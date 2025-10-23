/// Video upload and streaming handlers (Phase 4)
///
/// API endpoints for video uploads, metadata management, and streaming
use actix_web::{web, HttpRequest, HttpResponse};
use serde_json::json;
use uuid::Uuid;

use crate::error::Result;
use crate::models::video::*;
use crate::services::video_service::VideoService;
use crate::services::deep_learning_inference::DeepLearningInferenceService;
use tracing::{debug, info};
use crate::middleware::UserId;
use crate::db::video_repo;
use crate::config::video_config::VideoConfig;
use crate::services::streaming_manifest::StreamingManifestGenerator;

/// POST /api/v1/videos/upload-url
///
/// Generate a presigned S3 URL for direct video upload
pub async fn generate_upload_url(
    _req: HttpRequest,
    auth: UserId,
    video_service: web::Data<VideoService>,
) -> Result<HttpResponse> {
    let user_id = auth.0;

    let response = video_service.generate_upload_url(user_id).await?;

    info!(
        "Generated upload URL for user: {} (video: {})",
        user_id, response.video_id
    );

    Ok(HttpResponse::Ok().json(response))
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
    tokio::spawn(async move {
        // Seed pipeline status
        let _ = video_repo::upsert_pipeline_status(pool_clone.get_ref(), entity.id, "processing", 5, "queued", None).await;
        // Simulate stages
        let _ = video_repo::upsert_pipeline_status(pool_clone.get_ref(), entity.id, "validating", 20, "validating video", None).await;
        let _ = video_repo::upsert_pipeline_status(pool_clone.get_ref(), entity.id, "transcoding", 60, "transcoding variants", None).await;
        let _ = video_repo::upsert_pipeline_status(pool_clone.get_ref(), entity.id, "completed", 100, "completed", None).await;
    });

    Ok(HttpResponse::Created().json(json!({
        "video_id": entity.id,
        "status": entity.status,
        "created_at": entity.created_at,
        "title": entity.title,
        "hashtags": entity.get_hashtags(),
    })))
}

/// GET /api/v1/videos/:id
///
/// Get video metadata and engagement statistics
pub async fn get_video(path: web::Path<String>, pool: web::Data<sqlx::PgPool>, _req: HttpRequest) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner()).map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
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
    let id = Uuid::parse_str(&path.into_inner()).map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
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
pub async fn delete_video(path: web::Path<String>, pool: web::Data<sqlx::PgPool>, _req: HttpRequest) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner()).map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    info!("Deleting video: {}", id);
    let deleted = video_repo::soft_delete_video(pool.get_ref(), id).await?;
    if deleted { Ok(HttpResponse::NoContent().finish()) } else { Ok(HttpResponse::NotFound().finish()) }
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
    debug!("Getting stream manifest for video: {} (format: {})", video_id, format);
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
    let content_type = if format == "dash" { "application/dash+xml" } else { "application/vnd.apple.mpegurl" };
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
    let id = Uuid::parse_str(&video_id).map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
    if let Some((stage, progress, step, error)) = video_repo::get_pipeline_status(pool.get_ref(), id).await? {
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
pub async fn like_video(path: web::Path<String>, pool: web::Data<sqlx::PgPool>, _req: HttpRequest) -> Result<HttpResponse> {
    let id = Uuid::parse_str(&path.into_inner()).map_err(|e| crate::error::AppError::BadRequest(e.to_string()))?;
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
    let dim = dl.get_config_info()
        .get("embedding_dim")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(512);

    let query_embedding = if let Ok(Some(emb)) = dl.get_embedding_pg(pool.get_ref(), &video_id).await {
        emb.embedding
    } else {
        vec![0.0; dim]
    };

    // Prefer Milvus when enabled and healthy; fallback to PG
    let milvus_enabled = std::env::var("MILVUS_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
    let similar = if milvus_enabled && dl.check_milvus_health().await.unwrap_or(false) {
        match dl.find_similar_videos_milvus(&query_embedding, 10).await {
            Ok(res) if !res.is_empty() => res,
            _ => dl.find_similar_videos_pg(pool.get_ref(), &query_embedding, 10).await?,
        }
    } else {
        dl.find_similar_videos_pg(pool.get_ref(), &query_embedding, 10).await?
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
