//! Kafka Producer for Publishing Events with Circuit Breaker Protection
//! ✅ P0-5: Publish events to Kafka topics for other services
//!
//! Used for:
//! - Publishing subscription updates
//! - Event audit logging
//! - Integration with other microservices

use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use resilience::{CircuitBreaker, CircuitBreakerError, CircuitState};
use std::sync::Arc;
use std::time::Duration;
use tracing::{debug, info, warn};

use super::consumer::{KafkaFeedEvent, KafkaMessageEvent, KafkaNotificationEvent};
use super::KafkaError;

/// Kafka producer for publishing events with circuit breaker protection
pub struct KafkaProducer {
    producer: FutureProducer,
    #[allow(dead_code)]
    broker_list: String,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl KafkaProducer {
    /// Create new Kafka producer with idempotency guarantees and circuit breaker
    ///
    /// Configuration ensures:
    /// - `enable.idempotence = true`: Prevents duplicate messages on retry (exactly-once per session)
    /// - `acks = all`: Waits for all replicas to acknowledge (durability guarantee)
    /// - `max.in.flight.requests.per.connection = 5`: Maintains ordering with idempotence enabled
    /// - `retries = 5`: Limited retries to allow circuit breaker to trip
    /// - `compression.type = lz4`: Fast compression (better than snappy for CPU-bound workloads)
    /// - Circuit breaker: Prevents cascading failures when Kafka is unhealthy
    pub async fn new(broker_list: &str) -> Result<Self, KafkaError> {
        let producer = ClientConfig::new()
            .set("bootstrap.servers", broker_list)
            .set("message.timeout.ms", "30000") // 30 second timeout
            .set("request.timeout.ms", "30000")
            // Idempotency configuration (prevents duplicates on retry)
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("max.in.flight.requests.per.connection", "5")
            .set("retries", "5") // Limited retries to allow circuit breaker to trip
            // Performance optimizations
            .set("compression.type", "lz4")
            .set("linger.ms", "10")
            .set("batch.size", "16384")
            .set("queue.buffering.max.messages", "100000")
            .create::<FutureProducer>()
            .map_err(|e| KafkaError::ProducerError(e.to_string()))?;

        // Use Kafka-optimized circuit breaker config
        let cb_config = resilience::presets::kafka_config().circuit_breaker;
        let circuit_breaker = Arc::new(CircuitBreaker::new(cb_config));

        info!(
            broker_list = %broker_list,
            "Kafka producer created with idempotency and circuit breaker enabled"
        );

        Ok(Self {
            producer,
            broker_list: broker_list.to_string(),
            circuit_breaker,
        })
    }

    /// Get current circuit breaker state
    pub fn circuit_state(&self) -> CircuitState {
        self.circuit_breaker.state()
    }

    /// Check if circuit breaker is open
    pub fn is_circuit_open(&self) -> bool {
        matches!(self.circuit_state(), CircuitState::Open)
    }

    /// Get current error rate
    pub fn error_rate(&self) -> f64 {
        self.circuit_breaker.error_rate()
    }

    /// Internal helper to send with circuit breaker tracking
    async fn send_with_circuit_breaker(
        &self,
        topic: &str,
        key: &str,
        payload: &[u8],
    ) -> Result<(), KafkaError> {
        let producer = self.producer.clone();
        let topic = topic.to_string();
        let key = key.to_string();
        let payload = payload.to_vec();

        let result = self
            .circuit_breaker
            .call(|| async {
                let record = FutureRecord::to(&topic).payload(&payload).key(&key);
                producer
                    .send(record, Duration::from_secs(30))
                    .await
                    .map(|_| ())
                    .map_err(|(err, _)| format!("{:?}", err))
            })
            .await;

        match result {
            Ok(()) => Ok(()),
            Err(CircuitBreakerError::Open) => {
                warn!(
                    topic = %topic,
                    circuit_state = ?self.circuit_state(),
                    "Circuit breaker open - rejecting Kafka publish"
                );
                Err(KafkaError::ProducerError(
                    "Circuit breaker open".to_string(),
                ))
            }
            Err(CircuitBreakerError::CallFailed(msg)) => {
                warn!(
                    topic = %topic,
                    error = %msg,
                    circuit_state = ?self.circuit_state(),
                    error_rate = self.error_rate(),
                    "Kafka publish failed"
                );
                Err(KafkaError::ProducerError(msg))
            }
        }
    }

    /// Publish a feed event with circuit breaker protection
    ///
    /// Uses creator_id as partition key to ensure all events from the same
    /// creator are delivered in order to the same partition.
    pub async fn publish_feed_event(&self, event: KafkaFeedEvent) -> Result<(), KafkaError> {
        let payload = serde_json::to_vec(&event)
            .map_err(|e| KafkaError::SerializationError(e.to_string()))?;

        // Use creator_id as key to ensure ordering per creator
        // This guarantees that all feed events from the same user are processed in order
        let key = event.creator_id.clone();

        self.send_with_circuit_breaker("feed.events", &key, &payload)
            .await?;

        debug!(
            post_id = %event.post_id,
            creator_id = %event.creator_id,
            "Published feed event to Kafka"
        );
        Ok(())
    }

    /// Publish a message event with circuit breaker protection
    pub async fn publish_message_event(&self, event: KafkaMessageEvent) -> Result<(), KafkaError> {
        let payload = serde_json::to_vec(&event)
            .map_err(|e| KafkaError::SerializationError(e.to_string()))?;

        // Use recipient_id as key to ensure ordering for user
        let key = format!("{}:{}", event.recipient_id, event.sender_id);

        self.send_with_circuit_breaker("messaging.events", &key, &payload)
            .await?;

        debug!(message_id = %event.message_id, "Published message event to Kafka");
        Ok(())
    }

    /// Publish a notification event with circuit breaker protection
    pub async fn publish_notification_event(
        &self,
        event: KafkaNotificationEvent,
    ) -> Result<(), KafkaError> {
        let payload = serde_json::to_vec(&event)
            .map_err(|e| KafkaError::SerializationError(e.to_string()))?;

        // Use user_id as key to ensure ordering for user
        let key = event.user_id.clone();

        self.send_with_circuit_breaker("notification.events", &key, &payload)
            .await?;

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
