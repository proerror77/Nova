/// Video handlers - HTTP endpoints for video operations
use actix_web::web;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::models::{CreateVideoRequest, UpdateVideoRequest, Video, VideoResponse};

/// List all videos
pub async fn list_videos(pool: web::Data<PgPool>) -> Result<actix_web::HttpResponse> {
    let videos = sqlx::query_as::<_, Video>(
        "SELECT id, creator_id, title, description, duration_seconds, cdn_url, \
         thumbnail_url, status, visibility, created_at, updated_at \
         FROM videos WHERE deleted_at IS NULL \
         ORDER BY created_at DESC LIMIT 100"
    )
    .fetch_all(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    let responses: Vec<VideoResponse> = videos.into_iter().map(|v| v.into()).collect();
    Ok(actix_web::HttpResponse::Ok().json(responses))
}

/// Get a specific video
pub async fn get_video(
    pool: web::Data<PgPool>,
    video_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let video_uuid = Uuid::parse_str(&video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    let video = sqlx::query_as::<_, Video>(
        "SELECT id, creator_id, title, description, duration_seconds, cdn_url, \
         thumbnail_url, status, visibility, created_at, updated_at \
         FROM videos WHERE id = $1 AND deleted_at IS NULL"
    )
    .bind(video_uuid)
    .fetch_optional(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?
    .ok_or(AppError::NotFound("Video not found".to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(VideoResponse::from(video)))
}

/// Create a new video
pub async fn create_video(
    pool: web::Data<PgPool>,
    creator_id: Uuid,
    req: web::Json<CreateVideoRequest>,
) -> Result<actix_web::HttpResponse> {
    if req.title.is_empty() {
        return Err(AppError::BadRequest("Title is required".to_string()));
    }

    let video_id = Uuid::new_v4();
    let visibility = req.visibility.as_deref().unwrap_or("public");
    let status = "uploading";

    let video = sqlx::query_as::<_, Video>(
        "INSERT INTO videos (id, creator_id, title, description, duration_seconds, \
         cdn_url, thumbnail_url, status, visibility, created_at, updated_at) \
         VALUES ($1, $2, $3, $4, 0, NULL, NULL, $5, $6, NOW(), NOW()) \
         RETURNING id, creator_id, title, description, duration_seconds, cdn_url, \
         thumbnail_url, status, visibility, created_at, updated_at"
    )
    .bind(video_id)
    .bind(creator_id)
    .bind(&req.title)
    .bind(&req.description)
    .bind(status)
    .bind(visibility)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(actix_web::HttpResponse::Created().json(VideoResponse::from(video)))
}

/// Update video metadata
pub async fn update_video(
    pool: web::Data<PgPool>,
    video_id: web::Path<String>,
    req: web::Json<UpdateVideoRequest>,
) -> Result<actix_web::HttpResponse> {
    let video_uuid = Uuid::parse_str(&video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    // Start with a fetch to ensure video exists
    let existing = sqlx::query_as::<_, Video>(
        "SELECT id, creator_id, title, description, duration_seconds, cdn_url, \
         thumbnail_url, status, visibility, created_at, updated_at \
         FROM videos WHERE id = $1 AND deleted_at IS NULL"
    )
    .bind(video_uuid)
    .fetch_optional(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?
    .ok_or(AppError::NotFound("Video not found".to_string()))?;

    // Update only provided fields
    let title = req.title.as_ref().unwrap_or(&existing.title);
    let description = req.description.as_ref().or(existing.description.as_ref());
    let visibility = req.visibility.as_ref().unwrap_or(&existing.visibility);

    let updated_video = sqlx::query_as::<_, Video>(
        "UPDATE videos SET title = $2, description = $3, visibility = $4, updated_at = NOW() \
         WHERE id = $1 \
         RETURNING id, creator_id, title, description, duration_seconds, cdn_url, \
         thumbnail_url, status, visibility, created_at, updated_at"
    )
    .bind(video_uuid)
    .bind(title)
    .bind(description)
    .bind(visibility)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(VideoResponse::from(updated_video)))
}

/// Delete (soft delete) a video
pub async fn delete_video(
    pool: web::Data<PgPool>,
    video_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let video_uuid = Uuid::parse_str(&video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    let result = sqlx::query("UPDATE videos SET deleted_at = NOW(), updated_at = NOW() WHERE id = $1")
        .bind(video_uuid)
        .execute(pool.get_ref())
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Video not found".to_string()));
    }

    Ok(actix_web::HttpResponse::NoContent().finish())
}
