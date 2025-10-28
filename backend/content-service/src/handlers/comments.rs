/// Comment handlers - HTTP endpoints for comment operations
use crate::error::Result;
use crate::services::CommentService;
use actix_web::{web, HttpResponse};
use sqlx::PgPool;
use uuid::Uuid;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct PaginationParams {
    pub limit: i64,
    pub offset: i64,
}

/// Create a new comment
pub async fn create_comment(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
    user_id: Uuid,
    req: web::Json<CreateCommentRequest>,
) -> Result<HttpResponse> {
    let service = CommentService::new((**pool).clone());
    let comment = service
        .create_comment(*post_id, user_id, &req.content, req.parent_comment_id)
        .await?;

    Ok(HttpResponse::Created().json(comment))
}

/// Get comments for a post
pub async fn get_post_comments(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = CommentService::new((**pool).clone());
    let comments = service
        .get_post_comments(*post_id, query.limit, query.offset)
        .await?;

    Ok(HttpResponse::Ok().json(comments))
}

/// Get a single comment
pub async fn get_comment(
    pool: web::Data<PgPool>,
    comment_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let service = CommentService::new((**pool).clone());
    match service.get_comment(*comment_id).await? {
        Some(comment) => Ok(HttpResponse::Ok().json(comment)),
        None => Ok(HttpResponse::NotFound().finish()),
    }
}

/// Get replies to a comment
pub async fn get_comment_replies(
    pool: web::Data<PgPool>,
    comment_id: web::Path<Uuid>,
    query: web::Query<PaginationParams>,
) -> Result<HttpResponse> {
    let service = CommentService::new((**pool).clone());
    let replies = service
        .get_comment_replies(*comment_id, query.limit, query.offset)
        .await?;

    Ok(HttpResponse::Ok().json(replies))
}

/// Update a comment
pub async fn update_comment(
    pool: web::Data<PgPool>,
    comment_id: web::Path<Uuid>,
    user_id: Uuid,
    req: web::Json<UpdateCommentRequest>,
) -> Result<HttpResponse> {
    let service = CommentService::new((**pool).clone());
    let updated = service
        .update_comment(*comment_id, user_id, &req.content)
        .await?;

    if updated {
        Ok(HttpResponse::Ok().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Delete a comment
pub async fn delete_comment(
    pool: web::Data<PgPool>,
    comment_id: web::Path<Uuid>,
    user_id: Uuid,
) -> Result<HttpResponse> {
    let service = CommentService::new((**pool).clone());
    let deleted = service.delete_comment(*comment_id, user_id).await?;

    if deleted {
        Ok(HttpResponse::NoContent().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// Request body for creating a comment
#[derive(Deserialize)]
pub struct CreateCommentRequest {
    pub content: String,
    pub parent_comment_id: Option<Uuid>,
}

/// Request body for updating a comment
#[derive(Deserialize)]
pub struct UpdateCommentRequest {
    pub content: String,
}
