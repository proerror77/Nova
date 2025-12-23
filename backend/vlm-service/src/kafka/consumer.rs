//! VLM Kafka Consumer
//!
//! Consumes post.created events and triggers VLM analysis.

use crate::kafka::events::{
    topics, PostCreatedForVLM, VLMChannelSuggestion, VLMPostAnalyzed, VLMTag,
};
use crate::kafka::producer::SharedVLMProducer;
use crate::{generate_tags, match_channels, Channel, GoogleVisionClient, TagSource};
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use rdkafka::ClientConfig;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{error, info, warn};
use uuid::Uuid;

/// VLM Kafka consumer configuration
#[derive(Debug, Clone)]
pub struct VLMConsumerConfig {
    pub brokers: String,
    pub group_id: String,
    pub max_retries: u32,
    pub retry_backoff_ms: u64,
    pub max_retry_backoff_ms: u64,
}

impl Default for VLMConsumerConfig {
    fn default() -> Self {
        Self {
            brokers: "localhost:9092".to_string(),
            group_id: "vlm-service".to_string(),
            max_retries: 3,
            retry_backoff_ms: 100,
            max_retry_backoff_ms: 30_000,
        }
    }
}

/// VLM Kafka consumer
pub struct VLMConsumer {
    consumer: StreamConsumer,
    config: VLMConsumerConfig,
    vision_client: Arc<GoogleVisionClient>,
    producer: SharedVLMProducer,
    db_pool: Option<PgPool>,
    channels_cache: Arc<RwLock<Vec<Channel>>>,
}

impl VLMConsumer {
    /// Create a new VLM consumer
    pub fn new(
        config: VLMConsumerConfig,
        vision_client: Arc<GoogleVisionClient>,
        producer: SharedVLMProducer,
        db_pool: Option<PgPool>,
    ) -> Result<Self, rdkafka::error::KafkaError> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("group.id", &config.group_id)
            .set("enable.auto.commit", "false") // Manual commit for reliability
            .set("auto.offset.reset", "earliest")
            .set("session.timeout.ms", "45000")
            .set("max.poll.interval.ms", "300000")
            .set("enable.partition.eof", "false")
            .create()?;

        consumer.subscribe(&[topics::POST_CREATED_FOR_VLM])?;

        info!(
            "VLM consumer initialized, subscribed to: {}",
            topics::POST_CREATED_FOR_VLM
        );

        Ok(Self {
            consumer,
            config,
            vision_client,
            producer,
            db_pool,
            channels_cache: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// Start consuming messages
    pub async fn run(&self) -> Result<(), VLMConsumerError> {
        use futures_util::StreamExt;

        info!("Starting VLM consumer loop");

        // Load channels cache on startup
        self.refresh_channels_cache().await;

        let mut message_stream = self.consumer.stream();
        let mut backoff_ms = self.config.retry_backoff_ms;

        loop {
            match message_stream.next().await {
                Some(Ok(message)) => {
                    // Reset backoff on successful message
                    backoff_ms = self.config.retry_backoff_ms;

                    if let Some(payload) = message.payload() {
                        match serde_json::from_slice::<PostCreatedForVLM>(payload) {
                            Ok(event) => {
                                if let Err(e) = self.process_event(event).await {
                                    error!("Failed to process VLM event: {}", e);
                                }
                            }
                            Err(e) => {
                                warn!("Failed to deserialize message: {}", e);
                            }
                        }
                    }

                    // Commit offset after processing
                    if let Err(e) = self.consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async) {
                        warn!("Failed to commit offset: {}", e);
                    }
                }
                Some(Err(e)) => {
                    error!("Kafka consumer error: {}", e);

                    // Exponential backoff
                    tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
                    backoff_ms = (backoff_ms * 2).min(self.config.max_retry_backoff_ms);
                }
                None => {
                    warn!("Message stream ended, reconnecting...");
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }

    /// Process a single VLM event
    async fn process_event(&self, event: PostCreatedForVLM) -> Result<(), VLMConsumerError> {
        let start_time = Instant::now();

        info!(
            post_id = %event.post_id,
            images = event.image_urls.len(),
            "Processing VLM event"
        );

        // Analyze first image (primary image for tagging)
        let image_url = event.image_urls.first().ok_or_else(|| {
            VLMConsumerError::Processing("No images in event".to_string())
        })?;

        // Call Vision API
        let analysis_result = self
            .vision_client
            .analyze_image(image_url)
            .await
            .map_err(|e| VLMConsumerError::VisionApi(e.to_string()))?;

        // Generate tags
        let max_tags = event.max_tags.unwrap_or(15) as usize;
        let min_confidence = 0.3_f32;
        let generated_tags = generate_tags(&analysis_result, max_tags, min_confidence);

        // Convert to VLMTag format
        let vlm_tags: Vec<VLMTag> = generated_tags
            .iter()
            .map(|t| VLMTag {
                tag: t.tag.clone(),
                confidence: t.confidence,
                source: match t.source {
                    TagSource::Label => "label",
                    TagSource::Object => "object",
                    TagSource::WebEntity => "web_entity",
                    TagSource::BestGuess => "best_guess",
                }
                .to_string(),
            })
            .collect();

        // Match channels if requested
        let channel_suggestions = if event.auto_assign_channels {
            let channels = self.channels_cache.read().await;
            // Convert generated tags to (String, f32) tuples for match_channels
            let tag_tuples: Vec<(String, f32)> = generated_tags
                .iter()
                .map(|t| (t.tag.clone(), t.confidence))
                .collect();
            let matches = match_channels(&tag_tuples, &channels, 3, 0.25);

            matches
                .iter()
                .map(|m| VLMChannelSuggestion {
                    channel_id: m.channel_id,
                    channel_name: m.channel_name.clone(),
                    channel_slug: m.channel_slug.clone(),
                    confidence: m.confidence,
                    matched_tags: m.matched_keywords.clone(),
                })
                .collect()
        } else {
            Vec::new()
        };

        let processing_time_ms = start_time.elapsed().as_millis() as i64;

        // Create and publish analyzed event
        let analyzed_event = VLMPostAnalyzed::new(
            event.post_id,
            vlm_tags.clone(),
            channel_suggestions,
            processing_time_ms,
        )
        .with_correlation_id(event.correlation_id);

        self.producer
            .publish_analyzed(analyzed_event)
            .await
            .map_err(|e| VLMConsumerError::Producer(e.to_string()))?;

        // Save tags to database if pool is available
        if let Some(pool) = &self.db_pool {
            self.save_tags_to_db(pool, event.post_id, &vlm_tags).await?;
        }

        info!(
            post_id = %event.post_id,
            tags = vlm_tags.len(),
            processing_time_ms = processing_time_ms,
            "VLM analysis complete"
        );

        Ok(())
    }

    /// Save generated tags to database
    async fn save_tags_to_db(
        &self,
        pool: &PgPool,
        post_id: Uuid,
        tags: &[VLMTag],
    ) -> Result<(), VLMConsumerError> {
        // Update post VLM status
        sqlx::query(
            r#"
            UPDATE posts
            SET vlm_status = 'completed', vlm_processed_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(post_id)
        .execute(pool)
        .await
        .map_err(|e| VLMConsumerError::Database(e.to_string()))?;

        // Insert tags
        for tag in tags {
            sqlx::query(
                r#"
                INSERT INTO post_tags (post_id, tag, confidence, source, vlm_provider)
                VALUES ($1, $2, $3, 'vlm', 'google_vision')
                ON CONFLICT (post_id, tag) DO UPDATE SET
                    confidence = EXCLUDED.confidence,
                    source = EXCLUDED.source
                "#,
            )
            .bind(post_id)
            .bind(&tag.tag)
            .bind(tag.confidence)
            .execute(pool)
            .await
            .map_err(|e| VLMConsumerError::Database(e.to_string()))?;
        }

        Ok(())
    }

    /// Refresh channels cache from database
    async fn refresh_channels_cache(&self) {
        if let Some(pool) = &self.db_pool {
            match sqlx::query_as::<_, ChannelRow>(
                r#"
                SELECT id, name, slug, vlm_keywords
                FROM channels
                WHERE vlm_keywords IS NOT NULL AND vlm_keywords != '[]'::jsonb
                "#,
            )
            .fetch_all(pool)
            .await
            {
                Ok(rows) => {
                    let channels: Vec<Channel> = rows
                        .into_iter()
                        .filter_map(|row| {
                            let keywords = row.vlm_keywords.and_then(|v| {
                                serde_json::from_value::<Vec<crate::KeywordWeight>>(v).ok()
                            });
                            keywords.map(|kw| Channel {
                                id: row.id,
                                name: row.name,
                                slug: row.slug,
                                vlm_keywords: kw,
                            })
                        })
                        .collect();

                    let count = channels.len();
                    *self.channels_cache.write().await = channels;
                    info!("Loaded {} channels with VLM keywords", count);
                }
                Err(e) => {
                    warn!("Failed to load channels cache: {}", e);
                }
            }
        }
    }
}

/// Database row for channel query
#[derive(Debug, sqlx::FromRow)]
struct ChannelRow {
    id: Uuid,
    name: String,
    slug: String,
    vlm_keywords: Option<serde_json::Value>,
}

/// Consumer error types
#[derive(Debug, thiserror::Error)]
pub enum VLMConsumerError {
    #[error("Kafka error: {0}")]
    Kafka(String),

    #[error("Processing error: {0}")]
    Processing(String),

    #[error("Vision API error: {0}")]
    VisionApi(String),

    #[error("Producer error: {0}")]
    Producer(String),

    #[error("Database error: {0}")]
    Database(String),
}
