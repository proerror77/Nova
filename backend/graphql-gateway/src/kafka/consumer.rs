//! Kafka Consumer for Subscription Events
//! ✅ P0-5: Subscribe to and process events from Kafka topics
//!
//! Subscribes to three main topics:
//! - feed.events: Feed updates
//! - messaging.events: Direct messages
//! - notification.events: Notifications

use futures_util::stream::Stream;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use serde::{Deserialize, Serialize};
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

use super::KafkaError;

/// Feed event from Kafka
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaFeedEvent {
    pub post_id: String,
    pub creator_id: String,
    pub content: String,
    pub created_at: String,
    pub event_type: String,
}

/// Message event from Kafka
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaMessageEvent {
    pub message_id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub recipient_id: String,
    pub content: String,
    pub created_at: String,
    pub encrypted: bool,
}

/// Notification event from Kafka
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaNotificationEvent {
    pub notification_id: String,
    pub user_id: String,
    pub actor_id: String,
    pub action: String,
    pub target_id: Option<String>,
    pub created_at: String,
    pub read: bool,
}

/// Unified event type
#[derive(Debug, Clone)]
pub enum KafkaEvent {
    Feed(KafkaFeedEvent),
    Message(KafkaMessageEvent),
    Notification(KafkaNotificationEvent),
}

/// Kafka consumer for subscription events
pub struct KafkaConsumer {
    consumer: Arc<StreamConsumer>,
    topics: Vec<String>,
    tx: mpsc::UnboundedSender<KafkaEvent>,
}

impl KafkaConsumer {
    /// Create new Kafka consumer
    pub fn new(
        consumer: StreamConsumer,
        topics: Vec<String>,
        tx: mpsc::UnboundedSender<KafkaEvent>,
    ) -> Self {
        Self {
            consumer: Arc::new(consumer),
            topics,
            tx,
        }
    }

    /// Subscribe to topics
    pub async fn subscribe(&self) -> Result<(), KafkaError> {
        let topics: Vec<&str> = self.topics.iter().map(|s| s.as_str()).collect();
        self.consumer
            .subscribe(&topics)
            .map_err(|e| KafkaError::ConsumerError(e.to_string()))?;

        info!(topics = ?self.topics, "Subscribed to Kafka topics");
        Ok(())
    }

    /// Start consuming events
    pub async fn start_consuming(self) -> Result<(), KafkaError> {
        // Spawn consumer task
        tokio::spawn(async move {
            debug!("Starting Kafka consumer loop");

            loop {
                match self.consumer.recv().await {
                    Ok(msg) => {
                        // Parse message
                        if let Some(payload) = msg.payload() {
                            let topic = msg.topic();

                            match topic {
                                "feed.events" => {
                                    if let Ok(event) =
                                        serde_json::from_slice::<KafkaFeedEvent>(payload)
                                    {
                                        debug!(post_id = %event.post_id, "Received feed event");
                                        let _ = self.tx.send(KafkaEvent::Feed(event));
                                    } else {
                                        warn!("Failed to deserialize feed event");
                                    }
                                }
                                "messaging.events" => {
                                    if let Ok(event) =
                                        serde_json::from_slice::<KafkaMessageEvent>(payload)
                                    {
                                        debug!(message_id = %event.message_id, "Received message event");
                                        let _ = self.tx.send(KafkaEvent::Message(event));
                                    } else {
                                        warn!("Failed to deserialize message event");
                                    }
                                }
                                "notification.events" => {
                                    if let Ok(event) =
                                        serde_json::from_slice::<KafkaNotificationEvent>(payload)
                                    {
                                        debug!(notification_id = %event.notification_id, "Received notification event");
                                        let _ = self.tx.send(KafkaEvent::Notification(event));
                                    } else {
                                        warn!("Failed to deserialize notification event");
                                    }
                                }
                                _ => {
                                    debug!(topic = %topic, "Received event from unknown topic");
                                }
                            }
                        }
                    }
                    Err(e) => {
                        error!("Kafka consumer error: {}", e);
                        // Continue consuming on transient errors
                        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                    }
                }
            }
        });

        Ok(())
    }
}

/// Stream wrapper for Kafka events
pub struct KafkaEventStream {
    rx: mpsc::UnboundedReceiver<KafkaEvent>,
}

impl KafkaEventStream {
    /// Create new event stream
    pub fn new(rx: mpsc::UnboundedReceiver<KafkaEvent>) -> Self {
        Self { rx }
    }

    /// Filter feed events for a specific user
    /// In production, you'd filter based on user's interests
    pub fn filter_feed_for_user(user_id: &str) -> impl Fn(KafkaEvent) -> bool {
        let user_id = user_id.to_string();
        move |event: KafkaEvent| {
            // Filter logic: could check user's interests, muted creators, etc.
            // For now, accept all feed events
            matches!(event, KafkaEvent::Feed(_))
        }
    }

    /// Filter message events for a specific user
    pub fn filter_messages_for_user(user_id: &str) -> impl Fn(KafkaEvent) -> bool {
        let user_id = user_id.to_string();
        move |event: KafkaEvent| match &event {
            KafkaEvent::Message(msg) => msg.recipient_id == user_id,
            _ => false,
        }
    }

    /// Filter notification events for a specific user
    pub fn filter_notifications_for_user(user_id: &str) -> impl Fn(KafkaEvent) -> bool {
        let user_id = user_id.to_string();
        move |event: KafkaEvent| match &event {
            KafkaEvent::Notification(notif) => notif.user_id == user_id,
            _ => false,
        }
    }
}

impl Stream for KafkaEventStream {
    type Item = KafkaEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.rx.poll_recv(cx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_feed_event_creation() {
        let event = KafkaFeedEvent {
            post_id: "post_1".to_string(),
            creator_id: "user_1".to_string(),
            content: "Test content".to_string(),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            event_type: "post_created".to_string(),
        };

        assert_eq!(event.post_id, "post_1");
        assert_eq!(event.event_type, "post_created");
    }

    #[test]
    fn test_kafka_message_event_creation() {
        let event = KafkaMessageEvent {
            message_id: "msg_1".to_string(),
            conversation_id: "conv_1".to_string(),
            sender_id: "user_1".to_string(),
            recipient_id: "user_2".to_string(),
            content: "Hello".to_string(),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            encrypted: true,
        };

        assert_eq!(event.sender_id, "user_1");
        assert_eq!(event.recipient_id, "user_2");
        assert!(event.encrypted);
    }

    #[test]
    fn test_kafka_notification_event_creation() {
        let event = KafkaNotificationEvent {
            notification_id: "notif_1".to_string(),
            user_id: "user_1".to_string(),
            actor_id: "user_2".to_string(),
            action: "like".to_string(),
            target_id: Some("post_1".to_string()),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            read: false,
        };

        assert_eq!(event.action, "like");
        assert!(!event.read);
    }

    #[test]
    fn test_filter_messages_for_user() {
        let filter = KafkaEventStream::filter_messages_for_user("user_1");

        let msg_event = KafkaEvent::Message(KafkaMessageEvent {
            message_id: "msg_1".to_string(),
            conversation_id: "conv_1".to_string(),
            sender_id: "user_2".to_string(),
            recipient_id: "user_1".to_string(),
            content: "Hello".to_string(),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            encrypted: false,
        });

        assert!(filter(msg_event));
    }

    #[test]
    fn test_filter_notifications_for_user() {
        let filter = KafkaEventStream::filter_notifications_for_user("user_1");

        let notif_event = KafkaEvent::Notification(KafkaNotificationEvent {
            notification_id: "notif_1".to_string(),
            user_id: "user_1".to_string(),
            actor_id: "user_2".to_string(),
            action: "like".to_string(),
            target_id: Some("post_1".to_string()),
            created_at: "2024-01-01T00:00:00Z".to_string(),
            read: false,
        });

        assert!(filter(notif_event));
    }
}
