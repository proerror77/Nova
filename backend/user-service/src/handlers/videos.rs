/// Video upload and streaming handlers (Phase 4)
///
/// API endpoints for video uploads, metadata management, and streaming
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

use crate::config::{video_config::VideoConfig, Config};
use crate::db::video_repo;
use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::models::video::*;
use crate::services::deep_learning_inference::DeepLearningInferenceService;
use crate::services::streaming_manifest::StreamingManifestGenerator;
use crate::services::{s3_service, video_service::VideoService};
use crate::services::video_transcoding::VideoMetadata;
use tokio::io::AsyncWriteExt;
use tracing::{debug, info};

// ============================================
// Video Upload Endpoints (Two-Phase Upload)
// ============================================

/// Initialize video upload and generate presigned S3 URL
/// POST /api/v1/videos/upload/init
/// Protected: Requires valid JWT token in Authorization header
pub async fn video_upload_init(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    req: web::Json<VideoUploadInitRequest>,
) -> Result<HttpResponse> {
    use crate::db::video_repo;

    // ========================================
    // Validation
    // ========================================

    // Validate filename
    if req.filename.is_empty() {
        return Err(AppError::BadRequest("Filename is required".into()));
    }

    if req.filename.len() > 255 {
        return Err(AppError::BadRequest(format!(
            "Filename exceeds maximum allowed length (255 characters)"
        )));
    }

    // Validate content_type (only video formats)
    const ALLOWED_VIDEO_TYPES: &[&str] = &[
        "video/mp4",
        "video/quicktime",
        "video/x-msvideo",
        "video/webm",
        "video/mpeg",
    ];

    if !ALLOWED_VIDEO_TYPES.contains(&req.content_type.as_str()) {
        return Err(AppError::BadRequest(format!(
            "Content type must be one of: {}",
            ALLOWED_VIDEO_TYPES.join(", ")
        )));
    }

    // Validate file_size (min 1MB, max 500MB)
    const MIN_VIDEO_SIZE: i64 = 1048576; // 1 MB
    const MAX_VIDEO_SIZE: i64 = 524288000; // 500 MB

    if req.file_size < MIN_VIDEO_SIZE {
        return Err(AppError::BadRequest(format!(
            "File size must be at least {} bytes (1 MB)",
            MIN_VIDEO_SIZE
        )));
    }

    if req.file_size > MAX_VIDEO_SIZE {
        return Err(AppError::BadRequest(format!(
            "File size exceeds maximum allowed size ({} bytes / 500 MB)",
            MAX_VIDEO_SIZE
        )));
    }

    // Validate title
    if req.title.trim().is_empty() {
        return Err(AppError::BadRequest("Title is required".into()));
    }

    if req.title.len() > 200 {
        return Err(AppError::BadRequest(format!(
            "Title exceeds maximum allowed length (200 characters)"
        )));
    }

    // ========================================
    // Extract user_id from JWT middleware
    // ========================================

    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return Err(AppError::Authentication(
                "User ID not found in request. JWT middleware may not be active.".into(),
            ))
        }
    };

    // ========================================
    // Create video record with status="pending"
    // ========================================

    let hashtags = VideoService::parse_hashtags(req.hashtags.as_ref());
    let visibility = req.visibility.as_deref().unwrap_or("public");

    let video = video_repo::create_video(
        pool.get_ref(),
        user_id,
        &req.title,
        req.description.as_deref(),
        &serde_json::json!(hashtags),
        visibility,
    )
    .await
    .map_err(|e| {
        tracing::error!("Failed to create video record: {:?}", e);
        AppError::Internal("Database error".into())
    })?;

    // ========================================
    // Generate S3 presigned URL
    // ========================================

    let s3_key = format!("videos/{}/original.mp4", video.id);

    let s3_client = s3_service::get_s3_client(&config.s3).await?;

    let presigned_url =
        s3_service::generate_presigned_url(&s3_client, &config.s3, &s3_key, &req.content_type)
            .await?;

    // ========================================
    // Generate upload_token (32-byte hex)
    // ========================================

    use rand::Rng;
    let mut rng = rand::thread_rng();
    let token_bytes: [u8; 32] = rng.gen();
    let upload_token = hex::encode(token_bytes);

    // ========================================
    // Create upload session with 1-hour expiry
    // ========================================

    video_repo::create_video_upload_session(pool.get_ref(), video.id, &upload_token)
        .await
        .map_err(|e| {
            tracing::error!("Failed to create video upload session: {:?}", e);
            AppError::Internal("Database error".into())
        })?;

    // ========================================
    // Return response
    // ========================================

    info!(
        "Generated video upload URL for user: {} (video: {})",
        user_id, video.id
    );

    Ok(HttpResponse::Created().json(VideoUploadInitResponse {
        presigned_url,
        video_id: video.id.to_string(),
        upload_token,
        expires_in: 900,
        instructions: "Use PUT method to upload video file to presigned_url".to_string(),
    }))
}

/// Complete video upload and verify file integrity
/// POST /api/v1/videos/upload/complete
pub async fn video_upload_complete(
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    job_sender: web::Data<crate::services::video_job_queue::VideoJobSender>,
    req: web::Json<VideoUploadCompleteRequest>,
) -> Result<HttpResponse> {
    use crate::db::video_repo;

    // ========================================
    // Validation
    // ========================================

    // Validate video_id is valid UUID
    let video_id = Uuid::parse_str(&req.video_id)
        .map_err(|_| AppError::BadRequest("Invalid video_id format".into()))?;

    // Validate upload_token is not empty
    if req.upload_token.is_empty() {
        return Err(AppError::BadRequest("Upload token is required".into()));
    }

    // Validate upload_token max length (512 chars)
    if req.upload_token.len() > 512 {
        return Err(AppError::BadRequest(
            "Upload token exceeds maximum length (512 characters)".into(),
        ));
    }

    // Validate file_hash is exactly 64 characters (SHA256)
    if req.file_hash.len() != 64 {
        return Err(AppError::BadRequest(
            "File hash must be exactly 64 characters (SHA256)".into(),
        ));
    }

    // Validate file_hash is valid hex string
    if !req.file_hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(AppError::BadRequest(
            "File hash must contain only hexadecimal characters".into(),
        ));
    }

    // Validate file_size is within bounds
    const MIN_VIDEO_SIZE: i64 = 1048576; // 1 MB
    const MAX_VIDEO_SIZE: i64 = 524288000; // 500 MB

    if req.file_size < MIN_VIDEO_SIZE {
        return Err(AppError::BadRequest(format!(
            "File size must be at least {} bytes (1 MB)",
            MIN_VIDEO_SIZE
        )));
    }

    if req.file_size > MAX_VIDEO_SIZE {
        return Err(AppError::BadRequest(format!(
            "File size exceeds maximum allowed size ({} bytes / 500 MB)",
            MAX_VIDEO_SIZE
        )));
    }

    // ========================================
    // Upload Completion Flow
    // ========================================

    // a. Find upload_session by token
    let upload_session = video_repo::find_video_upload_session_by_token(pool.get_ref(), &req.upload_token)
        .await
        .map_err(|e| {
            tracing::error!("Failed to find video upload session: {:?}", e);
            AppError::Internal("Database error".into())
        })?
        .ok_or_else(|| AppError::NotFound("Invalid or expired upload token".into()))?;

    // b. Verify token hasn't already been completed
    if upload_session.is_completed {
        return Err(AppError::BadRequest(
            "Upload already completed. This upload token has already been used.".into(),
        ));
    }

    // c. Verify video_id matches upload_session
    if upload_session.video_id != video_id {
        return Err(AppError::BadRequest(
            "Video ID does not match upload session".into(),
        ));
    }

    // d. Get S3 key from videos table: "videos/{video_id}/original.mp4"
    let s3_key = format!("videos/{}/original.mp4", video_id);

    // e. Create S3 client
    let s3_client = s3_service::get_s3_client(&config.s3).await?;

    // f. Verify file exists in S3
    let exists = s3_service::verify_s3_object_exists(&s3_client, &config.s3, &s3_key).await?;

    if !exists {
        return Err(AppError::Internal(
            "File not found in S3. Upload may have failed.".into(),
        ));
    }

    // g. Verify file hash
    let hash_matches =
        s3_service::verify_file_hash(&s3_client, &config.s3, &s3_key, &req.file_hash).await?;

    if !hash_matches {
        return Err(AppError::BadRequest(
            "File integrity check failed. File hash does not match uploaded file.".into(),
        ));
    }

    // Record validated file hash for auditing
    video_repo::update_video_session_file_hash(
        pool.get_ref(),
        upload_session.id,
        &req.file_hash,
        req.file_size,
    )
    .await
    .map_err(|e| {
        tracing::error!(
            "Failed to persist file hash for upload_session {}: {:?}",
            upload_session.id,
            e
        );
        AppError::Internal("Database error".into())
    })?;

    // h. Mark upload_session as completed
    video_repo::mark_video_upload_completed(pool.get_ref(), upload_session.id)
        .await
        .map_err(|e| {
            tracing::error!("Failed to mark upload as completed: {:?}", e);
            AppError::Internal("Database error".into())
        })?;

    // i. Update video status to "processing"
    video_repo::update_video_status(pool.get_ref(), video_id, "processing")
        .await
        .map_err(|e| {
            tracing::error!("Failed to update video status: {:?}", e);
            AppError::Internal("Database error".into())
        })?;

    // j. Get user_id from video record
    let user_id: Uuid = sqlx::query_scalar("SELECT creator_id FROM videos WHERE id = $1")
        .bind(video_id)
        .fetch_one(pool.get_ref())
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch creator_id for video {}: {:?}", video_id, e);
            AppError::Internal("Database error".into())
        })?;

    // k. Submit video processing job to queue
    let job = crate::services::video_job_queue::VideoProcessingJob {
        video_id,
        user_id,
        upload_token: req.upload_token.clone(),
        source_s3_key: s3_key.clone(),
    };

    // Send job to queue (non-blocking)
    match job_sender.send(job).await {
        Ok(_) => {
            info!(
                "Video processing job submitted for video_id={}, user_id={}",
                video_id, user_id
            );
        }
        Err(e) => {
            tracing::error!(
                "Failed to submit video processing job for video_id={}: {:?}",
                video_id,
                e
            );
            // Don't fail the request - mark video as failed and return success
            // The client uploaded successfully, but processing will be retried later
            if let Err(db_err) =
                video_repo::update_video_status(pool.get_ref(), video_id, "failed").await
            {
                tracing::error!("Failed to update video status to 'failed': {:?}", db_err);
            }
        }
    }

    // l. Return 200 with response
    Ok(HttpResponse::Ok().json(VideoUploadCompleteResponse {
        video_id: video_id.to_string(),
        status: "processing".to_string(),
        message: "Upload complete. Video processing in progress.".to_string(),
        video_key: s3_key,
    }))
}

/// POST /api/v1/videos/:id/processing/complete
/// Mark processing as complete with provided metadata and generate embeddings (ffprobe-based)
#[derive(Debug, serde::Deserialize)]
pub struct ProcessingCompleteRequest {
    pub duration_seconds: u32,
    pub width: u32,
    pub height: u32,
    pub bitrate_kbps: u32,
    pub fps: f32,
    pub video_codec: String,
    pub visibility: Option<String>,
    #[serde(default)]
    pub file_url: Option<String>,
}

pub async fn processing_complete(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    dl: web::Data<DeepLearningInferenceService>,
    body: web::Json<ProcessingCompleteRequest>,
) -> Result<HttpResponse> {
    let video_id = uuid::Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;

    let _ = video_repo::upsert_pipeline_status(
        pool.get_ref(),
        video_id,
        "completed",
        100,
        "completed",
        None,
    )
    .await;

    let meta = VideoMetadata {
        duration_seconds: body.duration_seconds,
        video_codec: body.video_codec.clone(),
        resolution: (body.width, body.height),
        frame_rate: body.fps,
        bitrate_kbps: body.bitrate_kbps,
        audio_codec: None,
        audio_sample_rate: None,
    };

    // Prefer file-based features when file_url is provided; fallback to metadata
    let embedding = if let Some(url) = &body.file_url {
        // If it's an http(s) URL, download to /tmp first, then probe; otherwise treat as local path
        let mut downloaded_path: Option<std::path::PathBuf> = None;
        let probe_path: std::path::PathBuf = if url.starts_with("http://")
            || url.starts_with("https://")
        {
            let tmp_path = std::path::PathBuf::from(format!("/tmp/nova_video_{}.bin", video_id));
            match reqwest::Client::new().get(url).send().await {
                Ok(resp) if resp.status().is_success() => match resp.bytes().await {
                    Ok(bytes) => match tokio::fs::File::create(&tmp_path).await {
                        Ok(mut f) => {
                            if let Err(e) = f.write_all(&bytes).await {
                                tracing::warn!("Failed writing downloaded file: {}", e);
                            } else {
                                downloaded_path = Some(tmp_path.clone());
                            }
                        }
                        Err(e) => tracing::warn!("Failed creating tmp file: {}", e),
                    },
                    Err(e) => tracing::warn!("Failed reading response body: {}", e),
                },
                Ok(resp) => {
                    tracing::warn!("Download failed: {} {}", resp.status(), resp.url());
                }
                Err(e) => tracing::warn!("HTTP download error: {}", e),
            }
            if let Some(p) = downloaded_path.as_ref() {
                p.clone()
            } else {
                std::path::PathBuf::from(url)
            }
        } else {
            std::path::PathBuf::from(url)
        };

        let res = dl
            .generate_embeddings_from_file(&video_id.to_string(), probe_path.as_path())
            .await;

        // Best-effort cleanup
        if let Some(p) = downloaded_path.as_ref() {
            if let Err(e) = tokio::fs::remove_file(p).await {
                tracing::debug!("cleanup tmp file failed: {}", e);
            }
        }

        match res {
            Ok(e) => e,
            Err(e) => {
                tracing::warn!("ffprobe failed for {}: {}. Fallback to metadata.", url, e);
                dl.generate_embeddings_from_metadata(&video_id.to_string(), &meta)
                    .await?
            }
        }
    } else {
        dl.generate_embeddings_from_metadata(&video_id.to_string(), &meta)
            .await?
    };

    let milvus_enabled =
        std::env::var("MILVUS_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
    if milvus_enabled && dl.check_milvus_health().await.unwrap_or(false) {
        if let Err(e) = dl.insert_embeddings_milvus(&[embedding.clone()]).await {
            tracing::warn!("Milvus insert failed: {}. Fallback to PG.", e);
            dl.insert_embeddings_pg(pool.get_ref(), &[embedding])
                .await?;
        }
    } else {
        dl.insert_embeddings_pg(pool.get_ref(), &[embedding])
            .await?;
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "video_id": video_id,
        "status": "processing_completed",
        "embedding_dim": 512
    })))
}

/// POST /api/v1/videos
///
/// Create video metadata and initiate processing
pub async fn create_video(
    _req: HttpRequest,
    auth: UserId,
    pool: web::Data<sqlx::PgPool>,
    body: web::Json<CreateVideoRequest>,
    video_service: web::Data<VideoService>,
    dl: web::Data<DeepLearningInferenceService>,
) -> Result<HttpResponse> {
    // Validate metadata
    video_service
        .validate_video_metadata(&body.title, body.description.as_deref(), 300)
        .await?;

    // Parse hashtags
    let hashtags = VideoService::parse_hashtags(body.hashtags.as_ref());

    info!(
        "Creating video: title={}, hashtags={}",
        body.title,
        hashtags.len()
    );

    let creator_id = auth.0;
    let visibility = body.visibility.as_deref().unwrap_or("public");
    let entity = video_repo::create_video(
        pool.get_ref(),
        creator_id,
        &body.title,
        body.description.as_deref(),
        &serde_json::json!(hashtags),
        visibility,
    )
    .await?;

    // Fire-and-forget start processing (placeholder)
    let pool_clone = pool.clone();
    let dl_clone = dl.clone();
    tokio::spawn(async move {
        // Seed pipeline status
        let _ = video_repo::upsert_pipeline_status(
            pool_clone.get_ref(),
            entity.id,
            "processing",
            5,
            "queued",
            None,
        )
        .await;
        // Simulate stages
        let _ = video_repo::upsert_pipeline_status(
            pool_clone.get_ref(),
            entity.id,
            "validating",
            20,
            "validating video",
            None,
        )
        .await;
        let _ = video_repo::upsert_pipeline_status(
            pool_clone.get_ref(),
            entity.id,
            "transcoding",
            60,
            "transcoding variants",
            None,
        )
        .await;
        let _ = video_repo::upsert_pipeline_status(
            pool_clone.get_ref(),
            entity.id,
            "completed",
            100,
            "completed",
            None,
        )
        .await;

        // Embedding generation moved to /processing/complete callback.
    });

    Ok(HttpResponse::Created().json(json!({
        "video_id": entity.id,
        "status": entity.status,
        "created_at": entity.created_at,
        "title": entity.title,
        "hashtags": entity.get_hashtags(),
    })))
}

/// POST /api/v1/videos/:id/embedding/rebuild
/// Force rebuild embedding for a given video (admin/ops)
pub async fn rebuild_embedding(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    dl: web::Data<DeepLearningInferenceService>,
) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    // Generate synthetic feature vector (until ffprobe/file path is available)
    let mut features = vec![0.0f32; 512];
    features[0] = 1.0;
    features[1] = 1.0;
    features[2] = 0.25;
    features[3] = 0.5;
    features[4] = 0.5;
    features[5] = 1.0;
    let emb = dl.generate_embeddings(&id.to_string(), features).await?;

    let milvus_enabled =
        std::env::var("MILVUS_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
    if milvus_enabled && dl.check_milvus_health().await.unwrap_or(false) {
        if let Err(e) = dl.insert_embeddings_milvus(&[emb.clone()]).await {
            tracing::warn!("Milvus insert failed: {}. Falling back to PG.", e);
            dl.insert_embeddings_pg(pool.get_ref(), &[emb]).await?;
        }
    } else {
        dl.insert_embeddings_pg(pool.get_ref(), &[emb]).await?;
    }

    Ok(HttpResponse::Ok().json(json!({
        "video_id": id,
        "rebuild": "ok"
    })))
}

/// GET /api/v1/videos/:id
///
/// Get video metadata and engagement statistics
pub async fn get_video(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    info!("Fetching video: {}", id);
    if let Some(v) = video_repo::get_video(pool.get_ref(), id).await? {
        return Ok(HttpResponse::Ok().json(json!({
            "id": v.id,
            "creator_id": v.creator_id,
            "title": v.title,
            "description": v.description,
            "duration_seconds": v.duration_seconds,
            "status": v.status,
            "content_type": v.content_type,
            "hashtags": v.get_hashtags(),
            "visibility": v.visibility,
            "created_at": v.created_at,
            "published_at": v.published_at
        })));
    }
    Ok(HttpResponse::NotFound().finish())
}

/// PATCH /api/v1/videos/:id
///
/// Update video metadata
pub async fn update_video(
    path: web::Path<String>,
    body: web::Json<UpdateVideoRequest>,
    pool: web::Data<sqlx::PgPool>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    info!("Updating video: {} (title: {:?})", id, body.title);
    let updated = video_repo::update_video(
        pool.get_ref(),
        id,
        body.title.as_deref(),
        body.description.as_deref(),
        body.hashtags.as_ref().map(|v| serde_json::json!(v)),
        body.visibility.as_deref(),
    )
    .await?;
    Ok(HttpResponse::Ok().json(json!({
        "id": updated.id,
        "title": updated.title,
        "visibility": updated.visibility,
        "updated_at": updated.updated_at
    })))
}

/// DELETE /api/v1/videos/:id
///
/// Soft-delete a video
pub async fn delete_video(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    info!("Deleting video: {}", id);
    let deleted = video_repo::soft_delete_video(pool.get_ref(), id).await?;
    if deleted {
        Ok(HttpResponse::NoContent().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}

/// GET /api/v1/videos/:id/stream
///
/// Get streaming manifest (HLS or DASH)
pub async fn get_stream_manifest(
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let video_id = path.into_inner();
    let format = query.get("format").map(|s| s.as_str()).unwrap_or("hls");
    debug!(
        "Getting stream manifest for video: {} (format: {})",
        video_id, format
    );
    // Build manifest using config
    let vc = VideoConfig::from_env();
    let gen = StreamingManifestGenerator::new(vc.streaming);
    let tiers = StreamingManifestGenerator::get_quality_tiers(&vc.processing.target_bitrates);
    let base_url = format!("{}/videos/{}", vc.cdn.endpoint_url, video_id);
    let duration = 300u32; // Placeholder duration, could be read from DB metadata
    let body = if format == "dash" {
        gen.generate_dash_mpd(&video_id, duration, tiers, &base_url)
    } else {
        gen.generate_hls_master_playlist(&video_id, duration, tiers, &base_url)
    };
    let content_type = if format == "dash" {
        "application/dash+xml"
    } else {
        "application/vnd.apple.mpegurl"
    };
    Ok(HttpResponse::Ok().content_type(content_type).body(body))
}

/// GET /api/v1/videos/:id/progress
///
/// Get video processing progress
pub async fn get_processing_progress(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let video_id = path.into_inner();
    debug!("Getting processing progress for video: {}", video_id);
    let id = Uuid::parse_str(&video_id)
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    if let Some((stage, progress, step, error)) =
        video_repo::get_pipeline_status(pool.get_ref(), id).await?
    {
        return Ok(HttpResponse::Ok().json(json!({
            "video_id": id,
            "stage": stage,
            "progress_percent": progress,
            "current_step": step,
            "error": error
        })));
    }
    Ok(HttpResponse::Ok().json(json!({
        "video_id": id,
        "stage": "unknown",
        "progress_percent": 0,
        "current_step": "",
        "error": null
    })))
}

/// POST /api/v1/videos/:id/like
///
/// Like a video
pub async fn like_video(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    info!("Liking video: {}", id);
    let engagement = video_repo::upsert_engagement(pool.get_ref(), id, 1).await?;
    Ok(HttpResponse::Ok().json(json!({
        "video_id": id,
        "like_count": engagement.like_count
    })))
}

/// POST /api/v1/videos/:id/share
///
/// Share a video
pub async fn share_video(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    _req: HttpRequest,
) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner())
        .map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    info!("Sharing video: {}", id);
    let engagement = video_repo::increment_share(pool.get_ref(), id).await?;
    Ok(HttpResponse::Ok().json(json!({
        "video_id": id,
        "share_count": engagement.share_count
    })))
}

/// GET /api/v1/videos/:id/similar
///
/// Return a list of similar videos using the embedding service.
pub async fn get_similar_videos(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    dl: web::Data<DeepLearningInferenceService>,
) -> Result<HttpResponse> {
    let video_id = path.into_inner();
    // Try to fetch existing embedding, otherwise use a zero vector as a basic query
    let dim = dl
        .get_config_info()
        .get("embedding_dim")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(512);

    let query_embedding =
        if let Ok(Some(emb)) = dl.get_embedding_pg(pool.get_ref(), &video_id).await {
            emb.embedding
        } else {
            vec![0.0; dim]
        };

    // Prefer Milvus when enabled and healthy; fallback to PG
    let milvus_enabled =
        std::env::var("MILVUS_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
    let similar = if milvus_enabled && dl.check_milvus_health().await.unwrap_or(false) {
        match dl.find_similar_videos_milvus(&query_embedding, 10).await {
            Ok(res) if !res.is_empty() => res,
            _ => {
                dl.find_similar_videos_pg(pool.get_ref(), &query_embedding, 10)
                    .await?
            }
        }
    } else {
        dl.find_similar_videos_pg(pool.get_ref(), &query_embedding, 10)
            .await?
    };
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "video_id": video_id,
        "similar_videos": similar,
    })))
}

// ========================================
// Helper Functions
// ========================================

/// Generate HLS (HTTP Live Streaming) manifest
fn generate_hls_manifest(video_id: &str) -> String {
    format!(
        "#EXTM3U\n\
         #EXT-X-VERSION:3\n\
         #EXT-X-TARGETDURATION:10\n\
         #EXTINF:10.0,\n\
         {}/720p/segment1.ts\n\
         #EXTINF:10.0,\n\
         {}/720p/segment2.ts\n\
         #EXT-X-ENDLIST",
        video_id, video_id
    )
}

/// Generate DASH (Dynamic Adaptive Streaming over HTTP) manifest
fn generate_dash_manifest(video_id: &str) -> String {
    format!(
        r#"<?xml version="1.0"?>
        <MPD>
          <Period>
            <AdaptationSet mimeType="video/mp4">
              <Representation bitrate="2500000">
                <BaseURL>{}/720p/manifest.mpd</BaseURL>
              </Representation>
              <Representation bitrate="1500000">
                <BaseURL>{}/480p/manifest.mpd</BaseURL>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>"#,
        video_id, video_id
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hls_manifest_generation() {
        let manifest = generate_hls_manifest("video-123");
        assert!(manifest.contains("#EXTM3U"));
        assert!(manifest.contains("video-123"));
        assert!(manifest.contains(".ts"));
    }

    #[test]
    fn test_dash_manifest_generation() {
        let manifest = generate_dash_manifest("video-456");
        assert!(manifest.contains("<?xml"));
        assert!(manifest.contains("MPD"));
        assert!(manifest.contains("video-456"));
    }
}
