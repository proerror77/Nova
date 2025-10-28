/// Post handlers - HTTP endpoints for post operations
use crate::error::Result;
use crate::services::PostService;
use actix_web::{web, HttpResponse};
use sqlx::PgPool;
use uuid::Uuid;

/// Create a new post
pub async fn create_post(
    pool: web::Data<PgPool>,
    user_id: Uuid,
    caption: Option<String>,
    image_key: String,
    content_type: String,
) -> Result<HttpResponse> {
    let service = PostService::new((**pool).clone());
    let post = service
        .create_post(user_id, caption.as_deref(), &image_key, &content_type)
        .await?;

    Ok(HttpResponse::Created().json(post))
}

/// Get a post by ID
pub async fn get_post(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let service = PostService::new((**pool).clone());
    match service.get_post(*post_id).await? {
        Some(post) => Ok(HttpResponse::Ok().json(post)),
        None => Ok(HttpResponse::NotFound().finish()),
    }
}

/// Get posts for a user
pub async fn get_user_posts(
    pool: web::Data<PgPool>,
    user_id: web::Path<Uuid>,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = PostService::new((**pool).clone());
    let posts = service
        .get_user_posts(*user_id, query.limit, query.offset)
        .await?;

    Ok(HttpResponse::Ok().json(posts))
}

/// Update post status
pub async fn update_post_status(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
    user_id: Uuid,
    status: String,
) -> Result<HttpResponse> {
    let service = PostService::new((**pool).clone());
    let updated = service.update_post_status(*post_id, user_id, &status).await?;

    if updated {
        Ok(HttpResponse::Ok().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Delete a post
pub async fn delete_post(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
    user_id: Uuid,
) -> Result<HttpResponse> {
    let service = PostService::new((**pool).clone());
    let deleted = service.delete_post(*post_id, user_id).await?;

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
