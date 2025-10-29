/// Upload handlers - HTTP endpoints for upload operations
use actix_web::web;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

use crate::cache::MediaCache;
use crate::db::upload_repo;
use crate::error::{AppError, Result};
use crate::models::{StartUploadRequest, UploadResponse};
use crate::services::UploadService;

/// Start a new upload session
pub async fn start_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    user_id: Uuid,
    req: web::Json<StartUploadRequest>,
) -> Result<actix_web::HttpResponse> {
    if req.file_name.is_empty() || req.file_size <= 0 {
        return Err(AppError::BadRequest(
            "Invalid file name or size".to_string(),
        ));
    }

    let upload_id = Uuid::new_v4();
    let upload = upload_repo::create_upload(
        pool.get_ref(),
        upload_id,
        user_id,
        &req.file_name,
        req.file_size,
    )
    .await?;

    if let Err(err) = cache.cache_upload(&upload).await {
        tracing::debug!(upload_id = %upload.id, "upload cache set failed: {}", err);
    }

    Ok(actix_web::HttpResponse::Created().json(UploadResponse::from(upload)))
}

/// Get upload progress
pub async fn get_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let service = UploadService::with_cache((**pool).clone(), cache.get_ref().clone());
    let upload = service
        .get_upload(upload_uuid)
        .await?
        .ok_or(AppError::NotFound("Upload not found".to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Update upload progress
pub async fn update_upload_progress(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
    progress: web::Json<serde_json::Value>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let uploaded_size: i64 = progress
        .get("uploaded_size")
        .and_then(|v| v.as_i64())
        .ok_or(AppError::BadRequest("Invalid uploaded_size".to_string()))?;

    let upload = upload_repo::update_uploaded_size(pool.get_ref(), upload_uuid, uploaded_size)
        .await?
        .ok_or(AppError::NotFound("Upload not found".to_string()))?;

    if let Err(err) = cache.cache_upload(&upload).await {
        tracing::debug!(%upload_uuid, "upload cache set failed: {}", err);
    }

    Ok(actix_web::HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Complete an upload
pub async fn complete_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let upload = upload_repo::update_status(pool.get_ref(), upload_uuid, "completed")
        .await?
        .ok_or(AppError::NotFound("Upload not found".to_string()))?;

    if let Err(err) = cache.cache_upload(&upload).await {
        tracing::debug!(%upload_uuid, "upload cache set failed: {}", err);
    }

    Ok(actix_web::HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Cancel an upload
pub async fn cancel_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    if !upload_repo::cancel_upload(pool.get_ref(), upload_uuid).await? {
        return Err(AppError::NotFound("Upload not found".to_string()));
    }

    if let Err(err) = cache.invalidate_upload(upload_uuid).await {
        tracing::debug!(%upload_uuid, "upload cache invalidation failed: {}", err);
    }

    Ok(actix_web::HttpResponse::NoContent().finish())
}
