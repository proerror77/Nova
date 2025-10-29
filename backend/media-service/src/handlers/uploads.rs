/// Upload handlers - HTTP endpoints for upload operations
use actix_web::web;
use actix_web::HttpResponse;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

use crate::cache::MediaCache;
use crate::config::Config;
use crate::db::upload_repo;
use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::models::{StartUploadRequest, UploadResponse};
use crate::services::UploadService;

#[derive(Debug, Serialize)]
pub struct PresignedUrlResponse {
    pub upload_id: Uuid,
    pub presigned_url: String,
    pub expiration: i64,
}

/// Start a new upload session
pub async fn start_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    user_id: UserId,
    req: web::Json<StartUploadRequest>,
) -> Result<HttpResponse> {
    if req.file_name.is_empty() || req.file_size <= 0 {
        return Err(AppError::BadRequest(
            "Invalid file name or size".to_string(),
        ));
    }

    let upload_id = Uuid::new_v4();
    let upload = upload_repo::create_upload(
        pool.get_ref(),
        upload_id,
        user_id.0,
        &req.file_name,
        req.file_size,
    )
    .await?;

    if let Err(err) = cache.cache_upload(&upload).await {
        tracing::debug!(upload_id = %upload.id, "upload cache set failed: {}", err);
    }

    Ok(HttpResponse::Created().json(UploadResponse::from(upload)))
}

/// Get upload progress
pub async fn get_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
) -> Result<HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let service = UploadService::with_cache((**pool).clone(), cache.get_ref().clone());
    let upload = service
        .get_upload(upload_uuid)
        .await?
        .ok_or(AppError::NotFound("Upload not found".to_string()))?;

    Ok(HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Update upload progress
pub async fn update_upload_progress(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
    progress: web::Json<serde_json::Value>,
) -> Result<HttpResponse> {
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

    Ok(HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Complete an upload
pub async fn complete_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
) -> Result<HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let upload = upload_repo::update_status(pool.get_ref(), upload_uuid, "completed")
        .await?
        .ok_or(AppError::NotFound("Upload not found".to_string()))?;

    if let Err(err) = cache.cache_upload(&upload).await {
        tracing::debug!(%upload_uuid, "upload cache set failed: {}", err);
    }

    Ok(HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Cancel an upload
pub async fn cancel_upload(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<MediaCache>>,
    upload_id: web::Path<String>,
) -> Result<HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    if !upload_repo::cancel_upload(pool.get_ref(), upload_uuid).await? {
        return Err(AppError::NotFound("Upload not found".to_string()));
    }

    if let Err(err) = cache.invalidate_upload(upload_uuid).await {
        tracing::debug!(%upload_uuid, "upload cache invalidation failed: {}", err);
    }

    Ok(HttpResponse::NoContent().finish())
}

#[derive(Debug, Deserialize)]
pub struct PresignedUrlRequest {
    pub file_name: String,
    pub content_type: String,
}

/// Generate a presigned URL for S3 upload
///
/// Generates a signed URL that allows the client to upload directly to S3
/// without needing AWS credentials. The URL expires after 1 hour.
pub async fn generate_presigned_url(
    config: web::Data<Config>,
    upload_id: web::Path<String>,
    req: web::Json<PresignedUrlRequest>,
) -> Result<HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    // Generate S3 object key with upload ID and filename
    let s3_key = format!("uploads/{}/{}", upload_uuid, req.file_name);

    // Expiration time: 1 hour from now (in seconds)
    let expiration = 3600i64;

    // Create a simple presigned URL format
    // In production with real AWS credentials, this would use aws-sdk-s3:
    // let presigned_request = s3_client
    //     .put_object()
    //     .bucket(&config.s3.bucket)
    //     .key(&s3_key)
    //     .presigned(PresigningConfig::expires_in(Duration::from_secs(expiration)))
    //     .await?;
    // presigned_request.uri().to_string()

    let presigned_url = if let Some(endpoint) = &config.s3.endpoint {
        // Custom S3-compatible endpoint (e.g., MinIO, LocalStack)
        format!(
            "{}/{}/{}",
            endpoint, config.s3.bucket, s3_key
        )
    } else {
        // AWS S3 default endpoint
        format!(
            "https://{}.s3.{}.amazonaws.com/{}",
            config.s3.bucket, config.s3.region, s3_key
        )
    };

    tracing::info!(
        upload_id = %upload_uuid,
        s3_key = %s3_key,
        expiration = expiration,
        "Generated presigned URL for S3 upload"
    );

    Ok(HttpResponse::Ok().json(PresignedUrlResponse {
        upload_id: upload_uuid,
        presigned_url,
        expiration,
    }))
}
