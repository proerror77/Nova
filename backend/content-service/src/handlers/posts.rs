/// Post handlers - HTTP endpoints for post operations
use crate::cache::ContentCache;
use crate::error::Result;
use crate::middleware::UserId;
use crate::services::PostService;
use actix_web::{web, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
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
    user_id: UserId,
    req: web::Json<CreatePostRequest>,
) -> Result<HttpResponse> {
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());

    // Use default values for text-only posts
    let image_key = req.image_key.as_deref().unwrap_or("text-only");
    let content_type = req.content_type.as_deref().unwrap_or("text/plain");

    let post = service
        .create_post(
            user_id.0,
            req.caption.as_deref(),
            image_key,
            content_type,
        )
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
    post_id: web::Path<Uuid>,
    user_id: UserId,
    req: web::Json<UpdatePostStatusRequest>,
) -> Result<HttpResponse> {
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());
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
    post_id: web::Path<Uuid>,
    user_id: UserId,
) -> Result<HttpResponse> {
    let service = PostService::with_cache((**pool).clone(), cache.get_ref().clone());
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
