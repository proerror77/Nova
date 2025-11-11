//! Kafka Producer for Publishing Events
//! ✅ P0-5: Publish events to Kafka topics for other services
//!
//! Used for:
//! - Publishing subscription updates
//! - Event audit logging
//! - Integration with other microservices

use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{info, debug};

use super::KafkaError;
use super::consumer::{KafkaFeedEvent, KafkaMessageEvent, KafkaNotificationEvent};

/// Kafka producer for publishing events
pub struct KafkaProducer {
    producer: FutureProducer,
    broker_list: String,
}

impl KafkaProducer {
    /// Create new Kafka producer
    pub async fn new(broker_list: &str) -> Result<Self, KafkaError> {
        let producer = ClientConfig::new()
            .set("bootstrap.servers", broker_list)
            .set("message.timeout.ms", "5000")
            .set("compression.type", "snappy")
            .create::<FutureProducer>()
            .map_err(|e| KafkaError::ProducerError(e.to_string()))?;

        info!(broker_list = %broker_list, "Kafka producer created");

        Ok(Self {
            producer,
            broker_list: broker_list.to_string(),
        })
    }

    /// Publish a feed event
    pub async fn publish_feed_event(&self, event: KafkaFeedEvent) -> Result<(), KafkaError> {
        let payload = serde_json::to_vec(&event)
            .map_err(|e| KafkaError::SerializationError(e.to_string()))?;

        let key = event.post_id.clone();

        let record = FutureRecord::to("feed.events")
            .payload(&payload)
            .key(&key);

        self.producer
            .send(record, Duration::from_secs(30))
            .await
            .map_err(|e| KafkaError::ProducerError(format!("{:?}", e)))?;

        debug!(post_id = %event.post_id, "Published feed event to Kafka");
        Ok(())
    }

    /// Publish a message event
    pub async fn publish_message_event(&self, event: KafkaMessageEvent) -> Result<(), KafkaError> {
        let payload = serde_json::to_vec(&event)
            .map_err(|e| KafkaError::SerializationError(e.to_string()))?;

        // Use recipient_id as key to ensure ordering for user
        let key = format!("{}:{}", event.recipient_id, event.sender_id);

        let record = FutureRecord::to("messaging.events")
            .payload(&payload)
            .key(&key);

        self.producer
            .send(record, Duration::from_secs(30))
            .await
            .map_err(|e| KafkaError::ProducerError(format!("{:?}", e)))?;

        debug!(message_id = %event.message_id, "Published message event to Kafka");
        Ok(())
    }

    /// Publish a notification event
    pub async fn publish_notification_event(&self, event: KafkaNotificationEvent) -> Result<(), KafkaError> {
        let payload = serde_json::to_vec(&event)
            .map_err(|e| KafkaError::SerializationError(e.to_string()))?;

        // Use user_id as key to ensure ordering for user
        let key = event.user_id.clone();

        let record = FutureRecord::to("notification.events")
            .payload(&payload)
            .key(&key);

        self.producer
            .send(record, Duration::from_secs(30))
            .await
            .map_err(|e| KafkaError::ProducerError(format!("{:?}", e)))?;

        debug!(notification_id = %event.notification_id, "Published notification event to Kafka");
        Ok(())
    }

    /// Wait for pending messages (FutureProducer auto-flushes)
    pub async fn flush(&self) -> Result<(), KafkaError> {
        // FutureProducer automatically handles delivery confirmation
        // This is a no-op but kept for API compatibility
        info!("Kafka producer ready");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feed_event_serialization() {
        let event = KafkaFeedEvent {
            post_id: "post_1".to_string(),
            creator_id: "user_1".to_string(),
            content: "Test content".to_string(),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            event_type: "post_created".to_string(),
        };

        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("post_1"));
        assert!(json.contains("post_created"));

        let deserialized: KafkaFeedEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.post_id, event.post_id);
    }

    #[test]
    fn test_message_event_serialization() {
        let event = KafkaMessageEvent {
            message_id: "msg_1".to_string(),
            conversation_id: "conv_1".to_string(),
            sender_id: "user_1".to_string(),
            recipient_id: "user_2".to_string(),
            content: "Hello".to_string(),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            encrypted: true,
        };

        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("msg_1"));
        assert!(json.contains("user_2"));

        let deserialized: KafkaMessageEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.sender_id, event.sender_id);
        assert_eq!(deserialized.recipient_id, event.recipient_id);
    }

    #[test]
    fn test_notification_event_serialization() {
        let event = KafkaNotificationEvent {
            notification_id: "notif_1".to_string(),
            user_id: "user_1".to_string(),
            actor_id: "user_2".to_string(),
            action: "like".to_string(),
            target_id: Some("post_1".to_string()),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            read: false,
        };

        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("notif_1"));
        assert!(json.contains("like"));

        let deserialized: KafkaNotificationEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.action, event.action);
        assert!(!deserialized.read);
    }
}
