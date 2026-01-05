//! Kafka event producer for social service
//!
//! Publishes like/unlike events for downstream consumers (analytics, notifications, feed ranking)

use anyhow::Result;
use chrono::Utc;
use event_schema::{EventEnvelope, LikeCreatedEvent, LikeDeletedEvent};
use rdkafka::message::OwnedHeaders;
use rdkafka::producer::{FutureProducer, FutureRecord};
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

        let envelope = EventEnvelope::new_with_type("social-service", "social.like.created", event)
            .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, post_id).await
    }

    /// Publish a like deleted event
    pub async fn publish_like_deleted(&self, like_id: Uuid, post_id: Uuid) -> Result<()> {
        let event = LikeDeletedEvent {
            like_id,
            target_id: post_id,
            target_type: "post".to_string(),
            deleted_at: Utc::now(),
        };

        let envelope = EventEnvelope::new_with_type("social-service", "social.like.deleted", event)
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
        let headers = OwnedHeaders::new().insert(rdkafka::message::Header {
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

    /// Publish a comment notification event to notification-service
    ///
    /// This sends a KafkaNotification to the CommentCreated topic that the
    /// notification-service consumes to create push notifications.
    ///
    /// # Arguments
    /// * `comment_id` - The ID of the comment
    /// * `post_id` - The ID of the post that was commented on
    /// * `commenter_id` - The ID of the user who commented
    /// * `post_author_id` - The ID of the post author (notification recipient)
    /// * `commenter_username` - Optional username of the commenter for notification text
    /// * `comment_preview` - Optional preview of the comment content
    pub async fn publish_comment_notification(
        &self,
        comment_id: Uuid,
        post_id: Uuid,
        commenter_id: Uuid,
        post_author_id: Uuid,
        commenter_username: Option<String>,
        comment_preview: Option<String>,
    ) -> Result<()> {
        // Don't send notification if user commented on their own post
        if commenter_id == post_author_id {
            info!(
                commenter_id = %commenter_id,
                post_id = %post_id,
                "Skipping self-comment notification"
            );
            return Ok(());
        }

        let username = commenter_username.unwrap_or_else(|| "Someone".to_string());
        let preview = comment_preview
            .map(|p| {
                if p.chars().count() > 50 {
                    format!("{}...", p.chars().take(47).collect::<String>())
                } else {
                    p
                }
            })
            .unwrap_or_default();

        let body = if preview.is_empty() {
            format!("{} commented on your post", username)
        } else {
            format!("{} commented: {}", username, preview)
        };

        let notification = KafkaNotification {
            id: comment_id.to_string(),
            user_id: post_author_id, // Recipient of the notification
            event_type: "Comment".to_string(),
            title: "New Comment".to_string(),
            body,
            data: Some(serde_json::json!({
                "sender_id": commenter_id.to_string(),
                "object_id": post_id.to_string(),
                "object_type": "post",
                "comment_id": comment_id.to_string(),
            })),
            timestamp: Utc::now().timestamp(),
        };

        let payload = serde_json::to_string(&notification)?;
        let partition_key = post_author_id.to_string();

        // Use "CommentCreated" topic for comment notifications
        let comment_topic = "CommentCreated";

        let record = FutureRecord::to(comment_topic)
            .key(&partition_key)
            .payload(&payload);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok(_) => {
                info!(
                    comment_id = %comment_id,
                    post_id = %post_id,
                    commenter_id = %commenter_id,
                    recipient_id = %post_author_id,
                    topic = %comment_topic,
                    "Published comment notification to Kafka"
                );
                Ok(())
            }
            Err((err, _)) => {
                warn!(
                    error = ?err,
                    comment_id = %comment_id,
                    post_id = %post_id,
                    "Failed to publish comment notification to Kafka"
                );
                Err(anyhow::anyhow!("Failed to publish notification: {}", err))
            }
        }
    }

    /// Publish a comment like notification event to notification-service
    ///
    /// This sends a KafkaNotification to the ReplyLiked topic that the
    /// notification-service consumes to create push notifications.
    ///
    /// # Arguments
    /// * `like_id` - The ID of the like
    /// * `comment_id` - The ID of the comment that was liked
    /// * `liker_id` - The ID of the user who liked the comment
    /// * `comment_author_id` - The ID of the comment author (notification recipient)
    /// * `liker_username` - Optional username of the liker for notification text
    pub async fn publish_comment_like_notification(
        &self,
        like_id: Uuid,
        comment_id: Uuid,
        liker_id: Uuid,
        comment_author_id: Uuid,
        liker_username: Option<String>,
    ) -> Result<()> {
        // Don't send notification if user liked their own comment
        if liker_id == comment_author_id {
            info!(
                liker_id = %liker_id,
                comment_id = %comment_id,
                "Skipping self-comment-like notification"
            );
            return Ok(());
        }

        let username = liker_username.unwrap_or_else(|| "Someone".to_string());

        let notification = KafkaNotification {
            id: like_id.to_string(),
            user_id: comment_author_id, // Recipient of the notification
            event_type: "CommentLike".to_string(),
            title: "Comment Liked".to_string(),
            body: format!("{} liked your comment", username),
            data: Some(serde_json::json!({
                "sender_id": liker_id.to_string(),
                "object_id": comment_id.to_string(),
                "object_type": "comment",
                "like_id": like_id.to_string(),
            })),
            timestamp: Utc::now().timestamp(),
        };

        let payload = serde_json::to_string(&notification)?;
        let partition_key = comment_author_id.to_string();

        // Use "ReplyLiked" topic for comment like notifications
        let reply_liked_topic = "ReplyLiked";

        let record = FutureRecord::to(reply_liked_topic)
            .key(&partition_key)
            .payload(&payload);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok(_) => {
                info!(
                    like_id = %like_id,
                    comment_id = %comment_id,
                    liker_id = %liker_id,
                    recipient_id = %comment_author_id,
                    topic = %reply_liked_topic,
                    "Published comment like notification to Kafka"
                );
                Ok(())
            }
            Err((err, _)) => {
                warn!(
                    error = ?err,
                    like_id = %like_id,
                    comment_id = %comment_id,
                    "Failed to publish comment like notification to Kafka"
                );
                Err(anyhow::anyhow!("Failed to publish notification: {}", err))
            }
        }
    }

    /// Publish a share notification event to notification-service
    ///
    /// This sends a KafkaNotification to the PostShared topic that the
    /// notification-service consumes to create push notifications.
    ///
    /// # Arguments
    /// * `share_id` - The ID of the share
    /// * `post_id` - The ID of the post that was shared
    /// * `sharer_id` - The ID of the user who shared the post
    /// * `post_author_id` - The ID of the post author (notification recipient)
    /// * `sharer_username` - Optional username of the sharer for notification text
    pub async fn publish_share_notification(
        &self,
        share_id: Uuid,
        post_id: Uuid,
        sharer_id: Uuid,
        post_author_id: Uuid,
        sharer_username: Option<String>,
    ) -> Result<()> {
        // Don't send notification if user shared their own post
        if sharer_id == post_author_id {
            info!(
                sharer_id = %sharer_id,
                post_id = %post_id,
                "Skipping self-share notification"
            );
            return Ok(());
        }

        let username = sharer_username.unwrap_or_else(|| "Someone".to_string());

        let notification = KafkaNotification {
            id: share_id.to_string(),
            user_id: post_author_id, // Recipient of the notification
            event_type: "Share".to_string(),
            title: "Post Shared".to_string(),
            body: format!("{} shared your post", username),
            data: Some(serde_json::json!({
                "sender_id": sharer_id.to_string(),
                "object_id": post_id.to_string(),
                "object_type": "post",
                "share_id": share_id.to_string(),
            })),
            timestamp: Utc::now().timestamp(),
        };

        let payload = serde_json::to_string(&notification)?;
        let partition_key = post_author_id.to_string();

        // Use "PostShared" topic for share notifications
        let share_topic = "PostShared";

        let record = FutureRecord::to(share_topic)
            .key(&partition_key)
            .payload(&payload);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok(_) => {
                info!(
                    share_id = %share_id,
                    post_id = %post_id,
                    sharer_id = %sharer_id,
                    recipient_id = %post_author_id,
                    topic = %share_topic,
                    "Published share notification to Kafka"
                );
                Ok(())
            }
            Err((err, _)) => {
                warn!(
                    error = ?err,
                    share_id = %share_id,
                    post_id = %post_id,
                    "Failed to publish share notification to Kafka"
                );
                Err(anyhow::anyhow!("Failed to publish notification: {}", err))
            }
        }
    }

    /// Publish mention notifications for users @mentioned in content
    ///
    /// This sends KafkaNotifications to the MentionCreated topic for each mentioned user.
    ///
    /// # Arguments
    /// * `source_id` - The ID of the source content (comment_id or post_id)
    /// * `source_type` - The type of source ("post" or "comment")
    /// * `author_id` - The ID of the content author
    /// * `mentioned_user_ids` - List of user IDs that were mentioned
    /// * `author_username` - Optional username of the author for notification text
    /// * `content_preview` - Optional preview of the content
    pub async fn publish_mention_notifications(
        &self,
        source_id: Uuid,
        source_type: &str,
        author_id: Uuid,
        mentioned_user_ids: Vec<Uuid>,
        author_username: Option<String>,
        content_preview: Option<String>,
    ) -> Result<()> {
        if mentioned_user_ids.is_empty() {
            return Ok(());
        }

        let username = author_username.unwrap_or_else(|| "Someone".to_string());
        let preview = content_preview
            .map(|p| {
                if p.chars().count() > 50 {
                    format!("{}...", p.chars().take(47).collect::<String>())
                } else {
                    p
                }
            })
            .unwrap_or_default();

        let event_type = if source_type == "post" {
            "MentionPost"
        } else {
            "MentionComment"
        };

        let mention_topic = "MentionCreated";

        for user_id in mentioned_user_ids {
            // Don't notify self-mentions
            if user_id == author_id {
                info!(
                    author_id = %author_id,
                    "Skipping self-mention notification"
                );
                continue;
            }

            let body = if preview.is_empty() {
                format!("{} mentioned you", username)
            } else {
                format!("{} mentioned you: {}", username, preview)
            };

            let notification = KafkaNotification {
                id: Uuid::new_v4().to_string(),
                user_id,
                event_type: event_type.to_string(),
                title: "You were mentioned".to_string(),
                body,
                data: Some(serde_json::json!({
                    "sender_id": author_id.to_string(),
                    "object_id": source_id.to_string(),
                    "object_type": source_type,
                })),
                timestamp: Utc::now().timestamp(),
            };

            let payload = serde_json::to_string(&notification)?;
            let partition_key = user_id.to_string();

            let record = FutureRecord::to(mention_topic)
                .key(&partition_key)
                .payload(&payload);

            match self.producer.send(record, Duration::from_secs(5)).await {
                Ok(_) => {
                    info!(
                        source_id = %source_id,
                        source_type = %source_type,
                        mentioned_user_id = %user_id,
                        topic = %mention_topic,
                        "Published mention notification to Kafka"
                    );
                }
                Err((err, _)) => {
                    warn!(
                        error = ?err,
                        source_id = %source_id,
                        mentioned_user_id = %user_id,
                        "Failed to publish mention notification to Kafka"
                    );
                    // Continue with other mentions even if one fails
                }
            }
        }

        Ok(())
    }
}
