/// Service layer for videos and uploads
///
/// This module provides business logic for:
/// - Video service: video lifecycle management
/// - Upload service: upload handling and resumable uploads
/// - Video module: GCS upload and management (migrated from video-service)
/// - Streaming module: HLS/DASH manifest generation for VOD (migrated from streaming-service)
/// - CDN module: Content delivery network management (migrated from cdn-service)
/// - Thumbnail module: Thumbnail generation for images using GCS
///
/// Extracted from user-service as part of P1.2 service splitting.
/// Enhanced with video-service GCS capabilities and streaming-service VOD manifests in Phase C: Media Consolidation.
pub mod cdn;
pub mod streaming;
pub mod thumbnail;
pub mod video;

use std::collections::HashMap;
use std::sync::Arc;

use sqlx::{PgPool, Postgres, Transaction};
use tokio::time::{sleep, Duration};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::cache::MediaCache;
use crate::db::{upload_repo, video_repo};
use crate::error::{AppError, Result};
use crate::models::{
    CreateReelRequest, Reel, ReelResponse, ReelTranscodeJob, ReelVariant, Upload, Video,
};

/// Video service for handling video operations
pub struct VideoService {
    pool: PgPool,
    cache: Option<Arc<MediaCache>>,
}

impl VideoService {
    /// Create a new VideoService
    pub fn new(pool: PgPool) -> Self {
        Self { pool, cache: None }
    }

    pub fn with_cache(pool: PgPool, cache: Arc<MediaCache>) -> Self {
        Self {
            pool,
            cache: Some(cache),
        }
    }

    fn cache(&self) -> Option<&Arc<MediaCache>> {
        self.cache.as_ref()
    }

    /// Get a video by ID
    pub async fn get_video(&self, video_id: Uuid) -> Result<Option<Video>> {
        if let Some(cache) = self.cache() {
            if let Some(video) = cache.get_video(video_id).await? {
                return Ok(Some(video));
            }
        }

        let video = video_repo::get_video(&self.pool, video_id).await?;

        if let (Some(cache), Some(ref video)) = (self.cache(), &video) {
            if let Err(err) = cache.cache_video(video).await {
                tracing::debug!(%video_id, "video cache set failed: {}", err);
            }
        }

        Ok(video)
    }

    /// Get user's videos
    pub async fn get_user_videos(&self, user_id: Uuid, limit: i32) -> Result<Vec<Video>> {
        video_repo::list_by_creator(&self.pool, user_id, limit).await
    }

    /// Update video status
    pub async fn update_video_status(&self, video_id: Uuid, status: &str) -> Result<bool> {
        let updated = video_repo::update_status(&self.pool, video_id, status).await?;

        if updated {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.invalidate_video(video_id).await {
                    tracing::debug!(%video_id, "video cache invalidation failed: {}", err);
                }
            }
        }

        Ok(updated)
    }
}

/// Upload service for handling upload operations
pub struct UploadService {
    pool: PgPool,
    cache: Option<Arc<MediaCache>>,
}

impl UploadService {
    /// Create a new UploadService
    pub fn new(pool: PgPool) -> Self {
        Self { pool, cache: None }
    }

    pub fn with_cache(pool: PgPool, cache: Arc<MediaCache>) -> Self {
        Self {
            pool,
            cache: Some(cache),
        }
    }

    fn cache(&self) -> Option<&Arc<MediaCache>> {
        self.cache.as_ref()
    }

    /// Get an upload by ID
    pub async fn get_upload(&self, upload_id: Uuid) -> Result<Option<Upload>> {
        if let Some(cache) = self.cache() {
            if let Some(upload) = cache.get_upload(upload_id).await? {
                return Ok(Some(upload));
            }
        }

        let upload = upload_repo::get_upload(&self.pool, upload_id).await?;

        if let (Some(cache), Some(ref upload)) = (self.cache(), &upload) {
            if let Err(err) = cache.cache_upload(upload).await {
                tracing::debug!(%upload_id, "upload cache set failed: {}", err);
            }
        }

        Ok(upload)
    }

    /// Get user's uploads
    pub async fn get_user_uploads(&self, user_id: Uuid, limit: i32) -> Result<Vec<Upload>> {
        upload_repo::get_user_uploads(&self.pool, user_id, limit).await
    }

    /// Update upload progress
    pub async fn update_progress(&self, upload_id: Uuid, uploaded_size: i64) -> Result<bool> {
        let updated =
            upload_repo::update_uploaded_size(&self.pool, upload_id, uploaded_size).await?;

        if let Some(ref upload) = updated {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.cache_upload(upload).await {
                    tracing::debug!(%upload_id, "upload cache set failed: {}", err);
                }
            }
        }

        Ok(updated.is_some())
    }

    /// Check if upload is complete
    pub async fn is_complete(&self, upload_id: Uuid) -> Result<bool> {
        upload_repo::is_complete(&self.pool, upload_id).await
    }
}

/// Reel service orchestrates data access for reel entities
pub struct ReelService {
    pool: PgPool,
}

impl ReelService {
    /// Create a new ReelService
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// List recent reels with hydrated variants + transcode jobs
    pub async fn list_reels(&self, limit: i64) -> Result<Vec<ReelResponse>> {
        let reels = sqlx::query_as::<_, Reel>(
            "SELECT id, creator_id, upload_id, caption, music_title, music_artist, music_id, \
                duration_seconds, visibility, status, processing_stage, processing_progress, \
                view_count, like_count, share_count, comment_count, allow_comments, allow_shares, \
                audio_track, cover_image_url, source_video_url, published_at, failed_at, \
                created_at, updated_at, deleted_at \
             FROM reels \
             WHERE deleted_at IS NULL \
             ORDER BY created_at DESC \
             LIMIT $1",
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        self.hydrate_reels(reels).await
    }

    /// Get a single reel by ID
    pub async fn get_reel(&self, reel_id: Uuid) -> Result<ReelResponse> {
        let reel = sqlx::query_as::<_, Reel>(
            "SELECT id, creator_id, upload_id, caption, music_title, music_artist, music_id, \
                duration_seconds, visibility, status, processing_stage, processing_progress, \
                view_count, like_count, share_count, comment_count, allow_comments, allow_shares, \
                audio_track, cover_image_url, source_video_url, published_at, failed_at, \
                created_at, updated_at, deleted_at \
             FROM reels \
             WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(reel_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Reel not found".to_string()))?;

        let mut hydrated = self.hydrate_reels(vec![reel]).await?;
        hydrated
            .pop()
            .ok_or_else(|| AppError::Internal("Failed to hydrate reel response".to_string()))
    }

    /// Create a new reel and enqueue transcoding pipeline
    pub async fn create_reel(
        &self,
        creator_id: Uuid,
        payload: CreateReelRequest,
        pipeline: &ReelTranscodePipeline,
    ) -> Result<ReelResponse> {
        if payload.upload_id.is_empty() {
            return Err(AppError::ValidationError("upload_id is required".into()));
        }

        let upload_uuid = Uuid::parse_str(&payload.upload_id)
            .map_err(|_| AppError::BadRequest("Invalid upload_id".into()))?;

        if let Some(duration) = payload.duration_seconds {
            if duration <= 0 {
                return Err(AppError::ValidationError(
                    "duration_seconds must be greater than zero".into(),
                ));
            }
        }

        let visibility = payload.visibility.as_deref().unwrap_or("public");
        if !matches!(visibility, "public" | "friends" | "private") {
            return Err(AppError::ValidationError(
                "visibility must be public, friends, or private".into(),
            ));
        }

        let allow_comments = payload.allow_comments.unwrap_or(true);
        let allow_shares = payload.allow_shares.unwrap_or(true);

        let mut tx: Transaction<'_, Postgres> = self.pool.begin().await?;

        let reel = sqlx::query_as::<_, Reel>(
            "INSERT INTO reels (
                creator_id,
                upload_id,
                caption,
                music_title,
                music_artist,
                duration_seconds,
                visibility,
                status,
                processing_stage,
                allow_comments,
                allow_shares,
                cover_image_url,
                created_at,
                updated_at
            )
            VALUES (
                $1, $2, $3, $4, $5, $6, $7,
                'processing', 'queued', $8, $9, $10, NOW(), NOW()
            )
            RETURNING id, creator_id, upload_id, caption, music_title, music_artist, music_id,
                duration_seconds, visibility, status, processing_stage, processing_progress,
                view_count, like_count, share_count, comment_count, allow_comments, allow_shares,
                audio_track, cover_image_url, source_video_url, published_at, failed_at,
                created_at, updated_at, deleted_at",
        )
        .bind(creator_id)
        .bind(upload_uuid)
        .bind(&payload.caption)
        .bind(&payload.music_title)
        .bind(&payload.music_artist)
        .bind(payload.duration_seconds)
        .bind(visibility)
        .bind(allow_comments)
        .bind(allow_shares)
        .bind(&payload.cover_image_url)
        .fetch_one(tx.as_mut())
        .await?;

        let profiles = pipeline.profiles();
        let mut jobs = Vec::with_capacity(profiles.len());
        for profile in profiles.iter() {
            let job = sqlx::query_as::<_, ReelTranscodeJob>(
                "INSERT INTO reel_transcode_jobs (reel_id, upload_id, target_quality)
                 VALUES ($1, $2, $3)
                 RETURNING id, reel_id, upload_id, target_quality, status, stage, progress,
                    retry_count, error_message, worker_id, started_at, finished_at,
                    created_at, updated_at",
            )
            .bind(reel.id)
            .bind(upload_uuid)
            .bind(profile.quality)
            .fetch_one(tx.as_mut())
            .await?;
            jobs.push(job);
        }

        tx.commit().await?;

        // Kick off asynchronous transcoding pipeline
        pipeline.enqueue_reel(reel.id, Some(upload_uuid)).await?;

        Ok(ReelResponse::from_entities(reel, Vec::new(), jobs))
    }

    /// Soft-delete a reel
    pub async fn delete_reel(&self, reel_id: Uuid) -> Result<()> {
        let result = sqlx::query(
            "UPDATE reels
             SET deleted_at = NOW(),
                 status = 'deleted',
                 updated_at = NOW()
             WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(reel_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Reel not found".into()));
        }
        Ok(())
    }

    async fn hydrate_reels(&self, reels: Vec<Reel>) -> Result<Vec<ReelResponse>> {
        if reels.is_empty() {
            return Ok(Vec::new());
        }

        let reel_ids: Vec<Uuid> = reels.iter().map(|r| r.id).collect();

        let variants = sqlx::query_as::<_, ReelVariant>(
            "SELECT id, reel_id, quality, codec, bitrate_kbps, width, height, frame_rate, \
                    cdn_url, file_size_bytes, is_default, created_at, updated_at \
             FROM reel_variants
             WHERE reel_id = ANY($1)",
        )
        .bind(&reel_ids)
        .fetch_all(&self.pool)
        .await?;

        let jobs = sqlx::query_as::<_, ReelTranscodeJob>(
            "SELECT id, reel_id, upload_id, target_quality, status, stage, progress, \
                    retry_count, error_message, worker_id, started_at, finished_at, \
                    created_at, updated_at
             FROM reel_transcode_jobs
             WHERE reel_id = ANY($1)
             ORDER BY created_at ASC",
        )
        .bind(&reel_ids)
        .fetch_all(&self.pool)
        .await?;

        let mut variant_map: HashMap<Uuid, Vec<ReelVariant>> = HashMap::new();
        for variant in variants {
            variant_map
                .entry(variant.reel_id)
                .or_default()
                .push(variant);
        }

        let mut job_map: HashMap<Uuid, Vec<ReelTranscodeJob>> = HashMap::new();
        for job in jobs {
            job_map.entry(job.reel_id).or_default().push(job);
        }

        Ok(reels
            .into_iter()
            .map(|reel| {
                let variants = variant_map.remove(&reel.id).unwrap_or_default();
                let jobs = job_map.remove(&reel.id).unwrap_or_default();
                ReelResponse::from_entities(reel, variants, jobs)
            })
            .collect())
    }
}

/// Adaptive bitrate presets for reel transcoding
#[derive(Debug, Clone)]
struct QualityProfile {
    quality: &'static str,
    width: i32,
    height: i32,
    bitrate_kbps: i32,
    frame_rate: f32,
    is_default: bool,
}

impl QualityProfile {
    fn default_profiles() -> Vec<Self> {
        vec![
            Self {
                quality: "1080p",
                width: 1080,
                height: 1920,
                bitrate_kbps: 6000,
                frame_rate: 30.0,
                is_default: true,
            },
            Self {
                quality: "720p",
                width: 720,
                height: 1280,
                bitrate_kbps: 3500,
                frame_rate: 30.0,
                is_default: false,
            },
            Self {
                quality: "480p",
                width: 480,
                height: 854,
                bitrate_kbps: 1800,
                frame_rate: 24.0,
                is_default: false,
            },
        ]
    }
}

/// Transcode pipeline orchestrates jobs asynchronously
///
/// Supports two modes:
/// - Mock mode (default): Simulates transcoding with delays, updates DB only
/// - Real mode: Uses GCP Transcoder API for actual video transcoding
///
/// Set `MEDIA_TRANSCODE_ENABLE_MOCK=false` and configure GCP credentials to enable real transcoding.
#[derive(Clone)]
pub struct ReelTranscodePipeline {
    pool: PgPool,
    profiles: Arc<Vec<QualityProfile>>,
    cdn_base_url: String,
    enable_mock: bool,
    gcs_bucket: Option<String>,
    gcp_project_id: Option<String>,
    gcp_location: Option<String>,
}

impl ReelTranscodePipeline {
    /// Build a new pipeline with defaults sourced from environment variables
    pub fn new(pool: PgPool) -> Self {
        let profiles = QualityProfile::default_profiles();
        let cdn_base_url =
            std::env::var("MEDIA_CDN_BASE_URL").unwrap_or_else(|_| "https://cdn.nova.local".into());
        let enable_mock = std::env::var("MEDIA_TRANSCODE_ENABLE_MOCK")
            .map(|val| val == "1" || val.eq_ignore_ascii_case("true"))
            .unwrap_or(true);

        Self {
            pool,
            profiles: Arc::new(profiles),
            cdn_base_url,
            enable_mock,
            gcs_bucket: std::env::var("GCS_BUCKET").ok(),
            gcp_project_id: std::env::var("GCP_PROJECT_ID").ok(),
            gcp_location: std::env::var("GCP_TRANSCODER_LOCATION").ok(),
        }
    }

    /// Return configured quality profiles
    fn profiles(&self) -> Arc<Vec<QualityProfile>> {
        Arc::clone(&self.profiles)
    }

    /// Check if real GCP transcoding is available
    fn is_gcp_transcoding_available(&self) -> bool {
        !self.enable_mock && self.gcs_bucket.is_some() && self.gcp_project_id.is_some()
    }

    /// Enqueue asynchronous processing for a reel
    pub async fn enqueue_reel(&self, reel_id: Uuid, upload_id: Option<Uuid>) -> Result<()> {
        let pool = self.pool.clone();
        let profiles = Arc::clone(&self.profiles);
        let cdn_base_url = self.cdn_base_url.clone();
        let enable_mock = self.enable_mock;
        let gcs_bucket = self.gcs_bucket.clone();
        let gcp_project_id = self.gcp_project_id.clone();
        let gcp_location = self.gcp_location.clone();

        tokio::spawn(async move {
            let use_gcp = !enable_mock && gcs_bucket.is_some() && gcp_project_id.is_some();

            let result = if use_gcp {
                // SAFETY: We checked is_some() above for gcs_bucket and gcp_project_id
                Self::process_reel_with_gcp(
                    pool,
                    reel_id,
                    upload_id,
                    profiles,
                    cdn_base_url,
                    gcs_bucket.expect("gcs_bucket checked above"),
                    gcp_project_id.expect("gcp_project_id checked above"),
                    gcp_location.unwrap_or_else(|| "us-central1".to_string()),
                )
                .await
            } else {
                Self::process_reel_mock(pool, reel_id, upload_id, profiles, cdn_base_url).await
            };

            if let Err(err) = result {
                error!(
                    "Reel transcoding failed: reel_id={}, error={}",
                    reel_id, err
                );
            }
        });

        Ok(())
    }

    /// Process reel using GCP Transcoder API
    async fn process_reel_with_gcp(
        pool: PgPool,
        reel_id: Uuid,
        upload_id: Option<Uuid>,
        profiles: Arc<Vec<QualityProfile>>,
        cdn_base_url: String,
        gcs_bucket: String,
        gcp_project_id: String,
        gcp_location: String,
    ) -> Result<()> {
        use crate::services::video::transcoder::{
            GcpTranscoderClient, TranscodeJobStatus, TranscodeProfile, TranscoderConfig,
        };

        let upload_id = match upload_id {
            Some(id) => id,
            None => {
                warn!("Reel {} missing upload_id. Marking as failed.", reel_id);
                mark_reel_failed(&pool, reel_id, "missing upload id").await?;
                return Ok(());
            }
        };

        // Get upload info to find source GCS URI
        let upload = sqlx::query_as::<_, Upload>(
            "SELECT id, user_id, filename, content_type, file_size, checksum, status,
                    upload_url, storage_path, created_at, updated_at, expires_at
             FROM uploads WHERE id = $1",
        )
        .bind(upload_id)
        .fetch_optional(&pool)
        .await?;

        let upload = match upload {
            Some(u) => u,
            None => {
                warn!("Upload {} not found for reel {}", upload_id, reel_id);
                mark_reel_failed(&pool, reel_id, "upload not found").await?;
                return Ok(());
            }
        };

        // Build input GCS URI from upload info
        // Format: gs://bucket/uploads/{user_id}/{upload_id}/{filename}
        let input_gcs_uri = format!(
            "gs://{}/uploads/{}/{}",
            gcs_bucket, upload.user_id, upload.file_name
        );

        info!(
            "Starting GCP transcoding for reel {}: input={}",
            reel_id, input_gcs_uri
        );

        // Update reel status
        sqlx::query(
            "UPDATE reels
             SET processing_stage = 'transcoding',
                 processing_progress = 5,
                 updated_at = NOW()
             WHERE id = $1 AND status <> 'deleted'",
        )
        .bind(reel_id)
        .execute(&pool)
        .await?;

        // Initialize GCP Transcoder client
        let transcoder_config = TranscoderConfig {
            project_id: gcp_project_id,
            location: gcp_location,
            gcs_bucket: gcs_bucket.clone(),
            cdn_base_url: cdn_base_url.clone(),
        };

        let mut transcoder = match GcpTranscoderClient::new(transcoder_config).await {
            Ok(client) => client,
            Err(e) => {
                error!("Failed to create GCP Transcoder client: {}", e);
                mark_reel_failed(&pool, reel_id, &format!("Transcoder client error: {}", e))
                    .await?;
                return Ok(());
            }
        };

        // Convert QualityProfile to TranscodeProfile
        let transcode_profiles: Vec<TranscodeProfile> = profiles
            .iter()
            .map(|p| TranscodeProfile {
                name: p.quality.to_string(),
                width: p.width,
                height: p.height,
                bitrate_kbps: p.bitrate_kbps,
                frame_rate: p.frame_rate,
                codec: "h264".to_string(),
            })
            .collect();

        // Create transcoding job
        let job_id = match transcoder
            .create_transcode_job(reel_id, &input_gcs_uri, &transcode_profiles)
            .await
        {
            Ok(id) => id,
            Err(e) => {
                error!("Failed to create transcode job: {}", e);
                mark_reel_failed(&pool, reel_id, &format!("Job creation failed: {}", e)).await?;
                return Ok(());
            }
        };

        info!(
            "GCP Transcoder job created: {} for reel {}",
            job_id, reel_id
        );

        // Update all transcode jobs with GCP job ID
        sqlx::query(
            "UPDATE reel_transcode_jobs
             SET status = 'processing',
                 stage = 'transcoding',
                 worker_id = $2,
                 started_at = NOW()
             WHERE reel_id = $1",
        )
        .bind(reel_id)
        .bind(&job_id)
        .execute(&pool)
        .await?;

        // Poll for job completion
        let poll_interval = std::time::Duration::from_secs(10);
        let max_wait = std::time::Duration::from_secs(3600); // 1 hour max
        let start_time = std::time::Instant::now();

        loop {
            let job_result = match transcoder.get_job_status(&job_id).await {
                Ok(r) => r,
                Err(e) => {
                    warn!("Failed to get job status: {}", e);
                    sleep(poll_interval).await;
                    continue;
                }
            };

            // Update progress in DB
            sqlx::query(
                "UPDATE reels
                 SET processing_progress = $2,
                     updated_at = NOW()
                 WHERE id = $1 AND status <> 'deleted'",
            )
            .bind(reel_id)
            .bind(job_result.progress.min(95) as i16)
            .execute(&pool)
            .await?;

            sqlx::query(
                "UPDATE reel_transcode_jobs
                 SET progress = $2
                 WHERE reel_id = $1 AND status = 'processing'",
            )
            .bind(reel_id)
            .bind(job_result.progress.min(95) as i16)
            .execute(&pool)
            .await?;

            match job_result.status {
                TranscodeJobStatus::Succeeded => {
                    info!("GCP Transcoder job {} succeeded", job_id);

                    // Create reel variants from outputs
                    for output in &job_result.output_uris {
                        let profile = profiles.iter().find(|p| p.quality == output.quality);
                        if let Some(profile) = profile {
                            sqlx::query(
                                "INSERT INTO reel_variants (
                                    reel_id, quality, codec, bitrate_kbps, width, height,
                                    frame_rate, cdn_url, file_size_bytes, is_default, created_at, updated_at
                                )
                                VALUES ($1, $2, 'h264', $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
                                ON CONFLICT (reel_id, quality) DO UPDATE
                                SET cdn_url = EXCLUDED.cdn_url,
                                    file_size_bytes = EXCLUDED.file_size_bytes,
                                    updated_at = NOW()",
                            )
                            .bind(reel_id)
                            .bind(&output.quality)
                            .bind(profile.bitrate_kbps)
                            .bind(profile.width)
                            .bind(profile.height)
                            .bind(profile.frame_rate)
                            .bind(&output.cdn_url)
                            .bind(output.file_size_bytes)
                            .bind(profile.is_default)
                            .execute(&pool)
                            .await?;
                        }
                    }

                    // Mark all jobs as completed
                    sqlx::query(
                        "UPDATE reel_transcode_jobs
                         SET status = 'completed',
                             stage = 'completed',
                             progress = 100,
                             finished_at = NOW()
                         WHERE reel_id = $1",
                    )
                    .bind(reel_id)
                    .execute(&pool)
                    .await?;

                    // Mark reel as published
                    sqlx::query(
                        "UPDATE reels
                         SET status = 'published',
                             processing_stage = 'completed',
                             processing_progress = 100,
                             published_at = COALESCE(published_at, NOW()),
                             updated_at = NOW()
                         WHERE id = $1 AND status <> 'deleted'",
                    )
                    .bind(reel_id)
                    .execute(&pool)
                    .await?;

                    info!("Reel {} transcoding completed successfully", reel_id);
                    return Ok(());
                }
                TranscodeJobStatus::Failed => {
                    let error_msg = job_result
                        .error_message
                        .unwrap_or_else(|| "Unknown error".to_string());
                    error!("GCP Transcoder job {} failed: {}", job_id, error_msg);
                    mark_reel_failed(&pool, reel_id, &error_msg).await?;
                    return Ok(());
                }
                _ => {
                    // Check timeout
                    if start_time.elapsed() > max_wait {
                        error!("Transcode job {} timed out after {:?}", job_id, max_wait);
                        mark_reel_failed(&pool, reel_id, "Transcoding timed out").await?;
                        return Ok(());
                    }
                    sleep(poll_interval).await;
                }
            }
        }
    }

    /// Process reel using mock/simulation mode (original behavior)
    async fn process_reel_mock(
        pool: PgPool,
        reel_id: Uuid,
        upload_id: Option<Uuid>,
        profiles: Arc<Vec<QualityProfile>>,
        cdn_base_url: String,
    ) -> Result<()> {
        if upload_id.is_none() {
            warn!(
                "Reel {} missing upload_id. Marking as failed before starting pipeline.",
                reel_id
            );
            mark_reel_failed(&pool, reel_id, "missing upload id").await?;
            return Ok(());
        }

        let jobs = sqlx::query_as::<_, ReelTranscodeJob>(
            "SELECT id, reel_id, upload_id, target_quality, status, stage, progress,
                    retry_count, error_message, worker_id, started_at, finished_at,
                    created_at, updated_at
             FROM reel_transcode_jobs
             WHERE reel_id = $1
             ORDER BY created_at ASC",
        )
        .bind(reel_id)
        .fetch_all(&pool)
        .await?;

        if jobs.is_empty() {
            warn!(
                "Reel {} has no queued transcode jobs. Marking as failed.",
                reel_id
            );
            mark_reel_failed(&pool, reel_id, "no transcode jobs queued").await?;
            return Ok(());
        }

        info!(
            "Processing reel {} in MOCK mode ({} jobs)",
            reel_id,
            jobs.len()
        );

        let total_jobs = jobs.len() as i16;

        for (index, job) in jobs.iter().enumerate() {
            let base_progress = (index as i16 * 100) / total_jobs.max(1);
            let completion_progress = ((index as i16 + 1) * 100) / total_jobs.max(1);
            let quality = &job.target_quality;

            // Stage: download
            sqlx::query(
                "UPDATE reel_transcode_jobs
                 SET status = 'processing',
                     stage = 'download',
                     progress = $2,
                     started_at = COALESCE(started_at, NOW())
                 WHERE id = $1",
            )
            .bind(job.id)
            .bind((base_progress + 5).min(95))
            .execute(&pool)
            .await?;

            sqlx::query(
                "UPDATE reels
                 SET processing_stage = $2,
                     processing_progress = $3,
                     updated_at = NOW()
                 WHERE id = $1 AND status <> 'deleted'",
            )
            .bind(reel_id)
            .bind(format!("download:{}", quality))
            .bind((base_progress + 5).min(95))
            .execute(&pool)
            .await?;

            sleep(Duration::from_millis(100)).await;

            // Stage: transcode
            sqlx::query(
                "UPDATE reel_transcode_jobs
                 SET stage = 'transcode',
                     progress = $2
                 WHERE id = $1",
            )
            .bind(job.id)
            .bind((base_progress + 45).min(98))
            .execute(&pool)
            .await?;

            sqlx::query(
                "UPDATE reels
                 SET processing_stage = $2,
                     processing_progress = $3
                 WHERE id = $1 AND status <> 'deleted'",
            )
            .bind(reel_id)
            .bind(format!("transcode:{}", quality))
            .bind((base_progress + 45).min(98))
            .execute(&pool)
            .await?;

            sleep(Duration::from_millis(150)).await;

            // Stage: package
            sqlx::query(
                "UPDATE reel_transcode_jobs
                 SET stage = 'package',
                     progress = $2
                 WHERE id = $1",
            )
            .bind(job.id)
            .bind((base_progress + 70).min(99))
            .execute(&pool)
            .await?;

            sqlx::query(
                "UPDATE reels
                 SET processing_stage = $2,
                     processing_progress = $3
                 WHERE id = $1 AND status <> 'deleted'",
            )
            .bind(reel_id)
            .bind(format!("package:{}", quality))
            .bind((base_progress + 70).min(99))
            .execute(&pool)
            .await?;

            sleep(Duration::from_millis(120)).await;

            // Create variant
            let profile = match profiles.iter().find(|p| p.quality == quality) {
                Some(profile) => profile,
                None => {
                    warn!(
                        "Unknown profile {} for reel {}. Skipping variant creation.",
                        quality, reel_id
                    );
                    continue;
                }
            };

            let cdn_url = format!(
                "{}/reels/{}/{}.mp4",
                cdn_base_url.trim_end_matches('/'),
                reel_id,
                profile.quality
            );

            sqlx::query(
                "INSERT INTO reel_variants (
                    reel_id, quality, codec, bitrate_kbps, width, height,
                    frame_rate, cdn_url, file_size_bytes, is_default, created_at, updated_at
                )
                VALUES ($1, $2, 'h264', $3, $4, $5, $6, $7, NULL, $8, NOW(), NOW())
                ON CONFLICT (reel_id, quality) DO UPDATE
                SET codec = EXCLUDED.codec,
                    bitrate_kbps = EXCLUDED.bitrate_kbps,
                    width = EXCLUDED.width,
                    height = EXCLUDED.height,
                    frame_rate = EXCLUDED.frame_rate,
                    cdn_url = EXCLUDED.cdn_url,
                    file_size_bytes = EXCLUDED.file_size_bytes,
                    is_default = EXCLUDED.is_default,
                    updated_at = NOW()",
            )
            .bind(reel_id)
            .bind(profile.quality)
            .bind(profile.bitrate_kbps)
            .bind(profile.width)
            .bind(profile.height)
            .bind(profile.frame_rate)
            .bind(cdn_url)
            .bind(profile.is_default)
            .execute(&pool)
            .await?;

            // Mark job completed
            sqlx::query(
                "UPDATE reel_transcode_jobs
                 SET status = 'completed',
                     stage = 'completed',
                     progress = $2,
                     finished_at = NOW()
                 WHERE id = $1",
            )
            .bind(job.id)
            .bind(completion_progress.min(100))
            .execute(&pool)
            .await?;

            sqlx::query(
                "UPDATE reels
                 SET processing_progress = $2,
                     processing_stage = 'publishing'
                 WHERE id = $1 AND status <> 'deleted'",
            )
            .bind(reel_id)
            .bind(completion_progress.min(100))
            .execute(&pool)
            .await?;

            info!(
                "Reel {} mock transcoding step complete (quality={})",
                reel_id, quality
            );
        }

        // Mark reel as published
        sqlx::query(
            "UPDATE reels
             SET status = 'published',
                 processing_stage = 'completed',
                 processing_progress = 100,
                 published_at = COALESCE(published_at, NOW()),
                 updated_at = NOW()
             WHERE id = $1 AND status <> 'deleted'",
        )
        .bind(reel_id)
        .execute(&pool)
        .await?;

        info!("Reel {} mock transcoding pipeline completed", reel_id);
        Ok(())
    }
}

async fn mark_reel_failed(pool: &PgPool, reel_id: Uuid, reason: &str) -> Result<()> {
    sqlx::query(
        "UPDATE reels
         SET status = 'failed',
             processing_stage = 'failed',
             failed_at = NOW(),
             updated_at = NOW()
         WHERE id = $1",
    )
    .bind(reel_id)
    .execute(pool)
    .await?;

    sqlx::query(
        "UPDATE reel_transcode_jobs
         SET status = 'failed',
             stage = 'failed',
             error_message = $2,
             finished_at = NOW()
         WHERE reel_id = $1 AND status <> 'completed'",
    )
    .bind(reel_id)
    .bind(reason)
    .execute(pool)
    .await?;

    warn!("Reel {} marked as failed ({})", reel_id, reason);
    Ok(())
}
