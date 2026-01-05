//! Kafka event producer for social service
//!
//! Publishes like/unlike events for downstream consumers (analytics, notifications, feed ranking)

use anyhow::Result;
use chrono::Utc;
use event_schema::{EventEnvelope, LikeCreatedEvent, LikeDeletedEvent};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::message::OwnedHeaders;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{info, warn};
use uuid::Uuid;

/// Notification event format expected by notification-service Kafka consumer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaNotification {
    pub id: String,
    pub user_id: Uuid,
    pub event_type: String,
    pub title: String,
    pub body: String,
    pub data: Option<serde_json::Value>,
    pub timestamp: i64,
}

/// Configuration for the Kafka event producer
#[derive(Debug, Clone)]
pub struct KafkaEventProducerConfig {
    pub brokers: String,
    pub topic: String,
    /// Topic for notification events (consumed by notification-service)
    pub notification_topic: String,
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
            notification_topic: std::env::var("KAFKA_NOTIFICATION_TOPIC")
                .unwrap_or_else(|_| "PostLiked".to_string()),
        })
    }
}

/// Kafka event producer for social interactions
#[derive(Clone)]
pub struct SocialEventProducer {
    producer: FutureProducer,
    topic: String,
    notification_topic: String,
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
            notification_topic = %config.notification_topic,
            "Social service Kafka producer initialized"
        );

        Ok(Self {
            producer,
            topic: config.topic.clone(),
            notification_topic: config.notification_topic.clone(),
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

    /// Publish a like notification event to notification-service
    ///
    /// This sends a KafkaNotification to the PostLiked topic that the
    /// notification-service consumes to create push notifications.
    ///
    /// # Arguments
    /// * `like_id` - The ID of the like
    /// * `post_id` - The ID of the post that was liked
    /// * `liker_id` - The ID of the user who liked the post
    /// * `post_author_id` - The ID of the post author (notification recipient)
    /// * `liker_username` - Optional username of the liker for notification text
    pub async fn publish_like_notification(
        &self,
        like_id: Uuid,
        post_id: Uuid,
        liker_id: Uuid,
        post_author_id: Uuid,
        liker_username: Option<String>,
    ) -> Result<()> {
        // Don't send notification if user liked their own post
        if liker_id == post_author_id {
            info!(
                liker_id = %liker_id,
                post_id = %post_id,
                "Skipping self-like notification"
            );
            return Ok(());
        }

        let username = liker_username.unwrap_or_else(|| "Someone".to_string());

        let notification = KafkaNotification {
            id: like_id.to_string(),
            user_id: post_author_id, // Recipient of the notification
            event_type: "Like".to_string(),
            title: "New Like".to_string(),
            body: format!("{} liked your post", username),
            data: Some(serde_json::json!({
                "sender_id": liker_id.to_string(),
                "object_id": post_id.to_string(),
                "object_type": "post",
                "like_id": like_id.to_string(),
            })),
            timestamp: Utc::now().timestamp(),
        };

        let payload = serde_json::to_string(&notification)?;
        let partition_key = post_author_id.to_string();

        let record = FutureRecord::to(&self.notification_topic)
            .key(&partition_key)
            .payload(&payload);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok(_) => {
                info!(
                    post_id = %post_id,
                    liker_id = %liker_id,
                    recipient_id = %post_author_id,
                    topic = %self.notification_topic,
                    "Published like notification to Kafka"
                );
                Ok(())
            }
            Err((err, _)) => {
                warn!(
                    error = ?err,
                    post_id = %post_id,
                    "Failed to publish like notification to Kafka"
                );
                Err(anyhow::anyhow!("Failed to publish notification: {}", err))
            }
        }
    }

    /// Publish a follow notification event to notification-service
    ///
    /// This sends a KafkaNotification to the FollowAdded topic that the
    /// notification-service consumes to create push notifications.
    ///
    /// # Arguments
    /// * `follower_id` - The ID of the user who followed
    /// * `followee_id` - The ID of the user being followed (notification recipient)
    /// * `follower_username` - Optional username of the follower for notification text
    pub async fn publish_follow_notification(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
        follower_username: Option<String>,
    ) -> Result<()> {
        // Don't send notification if user somehow followed themselves
        if follower_id == followee_id {
            info!(
                follower_id = %follower_id,
                "Skipping self-follow notification"
            );
            return Ok(());
        }

        let username = follower_username.unwrap_or_else(|| "Someone".to_string());

        let notification = KafkaNotification {
            id: Uuid::new_v4().to_string(),
            user_id: followee_id, // Recipient of the notification
            event_type: "Follow".to_string(),
            title: "New Follower".to_string(),
            body: format!("{} started following you", username),
            data: Some(serde_json::json!({
                "sender_id": follower_id.to_string(),
                "object_id": follower_id.to_string(),
                "object_type": "user",
            })),
            timestamp: Utc::now().timestamp(),
        };

        let payload = serde_json::to_string(&notification)?;
        let partition_key = followee_id.to_string();

        // Use "FollowAdded" topic for follow notifications
        let follow_topic = "FollowAdded";

        let record = FutureRecord::to(follow_topic)
            .key(&partition_key)
            .payload(&payload);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok(_) => {
                info!(
                    follower_id = %follower_id,
                    followee_id = %followee_id,
                    topic = %follow_topic,
                    "Published follow notification to Kafka"
                );
                Ok(())
            }
            Err((err, _)) => {
                warn!(
                    error = ?err,
                    follower_id = %follower_id,
                    followee_id = %followee_id,
                    "Failed to publish follow notification to Kafka"
                );
                Err(anyhow::anyhow!("Failed to publish notification: {}", err))
            }
        }
    }
}
