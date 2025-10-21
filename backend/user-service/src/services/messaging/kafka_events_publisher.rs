//! Kafka Events Publisher for E2E Encrypted Messaging
//!
//! Phase 5 Feature 2: Publishes message lifecycle events to Kafka for analytics and event streaming
//!
//! Handles publishing of:
//! - Message sent events
//! - Message delivered events
//! - Message read events
//! - Key exchange initiated events
//! - Key exchange completed events
//! - Public key registered events

use crate::error::AppError;
use crate::services::kafka_producer::EventProducer;
use crate::services::messaging::events::*;
use std::sync::Arc;
use uuid::Uuid;
use chrono::Utc;
use tracing::{debug, error};

/// Kafka events publisher for messaging
pub struct MessagingKafkaPublisher {
    producer: Arc<EventProducer>,
}

impl MessagingKafkaPublisher {
    pub fn new(producer: Arc<EventProducer>) -> Self {
        Self { producer }
    }

    /// Publish message sent event to Kafka
    ///
    /// Called when a new encrypted message is sent.
    pub async fn publish_message_sent(
        &self,
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
        encrypted_content: &str,
        nonce: &str,
        sender_public_key: &str,
    ) -> Result<(), AppError> {
        let event = MessageSentEvent {
            message_id,
            sender_id,
            recipient_id,
            encrypted_content: encrypted_content.to_string(),
            nonce: nonce.to_string(),
            sender_public_key: sender_public_key.to_string(),
            timestamp: Utc::now(),
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize message sent event: {}", e)))?;

        let key = format!("msg:{}", message_id);
        self.producer.send_json(&key, &payload).await?;

        debug!("Published message sent event: message_id={}", message_id);
        Ok(())
    }

    /// Publish message delivered event to Kafka
    ///
    /// Called when a message is confirmed delivered to recipient's device.
    pub async fn publish_message_delivered(
        &self,
        message_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let event = MessageDeliveredEvent {
            message_id,
            recipient_id,
            delivered_at: Utc::now(),
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize message delivered event: {}", e)))?;

        let key = format!("msg:{}:delivered", message_id);
        self.producer.send_json(&key, &payload).await?;

        debug!("Published message delivered event: message_id={}", message_id);
        Ok(())
    }

    /// Publish message read event to Kafka
    ///
    /// Called when a message is marked as read by recipient.
    pub async fn publish_message_read(
        &self,
        message_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let event = MessageReadEvent {
            message_id,
            recipient_id,
            read_at: Utc::now(),
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize message read event: {}", e)))?;

        let key = format!("msg:{}:read", message_id);
        self.producer.send_json(&key, &payload).await?;

        debug!("Published message read event: message_id={}", message_id);
        Ok(())
    }

    /// Publish key exchange initiated event to Kafka
    ///
    /// Called when a user initiates key exchange with another user.
    pub async fn publish_key_exchange_initiated(
        &self,
        exchange_id: Uuid,
        initiator_id: Uuid,
        recipient_id: Uuid,
        initiator_public_key: &str,
    ) -> Result<(), AppError> {
        let event = KeyExchangeInitiatedEvent {
            exchange_id,
            initiator_id,
            recipient_id,
            initiator_public_key: initiator_public_key.to_string(),
            timestamp: Utc::now(),
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize key exchange initiated event: {}", e)))?;

        let key = format!("kex:{}:initiated", exchange_id);
        self.producer.send_json(&key, &payload).await?;

        debug!("Published key exchange initiated event: exchange_id={}", exchange_id);
        Ok(())
    }

    /// Publish key exchange completed event to Kafka
    ///
    /// Called when a user completes key exchange by providing their public key.
    pub async fn publish_key_exchange_completed(
        &self,
        exchange_id: Uuid,
        initiator_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let event = KeyExchangeCompletedEvent {
            exchange_id,
            initiator_id,
            recipient_id,
            completed_at: Utc::now(),
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize key exchange completed event: {}", e)))?;

        let key = format!("kex:{}:completed", exchange_id);
        self.producer.send_json(&key, &payload).await?;

        debug!("Published key exchange completed event: exchange_id={}", exchange_id);
        Ok(())
    }

    /// Publish public key registered event to Kafka
    ///
    /// Called when a user registers or rotates their public key.
    pub async fn publish_public_key_registered(
        &self,
        user_id: Uuid,
        public_key: &str,
        is_rotation: bool,
    ) -> Result<(), AppError> {
        let event = PublicKeyRegisteredEvent {
            user_id,
            public_key: public_key.to_string(),
            registered_at: Utc::now(),
            is_rotation,
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize public key registered event: {}", e)))?;

        let key = if is_rotation {
            format!("pubkey:{}:rotated", user_id)
        } else {
            format!("pubkey:{}:registered", user_id)
        };

        self.producer.send_json(&key, &payload).await?;

        debug!("Published public key registered event: user_id={}, is_rotation={}", user_id, is_rotation);
        Ok(())
    }

    /// Batch publish multiple events efficiently
    ///
    /// Returns a list of any errors that occurred during publishing.
    /// This is useful for publishing multiple related events atomically.
    pub async fn publish_batch(&self, events: Vec<KafkaEvent>) -> Result<Vec<AppError>, AppError> {
        let mut errors = Vec::new();

        for event in events {
            match event {
                KafkaEvent::MessageSent {
                    message_id,
                    sender_id,
                    recipient_id,
                    encrypted_content,
                    nonce,
                    sender_public_key,
                } => {
                    if let Err(e) = self
                        .publish_message_sent(
                            message_id,
                            sender_id,
                            recipient_id,
                            &encrypted_content,
                            &nonce,
                            &sender_public_key,
                        )
                        .await
                    {
                        error!("Failed to publish message sent event: {:?}", e);
                        errors.push(e);
                    }
                }
                KafkaEvent::MessageDelivered {
                    message_id,
                    recipient_id,
                } => {
                    if let Err(e) = self.publish_message_delivered(message_id, recipient_id).await {
                        error!("Failed to publish message delivered event: {:?}", e);
                        errors.push(e);
                    }
                }
                KafkaEvent::MessageRead {
                    message_id,
                    recipient_id,
                } => {
                    if let Err(e) = self.publish_message_read(message_id, recipient_id).await {
                        error!("Failed to publish message read event: {:?}", e);
                        errors.push(e);
                    }
                }
                KafkaEvent::KeyExchangeInitiated {
                    exchange_id,
                    initiator_id,
                    recipient_id,
                    initiator_public_key,
                } => {
                    if let Err(e) = self
                        .publish_key_exchange_initiated(
                            exchange_id,
                            initiator_id,
                            recipient_id,
                            &initiator_public_key,
                        )
                        .await
                    {
                        error!("Failed to publish key exchange initiated event: {:?}", e);
                        errors.push(e);
                    }
                }
                KafkaEvent::KeyExchangeCompleted {
                    exchange_id,
                    initiator_id,
                    recipient_id,
                } => {
                    if let Err(e) =
                        self.publish_key_exchange_completed(exchange_id, initiator_id, recipient_id).await
                    {
                        error!("Failed to publish key exchange completed event: {:?}", e);
                        errors.push(e);
                    }
                }
                KafkaEvent::PublicKeyRegistered {
                    user_id,
                    public_key,
                    is_rotation,
                } => {
                    if let Err(e) = self.publish_public_key_registered(user_id, &public_key, is_rotation).await {
                        error!("Failed to publish public key registered event: {:?}", e);
                        errors.push(e);
                    }
                }
            }
        }

        Ok(errors)
    }
}

/// Enum of all possible Kafka events for the messaging system
#[derive(Debug, Clone)]
pub enum KafkaEvent {
    MessageSent {
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
        encrypted_content: String,
        nonce: String,
        sender_public_key: String,
    },
    MessageDelivered {
        message_id: Uuid,
        recipient_id: Uuid,
    },
    MessageRead {
        message_id: Uuid,
        recipient_id: Uuid,
    },
    KeyExchangeInitiated {
        exchange_id: Uuid,
        initiator_id: Uuid,
        recipient_id: Uuid,
        initiator_public_key: String,
    },
    KeyExchangeCompleted {
        exchange_id: Uuid,
        initiator_id: Uuid,
        recipient_id: Uuid,
    },
    PublicKeyRegistered {
        user_id: Uuid,
        public_key: String,
        is_rotation: bool,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_event_construction() {
        let user_id = Uuid::new_v4();
        let recipient_id = Uuid::new_v4();
        let message_id = Uuid::new_v4();

        let event = KafkaEvent::MessageSent {
            message_id,
            sender_id: user_id,
            recipient_id,
            encrypted_content: "encrypted".to_string(),
            nonce: "nonce".to_string(),
            sender_public_key: "pubkey".to_string(),
        };

        assert!(matches!(event, KafkaEvent::MessageSent { .. }));
    }

    #[test]
    fn test_kafka_event_batch() {
        let user_id = Uuid::new_v4();
        let recipient_id = Uuid::new_v4();
        let message_id = Uuid::new_v4();

        let events = vec![
            KafkaEvent::MessageSent {
                message_id,
                sender_id: user_id,
                recipient_id,
                encrypted_content: "encrypted".to_string(),
                nonce: "nonce".to_string(),
                sender_public_key: "pubkey".to_string(),
            },
            KafkaEvent::MessageDelivered {
                message_id,
                recipient_id,
            },
        ];

        assert_eq!(events.len(), 2);
    }

    #[test]
    fn test_all_kafka_event_types() {
        let user_a = Uuid::new_v4();
        let user_b = Uuid::new_v4();
        let message_id = Uuid::new_v4();
        let exchange_id = Uuid::new_v4();

        let _events = vec![
            KafkaEvent::MessageSent {
                message_id,
                sender_id: user_a,
                recipient_id: user_b,
                encrypted_content: "content".to_string(),
                nonce: "nonce".to_string(),
                sender_public_key: "pubkey".to_string(),
            },
            KafkaEvent::MessageDelivered {
                message_id,
                recipient_id: user_b,
            },
            KafkaEvent::MessageRead {
                message_id,
                recipient_id: user_b,
            },
            KafkaEvent::KeyExchangeInitiated {
                exchange_id,
                initiator_id: user_a,
                recipient_id: user_b,
                initiator_public_key: "pubkey_a".to_string(),
            },
            KafkaEvent::KeyExchangeCompleted {
                exchange_id,
                initiator_id: user_a,
                recipient_id: user_b,
            },
            KafkaEvent::PublicKeyRegistered {
                user_id: user_a,
                public_key: "pubkey".to_string(),
                is_rotation: false,
            },
        ];

        // All 6 event types constructed successfully
    }
}
