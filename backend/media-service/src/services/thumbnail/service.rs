//! Thumbnail service - coordinates thumbnail generation, storage, and database updates
//!
//! This service handles the complete thumbnail generation workflow:
//! 1. Download original image from GCS
//! 2. Generate thumbnail
//! 3. Upload thumbnail to GCS
//! 4. Update database with thumbnail metadata
//!
//! Works with media-service's `uploads` and `media_files` tables in nova_media database.

use super::gcs_client::GcsClient;
use super::processor::{ThumbnailConfig, ThumbnailProcessor};
use crate::error::{AppError, Result};
use sqlx::{FromRow, PgPool, Row};
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Upload record from media database (nova_media.uploads)
#[derive(Debug, Clone, FromRow)]
pub struct MediaUpload {
    pub id: Uuid,
    pub user_id: Uuid,
    pub media_id: Option<Uuid>,
    pub file_name: Option<String>,
    pub storage_path: Option<String>,
    pub status: String,
}

/// Media file record from media database (nova_media.media_files)
#[derive(Debug, Clone, FromRow)]
pub struct MediaFile {
    pub id: Uuid,
    pub storage_path: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: String,
}

/// Thumbnail service configuration
#[derive(Clone, Debug)]
pub struct ThumbnailServiceConfig {
    /// Thumbnail processing config
    pub thumbnail: ThumbnailConfig,
    /// Batch size for processing
    pub batch_size: i64,
    /// Media database URL (for uploads/media_files tables in nova_media)
    pub content_db_url: String,
}

impl Default for ThumbnailServiceConfig {
    fn default() -> Self {
        Self {
            thumbnail: ThumbnailConfig::default(),
            batch_size: 20,
            content_db_url: String::new(),
        }
    }
}

/// Thumbnail service for generating and managing thumbnails
pub struct ThumbnailService {
    gcs_client: Arc<GcsClient>,
    processor: ThumbnailProcessor,
    media_pool: PgPool,
    config: ThumbnailServiceConfig,
}

impl ThumbnailService {
    /// Create a new thumbnail service
    pub async fn new(
        gcs_client: Arc<GcsClient>,
        config: ThumbnailServiceConfig,
    ) -> Result<Self> {
        let media_pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(5)
            .connect(&config.content_db_url)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to connect to media DB: {e}")))?;

        let processor = ThumbnailProcessor::new(config.thumbnail.clone());

        info!("Thumbnail service initialized");

        Ok(Self {
            gcs_client,
            processor,
            media_pool,
            config,
        })
    }

    /// Process a single image by upload ID (from Kafka event)
    pub async fn process_image(&self, upload_id: Uuid) -> Result<()> {
        // First try to find the upload record
        let upload: Option<MediaUpload> = sqlx::query_as::<_, MediaUpload>(
            r#"
            SELECT id, user_id, media_id, file_name, storage_path, status
            FROM uploads
            WHERE id = $1 AND status = 'completed'
            "#,
        )
        .bind(upload_id)
        .fetch_optional(&self.media_pool)
        .await
        .map_err(|e| AppError::Internal(format!("DB query failed: {e}")))?;

        let upload = upload.ok_or_else(|| {
            AppError::NotFound(format!("Upload not found: {}", upload_id))
        })?;

        // Get storage path - construct from upload if not present
        let storage_path = upload.storage_path.clone().unwrap_or_else(|| {
            let file_name = upload.file_name.clone().unwrap_or_else(|| format!("{}.jpg", upload_id));
            format!("uploads/{}/{}", upload_id, file_name)
        });

        self.generate_thumbnail_for_upload(&upload, &storage_path).await
    }

    /// Process all images that are missing thumbnails
    pub async fn process_pending(&self) -> Result<u32> {
        let mut processed = 0u32;

        loop {
            // Fetch batch of media files missing thumbnails (images only)
            let media_files: Vec<MediaFile> = sqlx::query_as::<_, MediaFile>(
                r#"
                SELECT id, storage_path, thumbnail_url, status
                FROM media_files
                WHERE status = 'ready'
                  AND thumbnail_url IS NULL
                  AND (media_type = 'image' OR media_type LIKE 'image/%')
                ORDER BY created_at ASC
                LIMIT $1
                "#,
            )
            .bind(self.config.batch_size)
            .fetch_all(&self.media_pool)
            .await
            .map_err(|e| AppError::Internal(format!("DB query failed: {e}")))?;

            if media_files.is_empty() {
                info!(total_processed = processed, "No more images pending thumbnails");
                break;
            }

            info!(batch_size = media_files.len(), "Processing batch of images");

            for media in media_files {
                let storage_path = match &media.storage_path {
                    Some(path) => path.clone(),
                    None => {
                        warn!(media_id = %media.id, "Media file has no storage path, skipping");
                        continue;
                    }
                };

                match self.generate_thumbnail_for_media(&media, &storage_path).await {
                    Ok(()) => {
                        processed += 1;
                        debug!(media_id = %media.id, "Thumbnail generated successfully");
                    }
                    Err(e) => {
                        error!(
                            media_id = %media.id,
                            storage_path = %storage_path,
                            error = %e,
                            "Failed to generate thumbnail"
                        );
                    }
                }

                // Small delay to avoid overwhelming GCS
                tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            }
        }

        Ok(processed)
    }

    /// Generate thumbnail for an upload (from Kafka event)
    async fn generate_thumbnail_for_upload(&self, upload: &MediaUpload, storage_path: &str) -> Result<()> {
        info!(
            upload_id = %upload.id,
            storage_path = %storage_path,
            "Generating thumbnail for upload"
        );

        // Download original from GCS
        let original_data = self.gcs_client.download(storage_path).await?;

        // Generate thumbnail
        let thumbnail = self.processor.generate(&original_data)?;

        // Upload thumbnail to GCS
        let thumb_key = format!("thumbnails/{}.jpg", upload.id);
        self.gcs_client
            .upload(&thumb_key, thumbnail.data.clone(), "image/jpeg")
            .await?;

        // Get public URL
        let thumb_url = self.gcs_client.public_url(&thumb_key);

        // Update media_files.thumbnail_url if media_id is set
        if let Some(media_id) = upload.media_id {
            self.update_media_thumbnail(&media_id, &thumb_url).await?;
        }

        info!(
            upload_id = %upload.id,
            thumb_key = %thumb_key,
            width = thumbnail.width,
            height = thumbnail.height,
            size = thumbnail.data.len(),
            "Thumbnail created successfully for upload"
        );

        Ok(())
    }

    /// Generate thumbnail for a media file (from batch processing)
    async fn generate_thumbnail_for_media(&self, media: &MediaFile, storage_path: &str) -> Result<()> {
        info!(
            media_id = %media.id,
            storage_path = %storage_path,
            "Generating thumbnail for media file"
        );

        // Download original from GCS
        let original_data = self.gcs_client.download(storage_path).await?;

        // Generate thumbnail
        let thumbnail = self.processor.generate(&original_data)?;

        // Upload thumbnail to GCS
        let thumb_key = format!("thumbnails/{}.jpg", media.id);
        self.gcs_client
            .upload(&thumb_key, thumbnail.data.clone(), "image/jpeg")
            .await?;

        // Get public URL
        let thumb_url = self.gcs_client.public_url(&thumb_key);

        // Update media_files.thumbnail_url
        self.update_media_thumbnail(&media.id, &thumb_url).await?;

        info!(
            media_id = %media.id,
            thumb_key = %thumb_key,
            width = thumbnail.width,
            height = thumbnail.height,
            size = thumbnail.data.len(),
            "Thumbnail created successfully for media"
        );

        Ok(())
    }

    /// Update thumbnail URL in media_files table
    async fn update_media_thumbnail(&self, media_id: &Uuid, thumbnail_url: &str) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE media_files
            SET thumbnail_url = $2, updated_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(media_id)
        .bind(thumbnail_url)
        .execute(&self.media_pool)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to update thumbnail URL: {e}")))?;

        Ok(())
    }

    /// Get statistics about thumbnail generation
    pub async fn get_stats(&self) -> Result<ThumbnailStats> {
        let row = sqlx::query(
            r#"
            SELECT
                COUNT(*) FILTER (WHERE status = 'ready' AND (media_type = 'image' OR media_type LIKE 'image/%')) as originals,
                COUNT(*) FILTER (WHERE thumbnail_url IS NOT NULL) as thumbnails,
                0::bigint as failed
            FROM media_files
            "#,
        )
        .fetch_one(&self.media_pool)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch stats: {e}")))?;

        Ok(ThumbnailStats {
            total_originals: row.get::<i64, _>("originals") as u32,
            total_thumbnails: row.get::<i64, _>("thumbnails") as u32,
            total_failed: row.get::<i64, _>("failed") as u32,
        })
    }
}

/// Statistics about thumbnail generation
#[derive(Debug)]
pub struct ThumbnailStats {
    pub total_originals: u32,
    pub total_thumbnails: u32,
    pub total_failed: u32,
}
