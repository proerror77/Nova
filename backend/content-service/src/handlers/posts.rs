/// Post handlers - HTTP endpoints for post operations
use crate::cache::ContentCache;
use crate::error::{AppError, Result};
use crate::middleware::{AccountType, UserId};
use crate::services::PostService;
use actix_web::{web, HttpResponse};
use grpc_clients::GrpcClientPool;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use transactional_outbox::SqlxOutboxRepository;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct CreatePostRequest {
    pub caption: Option<String>,
    pub image_key: Option<String>,
    pub content_type: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PostResponse {
    pub id: Uuid,
    pub user_id: Uuid,
    pub caption: Option<String>,
    pub image_key: String,
    pub content_type: String,
    pub created_at: String,
}

/// Create a new post
pub async fn create_post(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    outbox_repo: web::Data<Arc<SqlxOutboxRepository>>,
    grpc_pool: web::Data<Arc<GrpcClientPool>>,
    user_id: UserId,
    account_type: AccountType,
    req: web::Json<CreatePostRequest>,
) -> Result<HttpResponse> {
    // Use default values for text-only posts
    let image_key = req.image_key.as_deref().unwrap_or("text-only");
    let content_type = req.content_type.as_deref().unwrap_or("text");

    // ✅ Phase F: Integrate Trust & Safety Service for content moderation
    // Call trust-safety-service to moderate content before creating post
    if let Some(caption_text) = &req.caption {
        use grpc_clients::nova::trust_safety::{
            ContentType as TsContentType, ModerateContentRequest, ModerationContext,
        };

        let mut trust_safety_client = grpc_pool.trust_safety();

        let moderation_req = ModerateContentRequest {
            content_id: Uuid::new_v4().to_string(), // Temporary ID for moderation
            content_type: TsContentType::Post as i32,
            text: caption_text.clone(),
            image_urls: vec![], // TODO: Add image URLs when available
            user_id: user_id.0.to_string(),
            context: Some(ModerationContext {
                seconds_since_last_post: 0, // TODO: Calculate from user's last post
                recent_post_count: 0,       // TODO: Query recent post count
                account_age_days: 0,        // TODO: Calculate from user creation date
                is_verified: false,         // TODO: Get from user service
            }),
        };

        match trust_safety_client.moderate_content(moderation_req).await {
            Ok(response) => {
                let moderation_result = response.into_inner();

                if !moderation_result.approved {
                    // Content rejected by moderation
                    tracing::warn!(
                        user_id = %user_id.0,
                        violations = ?moderation_result.violations,
                        "Content rejected by Trust & Safety moderation"
                    );

                    return Err(AppError::BadRequest(format!(
                        "Content violates community guidelines: {}. Violations: {}",
                        moderation_result.rejection_reason,
                        moderation_result.violations.join(", ")
                    )));
                }

                // Log moderation approval
                tracing::info!(
                    user_id = %user_id.0,
                    moderation_id = %moderation_result.moderation_id,
                    "Content approved by Trust & Safety moderation"
                );
            }
            Err(e) => {
                // Trust-safety service unavailable - log warning but allow post creation
                // This provides graceful degradation when trust-safety-service is not deployed
                tracing::warn!(
                    user_id = %user_id.0,
                    error = %e,
                    "Trust & Safety service unavailable - proceeding without moderation (graceful degradation)"
                );
            }
        }
    }

    let service = PostService::with_outbox(
        (**pool).clone(),
        cache.get_ref().clone(),
        outbox_repo.get_ref().clone(),
    );

    let post = service
        .create_post(user_id.0, req.caption.as_deref(), image_key, content_type, Some(&account_type.0))
        .await?;

    Ok(HttpResponse::Created().json(post))
}

/// Get a post by ID
pub async fn get_post(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    post_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());
    match service.get_post(*post_id).await? {
        Some(post) => Ok(HttpResponse::Ok().json(post)),
        None => Ok(HttpResponse::NotFound().finish()),
    }
}

/// Get posts for a user
pub async fn get_user_posts(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    user_id: web::Path<Uuid>,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());
    let posts = service
        .get_user_posts(*user_id, query.limit, query.offset)
        .await?;

    Ok(HttpResponse::Ok().json(posts))
}

#[derive(Debug, Deserialize)]
pub struct UpdatePostStatusRequest {
    pub status: String,
}

/// Update post status
pub async fn update_post_status(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    outbox_repo: web::Data<Arc<SqlxOutboxRepository>>,
    post_id: web::Path<Uuid>,
    user_id: UserId,
    req: web::Json<UpdatePostStatusRequest>,
) -> Result<HttpResponse> {
    let service = PostService::with_outbox(
        (**pool).clone(),
        cache.get_ref().clone(),
        outbox_repo.get_ref().clone(),
    );
    let updated = service
        .update_post_status(*post_id, user_id.0, &req.status)
        .await?;

    if updated {
        Ok(HttpResponse::Ok().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Delete a post
pub async fn delete_post(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    outbox_repo: web::Data<Arc<SqlxOutboxRepository>>,
    post_id: web::Path<Uuid>,
    user_id: UserId,
) -> Result<HttpResponse> {
    let service = PostService::with_outbox(
        (**pool).clone(),
        cache.get_ref().clone(),
        outbox_repo.get_ref().clone(),
    );
    let deleted = service.delete_post(*post_id, user_id.0).await?;

    if deleted {
        Ok(HttpResponse::NoContent().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Pagination query parameters
#[derive(serde::Deserialize)]
pub struct PaginationParams {
    pub limit: i64,
    pub offset: i64,
}

/// Request body for batch post fetching
#[derive(Debug, Deserialize)]
pub struct BatchPostsRequest {
    pub post_ids: Vec<Uuid>,
}

/// Response for batch post fetching
#[derive(Debug, Serialize)]
pub struct BatchPostsResponse {
    pub posts: Vec<crate::models::Post>,
    pub requested: usize,
    pub found: usize,
}

/// Get multiple posts by IDs in a single request
/// POST /api/v1/posts/batch
pub async fn get_posts_batch(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    req: web::Json<BatchPostsRequest>,
) -> Result<HttpResponse> {
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());

    let requested = req.post_ids.len();
    let posts = service.get_posts_batch(&req.post_ids).await?;
    let found = posts.len();

    Ok(HttpResponse::Ok().json(BatchPostsResponse {
        posts,
        requested,
        found,
    }))
}

/// Response for user liked/saved posts
#[derive(Debug, Serialize)]
pub struct UserPostsResponse {
    pub posts: Vec<crate::models::Post>,
    pub total_count: i64,
    pub has_more: bool,
}

/// Get posts liked by a user using SQL JOIN
/// GET /api/v1/posts/user/{user_id}/liked
pub async fn get_user_liked_posts(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    path: web::Path<Uuid>,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());

    let (posts, total) = service
        .get_user_liked_posts(user_id, query.limit, query.offset)
        .await?;

    let has_more = (query.offset + query.limit) < total;

    Ok(HttpResponse::Ok().json(UserPostsResponse {
        posts,
        total_count: total,
        has_more,
    }))
}

/// Get posts saved/bookmarked by a user using SQL JOIN
/// GET /api/v1/posts/user/{user_id}/saved
pub async fn get_user_saved_posts(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    path: web::Path<Uuid>,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());

    let (posts, total) = service
        .get_user_saved_posts(user_id, query.limit, query.offset)
        .await?;

    let has_more = (query.offset + query.limit) < total;

    Ok(HttpResponse::Ok().json(UserPostsResponse {
        posts,
        total_count: total,
        has_more,
    }))
}
