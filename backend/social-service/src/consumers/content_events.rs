//! Content Events Consumer
//!
//! Consumes content.post.created events from Kafka to initialize post_counters
//! when a new post is created. This ensures the counter cache is warmed before
//! the first like/comment/share interaction.

use rdkafka::config::ClientConfig;
use rdkafka::consumer::{CommitMode, Consumer, StreamConsumer};
use rdkafka::error::KafkaError;
use rdkafka::message::{Headers, Message};
use serde::Deserialize;
use sqlx::PgPool;
use std::time::Duration;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Configuration for the content events Kafka consumer
#[derive(Debug, Clone)]
pub struct ContentEventsConsumerConfig {
    pub brokers: String,
    pub group_id: String,
    pub content_events_topic: String,
}

impl ContentEventsConsumerConfig {
    /// Load configuration from environment variables
    pub fn from_env() -> Option<Self> {
        let brokers = std::env::var("KAFKA_BROKERS").ok()?;

        if brokers.trim().is_empty() {
            return None;
        }

        let topic_prefix =
            std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".to_string());

        Some(Self {
            brokers,
            group_id: std::env::var("KAFKA_SOCIAL_CONTENT_GROUP_ID")
                .unwrap_or_else(|_| "nova-social-content-consumer".to_string()),
            content_events_topic: std::env::var("KAFKA_CONTENT_EVENTS_TOPIC")
                .unwrap_or_else(|_| format!("{}.content.events", topic_prefix)),
        })
    }
}

/// Event payload for content.post.created
#[derive(Debug, Deserialize)]
struct PostCreatedEvent {
    post_id: String,
    user_id: String,
    #[allow(dead_code)]
    status: Option<String>,
}

/// Content events consumer that initializes post_counters on post creation
pub struct ContentEventsConsumer {
    pg_pool: PgPool,
    config: ContentEventsConsumerConfig,
}

impl ContentEventsConsumer {
    pub fn new(pg_pool: PgPool, config: ContentEventsConsumerConfig) -> Self {
        Self { pg_pool, config }
    }

    /// Run the consumer loop
    pub async fn run(self) {
        if let Err(err) = self.run_inner().await {
            error!("Content events consumer terminated with error: {err}");
        }
    }

    async fn run_inner(self) -> Result<(), KafkaError> {
        info!(
            "Starting content events consumer (topic: {}, group: {})",
            self.config.content_events_topic, self.config.group_id
        );

        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", &self.config.brokers)
            .set("group.id", &self.config.group_id)
            .set("enable.auto.commit", "true")
            .set("auto.offset.reset", "latest")
            .set("enable.partition.eof", "false")
            .set("session.timeout.ms", "45000")
            .set("max.poll.interval.ms", "300000")
            .create()?;

        consumer.subscribe(&[&self.config.content_events_topic])?;

        loop {
            match consumer.recv().await {
                Ok(record) => {
                    let topic = record.topic();
                    let payload = record.payload();

                    if payload.is_none() {
                        debug!("Received Kafka message with empty payload (topic: {})", topic);
                        continue;
                    }

                    let data = payload.expect("Payload checked to be Some above");
                    let event_type = self.header_value(&record, "event_type");

                    // Process content.post.created events
                    if event_type == Some("content.post.created") {
                        if let Err(e) = self.handle_post_created(data).await {
                            warn!("Failed to handle post created event: {}", e);
                        }
                    } else {
                        debug!("Ignoring event type: {:?}", event_type);
                    }

                    if let Err(commit_err) = consumer.commit_message(&record, CommitMode::Async) {
                        warn!("Failed to commit Kafka offset: {}", commit_err);
                    }
                }
                Err(err) => {
                    error!("Kafka error: {}", err);
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }

    /// Handle a post created event by initializing post_counters
    async fn handle_post_created(&self, data: &[u8]) -> anyhow::Result<()> {
        let event: PostCreatedEvent = serde_json::from_slice(data)?;

        let post_id = Uuid::parse_str(&event.post_id)?;

        info!(
            "Initializing post_counters for new post: {} (user: {})",
            post_id, event.user_id
        );

        // Initialize post_counters with zeros
        // ON CONFLICT DO NOTHING ensures idempotency
        sqlx::query(
            r#"
            INSERT INTO post_counters (post_id, like_count, comment_count, share_count, updated_at)
            VALUES ($1, 0, 0, 0, NOW())
            ON CONFLICT (post_id) DO NOTHING
            "#,
        )
        .bind(post_id)
        .execute(&self.pg_pool)
        .await?;

        debug!("post_counters initialized for post: {}", post_id);
        Ok(())
    }

    fn header_value<'a>(
        &self,
        message: &'a rdkafka::message::BorrowedMessage<'a>,
        key: &str,
    ) -> Option<&'a str> {
        message
            .headers()
            .and_then(|headers| {
                headers
                    .iter()
                    .find(|header| header.key == key)
                    .and_then(|header| header.value)
            })
            .and_then(|value| std::str::from_utf8(value).ok())
    }
}
