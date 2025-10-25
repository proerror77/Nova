/// Resumable Upload Handlers
///
/// API endpoints for chunked video upload with resume capability:
/// - POST /uploads/init: Initialize upload session
/// - PUT /uploads/{id}/chunks/{index}: Upload single chunk
/// - POST /uploads/{id}/complete: Complete upload and trigger processing
/// - GET /uploads/{id}: Get upload status and progress

use actix_multipart::Multipart;
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

use crate::config::Config;
use crate::db::upload_repo::{self, UploadStatus};
use crate::db::video_repo;
use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::services::resumable_upload_service::ResumableUploadService;
use crate::services::s3_service;

// ============================================
// Request/Response Models
// ============================================

#[derive(Debug, Deserialize)]
pub struct UploadInitRequest {
    pub file_name: String,
    pub file_size: i64,
    pub chunk_size: i32,
    // Optional video metadata
    pub title: Option<String>,
    pub description: Option<String>,
    pub hashtags: Option<Vec<String>>,
    pub visibility: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UploadInitResponse {
    pub upload_id: Uuid,
    pub chunks_total: i32,
    pub next_chunk_index: i32,
    pub expires_at: String,
}

#[derive(Debug, Serialize)]
pub struct UploadChunkResponse {
    pub chunk_index: i32,
    pub uploaded: bool,
    pub next_chunk_index: i32,
    pub progress_percent: f64,
}

#[derive(Debug, Deserialize)]
pub struct CompleteUploadRequest {
    pub chunks_uploaded: i32,
    pub final_hash: Option<String>,
    // Video metadata (if not provided during init)
    pub title: Option<String>,
    pub description: Option<String>,
    pub hashtags: Option<Vec<String>>,
    pub visibility: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CompleteUploadResponse {
    pub video_id: Uuid,
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct UploadStatusResponse {
    pub upload_id: Uuid,
    pub status: String,
    pub chunks_total: i32,
    pub chunks_uploaded: i32,
    pub progress_percent: f64,
    pub expires_at: String,
}

// ============================================
// Handlers
// ============================================

/// Initialize upload session
/// POST /api/v1/uploads/init
pub async fn upload_init(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    req: web::Json<UploadInitRequest>,
) -> Result<HttpResponse> {
    // Extract user_id from JWT
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("User ID not found".into()))?;

    // Validate inputs
    if req.file_name.is_empty() {
        return Err(AppError::BadRequest("file_name required".into()));
    }

    if req.file_size <= 0 {
        return Err(AppError::BadRequest("file_size must be positive".into()));
    }

    if req.chunk_size <= 0 {
        return Err(AppError::BadRequest("chunk_size must be positive".into()));
    }

    // Validate file size limits (max 5GB for resumable uploads)
    const MAX_FILE_SIZE: i64 = 5_368_709_120; // 5GB
    const MIN_FILE_SIZE: i64 = 1_048_576; // 1MB

    if req.file_size < MIN_FILE_SIZE {
        return Err(AppError::BadRequest(format!(
            "File size must be at least {} bytes (1 MB)",
            MIN_FILE_SIZE
        )));
    }

    if req.file_size > MAX_FILE_SIZE {
        return Err(AppError::BadRequest(format!(
            "File size exceeds maximum ({} bytes / 5 GB)",
            MAX_FILE_SIZE
        )));
    }

    // Validate chunk size (5MB min, 100MB max)
    const MIN_CHUNK_SIZE: i32 = 5_242_880; // 5MB
    const MAX_CHUNK_SIZE: i32 = 104_857_600; // 100MB

    if req.chunk_size < MIN_CHUNK_SIZE {
        return Err(AppError::BadRequest(format!(
            "Chunk size must be at least {} bytes (5 MB)",
            MIN_CHUNK_SIZE
        )));
    }

    if req.chunk_size > MAX_CHUNK_SIZE {
        return Err(AppError::BadRequest(format!(
            "Chunk size exceeds maximum ({} bytes / 100 MB)",
            MAX_CHUNK_SIZE
        )));
    }

    // Create upload session
    let upload = upload_repo::create_upload(
        pool.get_ref(),
        user_id,
        req.file_name.clone(),
        req.file_size,
        req.chunk_size,
    )
    .await
    .map_err(|e| AppError::Internal(format!("Failed to create upload: {}", e)))?;

    // Initialize S3 multipart upload
    let s3_client = s3_service::get_s3_client(&config.s3).await?;
    let s3_key = format!("uploads/{}/video", upload.id);

    ResumableUploadService::init_s3_multipart(
        &s3_client,
        &config.s3,
        pool.get_ref(),
        upload.id,
        &s3_key,
    )
    .await?;

    Ok(HttpResponse::Ok().json(UploadInitResponse {
        upload_id: upload.id,
        chunks_total: upload.chunks_total,
        next_chunk_index: 0,
        expires_at: upload.expires_at.to_rfc3339(),
    }))
}

/// Upload single chunk
/// PUT /api/v1/uploads/{upload_id}/chunks/{chunk_index}
pub async fn upload_chunk(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    path: web::Path<(Uuid, i32)>,
    mut payload: Multipart,
) -> Result<HttpResponse> {
    let (upload_id, chunk_index) = path.into_inner();

    // Extract user_id
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("User ID not found".into()))?;

    // Verify upload exists and belongs to user
    let upload = upload_repo::get_upload_by_user(pool.get_ref(), upload_id, user_id)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch upload: {}", e)))?
        .ok_or_else(|| AppError::NotFound("Upload not found".into()))?;

    // Check upload not expired
    if upload.expires_at < chrono::Utc::now() {
        return Err(AppError::BadRequest("Upload expired".into()));
    }

    // Check upload is still in uploading state
    if upload.status != UploadStatus::Uploading {
        return Err(AppError::BadRequest(format!(
            "Upload status is {:?}, cannot upload chunks",
            upload.status
        )));
    }

    // Validate chunk index
    ResumableUploadService::validate_chunk_index(chunk_index, upload.chunks_total)?;

    // Check if chunk already uploaded (idempotent)
    if let Some(existing_chunk) =
        upload_repo::get_chunk(pool.get_ref(), upload_id, chunk_index).await?
    {
        // Chunk already uploaded - return success (idempotent behavior)
        let next_index =
            ResumableUploadService::get_next_chunk_index(pool.get_ref(), upload_id).await?;
        let progress = ResumableUploadService::calculate_progress(
            upload.chunks_uploaded,
            upload.chunks_total,
        );

        return Ok(HttpResponse::Ok().json(UploadChunkResponse {
            chunk_index,
            uploaded: true,
            next_chunk_index: next_index,
            progress_percent: progress,
        }));
    }

    // Read chunk data from multipart
    let mut chunk_data = Vec::new();
    let mut chunk_hash: Option<String> = None;

    while let Some(field) = payload.next().await {
        let mut field = field.map_err(|e| AppError::BadRequest(format!("Multipart error: {}", e)))?;

        let field_name = field.name();

        match field_name {
            "chunk" => {
                // Read chunk bytes
                while let Some(chunk) = field.next().await {
                    let data =
                        chunk.map_err(|e| AppError::BadRequest(format!("Chunk read error: {}", e)))?;
                    chunk_data.extend_from_slice(&data);
                }
            }
            "hash" => {
                // Optional hash from client for verification
                while let Some(chunk) = field.next().await {
                    let data =
                        chunk.map_err(|e| AppError::BadRequest(format!("Hash read error: {}", e)))?;
                    chunk_hash = Some(String::from_utf8_lossy(&data).to_string());
                }
            }
            _ => {
                // Ignore unknown fields
            }
        }
    }

    if chunk_data.is_empty() {
        return Err(AppError::BadRequest("No chunk data provided".into()));
    }

    // Verify chunk hash if provided
    if let Some(ref expected_hash) = chunk_hash {
        if !ResumableUploadService::verify_chunk_hash(&chunk_data, expected_hash)? {
            return Err(AppError::BadRequest("Chunk hash mismatch".into()));
        }
    }

    // Upload chunk to S3
    let s3_client = s3_service::get_s3_client(&config.s3).await?;
    let s3_key = format!("uploads/{}/video", upload_id);
    let s3_upload_id = upload.s3_upload_id.as_ref().ok_or_else(|| {
        AppError::Internal("S3 upload ID missing - multipart not initialized".into())
    })?;

    ResumableUploadService::upload_chunk(
        &s3_client,
        &config.s3,
        pool.get_ref(),
        upload_id,
        s3_upload_id,
        &s3_key,
        chunk_index,
        chunk_data,
    )
    .await?;

    // Get updated progress
    let updated_upload = upload_repo::get_upload(pool.get_ref(), upload_id)
        .await?
        .ok_or_else(|| AppError::Internal("Upload disappeared".into()))?;

    let next_index =
        ResumableUploadService::get_next_chunk_index(pool.get_ref(), upload_id).await?;
    let progress = ResumableUploadService::calculate_progress(
        updated_upload.chunks_uploaded,
        updated_upload.chunks_total,
    );

    Ok(HttpResponse::Ok().json(UploadChunkResponse {
        chunk_index,
        uploaded: true,
        next_chunk_index: next_index,
        progress_percent: progress,
    }))
}

/// Complete upload and trigger video processing
/// POST /api/v1/uploads/{upload_id}/complete
pub async fn complete_upload(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    upload_id: web::Path<Uuid>,
    req: web::Json<CompleteUploadRequest>,
) -> Result<HttpResponse> {
    let upload_id = upload_id.into_inner();

    // Extract user_id
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("User ID not found".into()))?;

    // Verify upload belongs to user
    let upload = upload_repo::get_upload_by_user(pool.get_ref(), upload_id, user_id)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch upload: {}", e)))?
        .ok_or_else(|| AppError::NotFound("Upload not found".into()))?;

    // Verify all chunks uploaded
    if !ResumableUploadService::is_upload_complete(pool.get_ref(), upload_id).await? {
        return Err(AppError::BadRequest(format!(
            "Upload incomplete: {}/{} chunks uploaded",
            upload.chunks_uploaded, upload.chunks_total
        )));
    }

    // Complete S3 multipart upload
    let s3_client = s3_service::get_s3_client(&config.s3).await?;
    let s3_key = format!("uploads/{}/video", upload_id);
    let s3_upload_id = upload.s3_upload_id.as_ref().ok_or_else(|| {
        AppError::Internal("S3 upload ID missing".into())
    })?;

    ResumableUploadService::complete_s3_multipart(
        &s3_client,
        &config.s3,
        pool.get_ref(),
        upload_id,
        s3_upload_id,
        &s3_key,
    )
    .await?;

    // Create video record
    let title = req
        .title
        .clone()
        .unwrap_or_else(|| upload.file_name.clone());
    let hashtags = req.hashtags.clone().unwrap_or_default();
    let hashtags_json = serde_json::json!(hashtags);
    let visibility = req.visibility.as_deref().unwrap_or("public");

    let video = video_repo::create_video(
        pool.get_ref(),
        user_id,
        &title,
        req.description.as_deref(),
        &hashtags_json,
        visibility,
    )
    .await
    .map_err(|e| AppError::Internal(format!("Failed to create video: {}", e)))?;

    // Mark upload as completed and link to video
    let final_hash = req.final_hash.clone().unwrap_or_else(|| "".to_string());
    upload_repo::complete_upload(pool.get_ref(), upload_id, video.id, final_hash)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to mark upload complete: {}", e)))?;

    Ok(HttpResponse::Ok().json(CompleteUploadResponse {
        video_id: video.id,
        status: "processing".to_string(),
    }))
}

/// Get upload status
/// GET /api/v1/uploads/{upload_id}
pub async fn get_upload_status(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    upload_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let upload_id = upload_id.into_inner();

    // Extract user_id
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("User ID not found".into()))?;

    // Verify upload belongs to user
    let upload = upload_repo::get_upload_by_user(pool.get_ref(), upload_id, user_id)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch upload: {}", e)))?
        .ok_or_else(|| AppError::NotFound("Upload not found".into()))?;

    let progress = ResumableUploadService::calculate_progress(
        upload.chunks_uploaded,
        upload.chunks_total,
    );

    let status_str = match upload.status {
        UploadStatus::Uploading => "uploading",
        UploadStatus::Completed => "completed",
        UploadStatus::Failed => "failed",
        UploadStatus::Cancelled => "cancelled",
    };

    Ok(HttpResponse::Ok().json(UploadStatusResponse {
        upload_id: upload.id,
        status: status_str.to_string(),
        chunks_total: upload.chunks_total,
        chunks_uploaded: upload.chunks_uploaded,
        progress_percent: progress,
        expires_at: upload.expires_at.to_rfc3339(),
    }))
}

/// Cancel upload
/// DELETE /api/v1/uploads/{upload_id}
pub async fn cancel_upload(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    upload_id: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let upload_id = upload_id.into_inner();

    // Extract user_id
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("User ID not found".into()))?;

    // Verify upload belongs to user
    let upload = upload_repo::get_upload_by_user(pool.get_ref(), upload_id, user_id)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch upload: {}", e)))?
        .ok_or_else(|| AppError::NotFound("Upload not found".into()))?;

    // Abort S3 multipart upload if exists
    if let Some(s3_upload_id) = upload.s3_upload_id {
        let s3_client = s3_service::get_s3_client(&config.s3).await?;
        let s3_key = format!("uploads/{}/video", upload_id);

        // Ignore errors on abort (may already be completed/aborted)
        let _ = ResumableUploadService::abort_s3_multipart(
            &s3_client,
            &config.s3,
            &s3_upload_id,
            &s3_key,
        )
        .await;
    }

    // Mark upload as cancelled
    upload_repo::cancel_upload(pool.get_ref(), upload_id)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to cancel upload: {}", e)))?;

    Ok(HttpResponse::Ok().json(json!({
        "upload_id": upload_id,
        "status": "cancelled"
    })))
}
