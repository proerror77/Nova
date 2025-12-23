//! VLM Backfill Job
//!
//! Processes existing posts that haven't been analyzed by VLM yet.
//! Designed to run as a Kubernetes CronJob.

use crate::config::Config;
use crate::providers::GoogleVisionClient;
use crate::services::{generate_tags, match_channels, Channel as ServiceChannel, GeneratedTag, KeywordWeight};
use anyhow::Result;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Post record for backfill processing
#[derive(Debug, sqlx::FromRow)]
struct PendingPost {
    pub id: Uuid,
    #[allow(dead_code)]
    pub user_id: Uuid,
    pub media_urls: Option<serde_json::Value>,
    #[allow(dead_code)]
    pub media_type: Option<String>,
}

/// Channel record from database
#[derive(Debug, sqlx::FromRow)]
struct DbChannel {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub vlm_keywords: Option<serde_json::Value>,
}

impl DbChannel {
    /// Convert to service Channel type
    fn to_service_channel(&self) -> ServiceChannel {
        let keywords = self
            .vlm_keywords
            .as_ref()
            .and_then(|v| serde_json::from_value::<Vec<KeywordWeight>>(v.clone()).ok())
            .unwrap_or_default();

        ServiceChannel {
            id: self.id,
            name: self.name.clone(),
            slug: self.slug.clone(),
            vlm_keywords: keywords,
        }
    }
}

/// Backfill job for processing existing posts
pub struct BackfillJob {
    pool: PgPool,
    vision_client: Arc<GoogleVisionClient>,
    config: Config,
}

impl BackfillJob {
    /// Create a new backfill job
    pub fn new(
        pool: PgPool,
        vision_client: Arc<GoogleVisionClient>,
        config: Config,
    ) -> Self {
        Self {
            pool,
            vision_client,
            config,
        }
    }

    /// Run the backfill job
    pub async fn run(&self) -> Result<BackfillStats> {
        info!(
            batch_size = self.config.backfill_batch_size,
            max_posts = self.config.backfill_max_posts,
            rate_limit = self.config.rate_limit_rps,
            "Starting VLM backfill job"
        );

        let mut stats = BackfillStats::default();
        let mut offset: i64 = 0;
        let batch_size = self.config.backfill_batch_size as i64;
        let max_posts = self.config.backfill_max_posts as i64;
        let batch_delay = Duration::from_millis(self.config.backfill_batch_delay_ms);

        // Load channels for matching
        let db_channels = self.load_channels().await?;
        let channels: Vec<ServiceChannel> = db_channels
            .iter()
            .map(|c| c.to_service_channel())
            .collect();
        info!(channel_count = channels.len(), "Loaded channels for matching");

        loop {
            // Check if we've reached the max
            if stats.total_processed >= max_posts as u64 {
                info!(
                    processed = stats.total_processed,
                    "Reached max posts limit, stopping"
                );
                break;
            }

            // Fetch batch of pending posts
            let posts = self.fetch_pending_posts(batch_size, offset).await?;

            if posts.is_empty() {
                info!("No more pending posts to process");
                break;
            }

            let batch_count = posts.len();
            info!(
                batch = stats.batches_processed + 1,
                count = batch_count,
                offset = offset,
                "Processing batch"
            );

            // Process each post in the batch
            for post in posts {
                match self.process_post(&post, &channels).await {
                    Ok(()) => {
                        stats.success_count += 1;
                        debug!(post_id = %post.id, "Post processed successfully");
                    }
                    Err(e) => {
                        stats.error_count += 1;
                        error!(post_id = %post.id, error = %e, "Failed to process post");
                    }
                }
                stats.total_processed += 1;

                // Rate limiting delay per request
                if self.config.rate_limit_rps > 0 {
                    let delay_per_request =
                        Duration::from_millis(1000 / self.config.rate_limit_rps as u64);
                    tokio::time::sleep(delay_per_request).await;
                }
            }

            stats.batches_processed += 1;
            offset += batch_count as i64;

            // Delay between batches
            if !batch_delay.is_zero() {
                tokio::time::sleep(batch_delay).await;
            }
        }

        info!(
            total_processed = stats.total_processed,
            success = stats.success_count,
            errors = stats.error_count,
            batches = stats.batches_processed,
            "VLM backfill job completed"
        );

        Ok(stats)
    }

    /// Fetch pending posts from database
    async fn fetch_pending_posts(&self, limit: i64, offset: i64) -> Result<Vec<PendingPost>> {
        let posts = sqlx::query_as::<_, PendingPost>(
            r#"
            SELECT id, user_id, media_urls, media_type
            FROM posts
            WHERE deleted_at IS NULL
              AND (vlm_status IS NULL OR vlm_status = 'pending')
              AND media_type IS NOT NULL
              AND media_type <> 'none'
              AND media_urls IS NOT NULL
              AND jsonb_array_length(media_urls) > 0
            ORDER BY created_at DESC
            LIMIT $1 OFFSET $2
            "#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(posts)
    }

    /// Load channels with VLM keywords
    async fn load_channels(&self) -> Result<Vec<DbChannel>> {
        let channels = sqlx::query_as::<_, DbChannel>(
            r#"
            SELECT id, name, slug, vlm_keywords
            FROM channels
            WHERE deleted_at IS NULL
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(channels)
    }

    /// Process a single post
    async fn process_post(&self, post: &PendingPost, channels: &[ServiceChannel]) -> Result<()> {
        // Extract image URLs
        let image_urls = self.extract_image_urls(post)?;
        if image_urls.is_empty() {
            // Mark as processed with no images
            self.update_vlm_status(post.id, "no_images").await?;
            return Ok(());
        }

        // Mark as processing
        self.update_vlm_status(post.id, "processing").await?;

        // Analyze first image (or could analyze all)
        let first_url = &image_urls[0];
        let vision_result = self.vision_client.analyze_image(first_url).await;

        match vision_result {
            Ok(analysis) => {
                // Generate normalized tags using the service function
                let tags = generate_tags(
                    &analysis,
                    self.config.max_tags,
                    self.config.min_tag_confidence,
                );

                // Save tags to database
                self.save_tags(post.id, &tags).await?;

                // Match channels using the service function
                let tag_tuples: Vec<(String, f32)> = tags
                    .iter()
                    .map(|t| (t.tag.clone(), t.confidence))
                    .collect();
                let matched_channels = match_channels(
                    &tag_tuples,
                    channels,
                    self.config.max_channels,
                    self.config.channel_min_confidence,
                );

                // Auto-assign channels if any matched
                if !matched_channels.is_empty() {
                    self.assign_channels(post.id, &matched_channels).await?;
                }

                // Mark as completed
                self.update_vlm_status(post.id, "completed").await?;

                debug!(
                    post_id = %post.id,
                    tag_count = tags.len(),
                    channel_count = matched_channels.len(),
                    "Post analysis completed"
                );
            }
            Err(e) => {
                warn!(post_id = %post.id, error = %e, "Vision API error");
                self.update_vlm_status(post.id, "error").await?;
                return Err(e.into());
            }
        }

        Ok(())
    }

    /// Extract image URLs from post
    fn extract_image_urls(&self, post: &PendingPost) -> Result<Vec<String>> {
        let Some(urls_json) = &post.media_urls else {
            return Ok(vec![]);
        };

        let urls: Vec<String> = serde_json::from_value(urls_json.clone())?;
        Ok(urls)
    }

    /// Update VLM status in database
    async fn update_vlm_status(&self, post_id: Uuid, status: &str) -> Result<()> {
        let processed_at = if status == "completed" || status == "error" || status == "no_images" {
            Some(chrono::Utc::now())
        } else {
            None
        };

        sqlx::query(
            r#"
            UPDATE posts
            SET vlm_status = $1,
                vlm_processed_at = COALESCE($2, vlm_processed_at),
                updated_at = NOW()
            WHERE id = $3
            "#,
        )
        .bind(status)
        .bind(processed_at)
        .bind(post_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Save tags to database
    async fn save_tags(&self, post_id: Uuid, tags: &[GeneratedTag]) -> Result<()> {
        for tag in tags {
            sqlx::query(
                r#"
                INSERT INTO post_tags (post_id, tag, confidence, source, vlm_provider)
                VALUES ($1, $2, $3, 'vlm', 'google_vision')
                ON CONFLICT (post_id, tag) DO UPDATE SET
                    confidence = EXCLUDED.confidence,
                    vlm_provider = EXCLUDED.vlm_provider
                "#,
            )
            .bind(post_id)
            .bind(&tag.tag)
            .bind(tag.confidence)
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    /// Assign channels to post
    async fn assign_channels(
        &self,
        post_id: Uuid,
        channels: &[crate::services::ChannelMatch],
    ) -> Result<()> {
        for channel in channels {
            sqlx::query(
                r#"
                INSERT INTO post_channels (post_id, channel_id, confidence, tagged_by)
                VALUES ($1, $2, $3, 'vlm_backfill')
                ON CONFLICT (post_id, channel_id) DO NOTHING
                "#,
            )
            .bind(post_id)
            .bind(channel.channel_id)
            .bind(channel.confidence)
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }
}

/// Statistics from backfill run
#[derive(Debug, Default)]
pub struct BackfillStats {
    pub total_processed: u64,
    pub success_count: u64,
    pub error_count: u64,
    pub batches_processed: u64,
}
