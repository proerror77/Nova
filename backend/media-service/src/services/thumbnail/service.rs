//! Thumbnail service - coordinates thumbnail generation, storage, and database updates
//!
//! This service handles the complete thumbnail generation workflow:
//! 1. Download original image from GCS
//! 2. Generate thumbnail
//! 3. Upload thumbnail to GCS
//! 4. Update database with thumbnail metadata

use super::gcs_client::GcsClient;
use super::processor::{ThumbnailConfig, ThumbnailProcessor};
use crate::error::{AppError, Result};
use sqlx::{FromRow, PgPool, Row};
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Post image record from database
#[derive(Debug, Clone, FromRow)]
pub struct PostImage {
    pub id: Uuid,
    pub post_id: Uuid,
    pub s3_key: String,
    pub url: String,
    pub size_variant: String,
    pub status: String,
}

/// Thumbnail service configuration
#[derive(Clone, Debug)]
pub struct ThumbnailServiceConfig {
    /// Thumbnail processing config
    pub thumbnail: ThumbnailConfig,
    /// Batch size for processing
    pub batch_size: i64,
    /// Content database URL (for post_images table)
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
    content_pool: PgPool,
    config: ThumbnailServiceConfig,
}

impl ThumbnailService {
    /// Create a new thumbnail service
    pub async fn new(
        gcs_client: Arc<GcsClient>,
        config: ThumbnailServiceConfig,
    ) -> Result<Self> {
        let content_pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(5)
            .connect(&config.content_db_url)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to connect to content DB: {e}")))?;

        let processor = ThumbnailProcessor::new(config.thumbnail.clone());

        info!("Thumbnail service initialized");

        Ok(Self {
            gcs_client,
            processor,
            content_pool,
            config,
        })
    }

    /// Process a single image by ID
    pub async fn process_image(&self, image_id: Uuid) -> Result<()> {
        // Fetch the original image record
        let image: Option<PostImage> = sqlx::query_as::<_, PostImage>(
            r#"
            SELECT id, post_id, s3_key, url, size_variant, status
            FROM post_images
            WHERE id = $1 AND size_variant = 'original' AND status = 'completed'
            "#,
        )
        .bind(image_id)
        .fetch_optional(&self.content_pool)
        .await
        .map_err(|e| AppError::Internal(format!("DB query failed: {e}")))?;

        let image = image.ok_or_else(|| {
            AppError::NotFound(format!("Original image not found: {}", image_id))
        })?;

        self.generate_thumbnail_for_image(&image).await
    }

    /// Process all images that are missing thumbnails
    pub async fn process_pending(&self) -> Result<u32> {
        let mut processed = 0u32;

        loop {
            // Fetch batch of images missing thumbnails
            let images: Vec<PostImage> = sqlx::query_as::<_, PostImage>(
                r#"
                SELECT pi.id, pi.post_id, pi.s3_key, pi.url, pi.size_variant, pi.status
                FROM post_images pi
                WHERE pi.size_variant = 'original'
                  AND pi.status = 'completed'
                  AND NOT EXISTS (
                    SELECT 1 FROM post_images t
                    WHERE t.post_id = pi.post_id
                      AND t.size_variant = 'thumbnail'
                      AND t.status = 'completed'
                  )
                ORDER BY pi.created_at ASC
                LIMIT $1
                "#,
            )
            .bind(self.config.batch_size)
            .fetch_all(&self.content_pool)
            .await
            .map_err(|e| AppError::Internal(format!("DB query failed: {e}")))?;

            if images.is_empty() {
                info!(total_processed = processed, "No more images pending thumbnails");
                break;
            }

            info!(batch_size = images.len(), "Processing batch of images");

            for image in images {
                match self.generate_thumbnail_for_image(&image).await {
                    Ok(()) => {
                        processed += 1;
                        debug!(post_id = %image.post_id, "Thumbnail generated successfully");
                    }
                    Err(e) => {
                        error!(
                            post_id = %image.post_id,
                            s3_key = %image.s3_key,
                            error = %e,
                            "Failed to generate thumbnail"
                        );
                        // Mark as failed in database
                        let _ = self.mark_thumbnail_failed(&image.post_id, &e.to_string()).await;
                    }
                }

                // Small delay to avoid overwhelming GCS
                tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            }
        }

        Ok(processed)
    }

    /// Generate thumbnail for a single image
    async fn generate_thumbnail_for_image(&self, image: &PostImage) -> Result<()> {
        info!(
            post_id = %image.post_id,
            s3_key = %image.s3_key,
            "Generating thumbnail"
        );

        // Download original from GCS
        let original_data = self.gcs_client.download(&image.s3_key).await?;

        // Generate thumbnail
        let thumbnail = self.processor.generate(&original_data)?;

        // Upload thumbnail to GCS
        let thumb_key = format!("thumbnails/{}/{}.jpg", image.post_id, image.id);
        self.gcs_client
            .upload(&thumb_key, thumbnail.data.clone(), "image/jpeg")
            .await?;

        // Get public URL
        let thumb_url = self.gcs_client.public_url(&thumb_key);

        // Insert thumbnail record
        self.insert_thumbnail_record(
            &image.post_id,
            &thumb_key,
            &thumb_url,
            thumbnail.data.len() as i32,
            thumbnail.width as i32,
            thumbnail.height as i32,
        )
        .await?;

        info!(
            post_id = %image.post_id,
            thumb_key = %thumb_key,
            width = thumbnail.width,
            height = thumbnail.height,
            size = thumbnail.data.len(),
            "Thumbnail created successfully"
        );

        Ok(())
    }

    /// Insert a thumbnail record into the database
    async fn insert_thumbnail_record(
        &self,
        post_id: &Uuid,
        s3_key: &str,
        url: &str,
        file_size: i32,
        width: i32,
        height: i32,
    ) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO post_images (post_id, s3_key, status, size_variant, file_size, width, height, url)
            SELECT $1, $2, 'completed', 'thumbnail', $3, $4, $5, $6
            WHERE NOT EXISTS (
                SELECT 1 FROM post_images
                WHERE post_id = $1 AND size_variant = 'thumbnail' AND status = 'completed'
            )
            "#,
        )
        .bind(post_id)
        .bind(s3_key)
        .bind(file_size)
        .bind(width)
        .bind(height)
        .bind(url)
        .execute(&self.content_pool)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to insert thumbnail record: {e}")))?;

        Ok(())
    }

    /// Mark thumbnail generation as failed
    async fn mark_thumbnail_failed(&self, post_id: &Uuid, error_message: &str) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO post_images (post_id, s3_key, status, size_variant, error_message)
            VALUES ($1, '', 'failed', 'thumbnail', $2)
            ON CONFLICT DO NOTHING
            "#,
        )
        .bind(post_id)
        .bind(error_message)
        .execute(&self.content_pool)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to mark thumbnail as failed: {e}")))?;

        Ok(())
    }

    /// Get statistics about thumbnail generation
    pub async fn get_stats(&self) -> Result<ThumbnailStats> {
        let row = sqlx::query(
            r#"
            SELECT
                COUNT(*) FILTER (WHERE size_variant = 'original' AND status = 'completed') as originals,
                COUNT(*) FILTER (WHERE size_variant = 'thumbnail' AND status = 'completed') as thumbnails,
                COUNT(*) FILTER (WHERE size_variant = 'thumbnail' AND status = 'failed') as failed
            FROM post_images
            "#,
        )
        .fetch_one(&self.content_pool)
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
