/// Video handlers - HTTP endpoints for video operations
use actix_web::web;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

use crate::cache::MediaCache;
use crate::db::video_repo;
use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::models::{CreateVideoRequest, UpdateVideoRequest, VideoResponse};
use crate::services::VideoService;

/// List all videos
pub async fn list_videos(pool: web::Data<PgPool>) -> Result<actix_web::HttpResponse> {
    let videos = video_repo::list_recent(pool.get_ref(), 100).await?;

    let responses: Vec<VideoResponse> = videos.into_iter().map(|v| v.into()).collect();
    Ok(actix_web::HttpResponse::Ok().json(responses))
}

/// Get a specific video
pub async fn get_video(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    video_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let video_uuid = Uuid::parse_str(&video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    let service = VideoService::with_cache((**pool).clone(), cache.get_ref().clone());
    let video = service
        .get_video(video_uuid)
        .await?
        .ok_or(AppError::NotFound("Video not found".to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(VideoResponse::from(video)))
}

/// Create a new video
pub async fn create_video(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    user_id: UserId,
    req: web::Json<CreateVideoRequest>,
) -> Result<actix_web::HttpResponse> {
    if req.title.is_empty() {
        return Err(AppError::BadRequest("Title is required".to_string()));
    }

    let video_id = Uuid::new_v4();
    let visibility = req.visibility.as_deref().unwrap_or("public");
    let status = "uploading";

    let video = video_repo::create_video(
        pool.get_ref(),
        video_id,
        user_id.0,
        &req.title,
        req.description.as_deref(),
        visibility,
        status,
    )
    .await?;

    if let Err(err) = cache.cache_video(&video).await {
        tracing::debug!(video_id = %video.id, "video cache set failed: {}", err);
    }

    Ok(actix_web::HttpResponse::Created().json(VideoResponse::from(video)))
}

/// Update video metadata
pub async fn update_video(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    video_id: web::Path<String>,
    req: web::Json<UpdateVideoRequest>,
) -> Result<actix_web::HttpResponse> {
    let video_uuid = Uuid::parse_str(&video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    // Start with a fetch to ensure video exists
    let existing = video_repo::get_video(pool.get_ref(), video_uuid)
        .await?
        .ok_or(AppError::NotFound("Video not found".to_string()))?;

    // Update only provided fields
    let title = req.title.as_deref().unwrap_or(&existing.title);
    let description = req
        .description
        .as_deref()
        .or(existing.description.as_deref());
    let visibility = req
        .visibility
        .as_deref()
        .unwrap_or(existing.visibility.as_str());

    let updated_video =
        video_repo::update_video(pool.get_ref(), video_uuid, title, description, visibility)
            .await?;

    if let Err(err) = cache.cache_video(&updated_video).await {
        tracing::debug!(%video_uuid, "video cache set failed: {}", err);
    }

    Ok(actix_web::HttpResponse::Ok().json(VideoResponse::from(updated_video)))
}

/// Delete (soft delete) a video
pub async fn delete_video(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    video_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let video_uuid = Uuid::parse_str(&video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    if !video_repo::soft_delete(pool.get_ref(), video_uuid).await? {
        return Err(AppError::NotFound("Video not found".to_string()));
    }

    if let Err(err) = cache.invalidate_video(video_uuid).await {
        tracing::debug!(%video_uuid, "video cache invalidation failed: {}", err);
    }

    Ok(actix_web::HttpResponse::NoContent().finish())
}
