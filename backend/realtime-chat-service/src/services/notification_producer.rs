//! Kafka Notification Producer
//!
//! Publishes message notification events to Kafka for the notification-service
//! to consume and send push notifications.

use chrono::Utc;
use rdkafka::config::ClientConfig;
use rdkafka::producer::{FutureProducer, FutureRecord};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use uuid::Uuid;

/// Notification event types matching notification-service's KafkaNotification format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NotificationEventType {
    Like,
    Comment,
    Follow,
    LiveStart,
    Message,
    MentionPost,
    MentionComment,
}

impl std::fmt::Display for NotificationEventType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NotificationEventType::Like => write!(f, "like"),
            NotificationEventType::Comment => write!(f, "comment"),
            NotificationEventType::Follow => write!(f, "follow"),
            NotificationEventType::LiveStart => write!(f, "live_start"),
            NotificationEventType::Message => write!(f, "message"),
            NotificationEventType::MentionPost => write!(f, "mention_post"),
            NotificationEventType::MentionComment => write!(f, "mention_comment"),
        }
    }
}

/// Kafka notification event format matching notification-service's expected schema
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaNotification {
    pub id: String,
    pub user_id: Uuid,
    pub event_type: NotificationEventType,
    pub title: String,
    pub body: String,
    pub data: Option<serde_json::Value>,
    pub timestamp: i64,
}

/// Producer for sending notification events to Kafka
#[derive(Clone)]
pub struct NotificationProducer {
    producer: FutureProducer,
    topic: String,
}

impl NotificationProducer {
    /// Create a new notification producer
    pub fn new(brokers: &str, topic: &str) -> Result<Self, String> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("message.timeout.ms", "5000")
            .set("acks", "all")
            .set("retries", "3")
            .set("retry.backoff.ms", "100")
            .create()
            .map_err(|e| format!("Failed to create Kafka producer: {}", e))?;

        tracing::info!(
            brokers = %brokers,
            topic = %topic,
            "NotificationProducer initialized"
        );

        Ok(Self {
            producer,
            topic: topic.to_string(),
        })
    }

    /// Publish a message notification event
    ///
    /// Called when a new message is sent to notify the recipient.
    pub async fn publish_message_notification(
        &self,
        recipient_id: Uuid,
        sender_id: Uuid,
        sender_name: &str,
        conversation_id: Uuid,
        message_id: Uuid,
        message_preview: &str,
    ) -> Result<(), String> {
        let notification = KafkaNotification {
            id: Uuid::new_v4().to_string(),
            user_id: recipient_id,
            event_type: NotificationEventType::Message,
            title: sender_name.to_string(),
            body: truncate_message_preview(message_preview, 100),
            data: Some(serde_json::json!({
                "sender_id": sender_id.to_string(),
                "conversation_id": conversation_id.to_string(),
                "message_id": message_id.to_string(),
                "object_id": conversation_id.to_string(),
                "object_type": "conversation",
            })),
            timestamp: Utc::now().timestamp(),
        };

        self.publish(notification).await
    }

    /// Publish a notification event to Kafka
    async fn publish(&self, notification: KafkaNotification) -> Result<(), String> {
        let payload = serde_json::to_string(&notification)
            .map_err(|e| format!("Failed to serialize notification: {}", e))?;

        let key = notification.user_id.to_string();

        let record = FutureRecord::to(&self.topic)
            .key(&key)
            .payload(&payload);

        match self.producer.send(record, Duration::from_secs(5)).await {
            Ok((partition, offset)) => {
                tracing::debug!(
                    user_id = %notification.user_id,
                    event_type = %notification.event_type,
                    partition = partition,
                    offset = offset,
                    "Notification event published to Kafka"
                );
                Ok(())
            }
            Err((e, _)) => {
                tracing::error!(
                    error = %e,
                    user_id = %notification.user_id,
                    event_type = %notification.event_type,
                    "Failed to publish notification event to Kafka"
                );
                Err(format!("Failed to publish to Kafka: {}", e))
            }
        }
    }
}

/// Truncate message preview to a maximum length, adding ellipsis if needed
fn truncate_message_preview(message: &str, max_len: usize) -> String {
    if message.len() <= max_len {
        message.to_string()
    } else {
        let truncated: String = message.chars().take(max_len - 3).collect();
        format!("{}...", truncated)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_truncate_message_preview() {
        assert_eq!(truncate_message_preview("Hello", 100), "Hello");
        assert_eq!(truncate_message_preview("Hello world!", 8), "Hello...");
        assert_eq!(truncate_message_preview("Hi", 10), "Hi");
    }

    #[test]
    fn test_notification_event_type_display() {
        assert_eq!(NotificationEventType::Message.to_string(), "message");
        assert_eq!(NotificationEventType::Like.to_string(), "like");
    }

    #[test]
    fn test_kafka_notification_serialization() {
        let notification = KafkaNotification {
            id: "test-id".to_string(),
            user_id: Uuid::nil(),
            event_type: NotificationEventType::Message,
            title: "Test User".to_string(),
            body: "Hello!".to_string(),
            data: Some(serde_json::json!({"key": "value"})),
            timestamp: 1234567890,
        };

        let json = serde_json::to_string(&notification).unwrap();
        assert!(json.contains("\"event_type\":\"Message\""));
        assert!(json.contains("\"title\":\"Test User\""));
    }
}
