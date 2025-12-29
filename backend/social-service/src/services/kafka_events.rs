//! Kafka event producer for social service
//!
//! Publishes like/unlike events for downstream consumers (analytics, notifications, feed ranking)

use anyhow::Result;
use chrono::Utc;
use event_schema::{EventEnvelope, LikeCreatedEvent, LikeDeletedEvent};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::message::OwnedHeaders;
use std::time::Duration;
use tracing::{info, warn};
use uuid::Uuid;

/// Configuration for the Kafka event producer
#[derive(Debug, Clone)]
pub struct KafkaEventProducerConfig {
    pub brokers: String,
    pub topic: String,
}

impl KafkaEventProducerConfig {
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
            topic: std::env::var("KAFKA_SOCIAL_EVENTS_TOPIC")
                .unwrap_or_else(|_| format!("{}.social.events", topic_prefix)),
        })
    }
}

/// Kafka event producer for social interactions
#[derive(Clone)]
pub struct SocialEventProducer {
    producer: FutureProducer,
    topic: String,
}

impl SocialEventProducer {
    /// Create a new Kafka event producer
    pub fn new(config: &KafkaEventProducerConfig) -> Result<Self> {
        let producer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("client.id", "social-service")
            // Idempotency and reliability settings
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("max.in.flight.requests.per.connection", "5")
            .set("retries", "3")
            .set("linger.ms", "5") // Batch for 5ms for better throughput
            .create::<FutureProducer>()?;

        info!(
            brokers = %config.brokers,
            topic = %config.topic,
            "Social service Kafka producer initialized"
        );

        Ok(Self {
            producer,
            topic: config.topic.clone(),
        })
    }

    /// Publish a like created event
    pub async fn publish_like_created(
        &self,
        like_id: Uuid,
        post_id: Uuid,
        user_id: Uuid,
    ) -> Result<()> {
        let event = LikeCreatedEvent {
            like_id,
            target_id: post_id,
            target_type: "post".to_string(),
            user_id,
            created_at: Utc::now(),
        };

        let envelope = EventEnvelope::new_with_type(
            "social-service",
            "social.like.created",
            event,
        )
        .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, post_id).await
    }

    /// Publish a like deleted event
    pub async fn publish_like_deleted(
        &self,
        like_id: Uuid,
        post_id: Uuid,
    ) -> Result<()> {
        let event = LikeDeletedEvent {
            like_id,
            target_id: post_id,
            target_type: "post".to_string(),
            deleted_at: Utc::now(),
        };

        let envelope = EventEnvelope::new_with_type(
            "social-service",
            "social.like.deleted",
            event,
        )
        .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, post_id).await
    }

    /// Generic event publishing method
    async fn publish_event<T: serde::Serialize>(
        &self,
        envelope: &EventEnvelope<T>,
        partition_key_id: Uuid,
    ) -> Result<()> {
        let payload = serde_json::to_string(envelope)?;
        let partition_key = partition_key_id.to_string();

        // Add event_type header for consumer routing
        let headers = OwnedHeaders::new()
            .insert(rdkafka::message::Header {
                key: "event_type",
                value: envelope.event_type.as_deref(),
            });

        let record = FutureRecord::to(&self.topic)
            .key(&partition_key)
            .payload(&payload)
            .headers(headers);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok(_) => {
                info!(
                    event_type = ?envelope.event_type,
                    partition_key = %partition_key,
                    "Published social event to Kafka"
                );
                Ok(())
            }
            Err((err, _)) => {
                warn!(
                    error = ?err,
                    event_type = ?envelope.event_type,
                    "Failed to publish social event to Kafka"
                );
                Err(anyhow::anyhow!("Failed to publish event: {}", err))
            }
        }
    }
}
