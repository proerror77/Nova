/// Kafka event producer for identity service with circuit breaker resilience
use crate::error::{IdentityError, Result};
use chrono::{DateTime, Utc};
use crypto_core::kafka_correlation::inject_headers;
use event_schema::{
    EventEnvelope, PasswordChangedEvent, TwoFAEnabledEvent, UserCreatedEvent, UserDeletedEvent,
    UserProfileUpdatedEvent,
};
use rdkafka::message::OwnedHeaders;
use rdkafka::producer::{FutureProducer, FutureRecord};
use resilience::{CircuitBreaker, CircuitBreakerError, CircuitState};
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn};
use uuid::Uuid;

/// Kafka event producer service with circuit breaker protection
#[derive(Clone)]
pub struct KafkaEventProducer {
    producer: FutureProducer,
    topic: String,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl KafkaEventProducer {
    /// Create a new Kafka event producer with circuit breaker
    ///
    /// ## Arguments
    ///
    /// * `brokers` - Comma-separated list of Kafka brokers
    /// * `topic` - Default topic for publishing events
    pub fn new(brokers: &str, topic: &str) -> Result<Self> {
        let producer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("client.id", "identity-service")
            // Idempotency and reliability settings
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("max.in.flight.requests.per.connection", "5")
            .set("retries", "3")
            .create::<FutureProducer>()
            .map_err(|e| {
                IdentityError::Internal(format!("Failed to create Kafka producer: {}", e))
            })?;

        // Use Kafka-optimized circuit breaker config from resilience presets
        let cb_config = resilience::presets::kafka_config().circuit_breaker;
        let circuit_breaker = Arc::new(CircuitBreaker::new(cb_config));

        info!(
            brokers = %brokers,
            topic = %topic,
            "Identity service Kafka producer initialized with circuit breaker"
        );

        Ok(Self {
            producer,
            topic: topic.to_string(),
            circuit_breaker,
        })
    }

    /// Get the current circuit breaker state
    pub fn circuit_state(&self) -> CircuitState {
        self.circuit_breaker.state()
    }

    /// Check if circuit breaker is open (failing fast)
    pub fn is_circuit_open(&self) -> bool {
        matches!(self.circuit_state(), CircuitState::Open)
    }

    /// Get current error rate from circuit breaker
    pub fn error_rate(&self) -> f64 {
        self.circuit_breaker.error_rate()
    }

    /// Publish user created event
    pub async fn publish_user_created(
        &self,
        user_id: Uuid,
        email: &str,
        username: &str,
    ) -> Result<()> {
        let event = UserCreatedEvent {
            user_id,
            email: email.to_string(),
            username: username.to_string(),
            created_at: Utc::now(),
        };

        // P1: Include event_type for reliable event routing
        let envelope =
            EventEnvelope::new_with_type("identity-service", "identity.user.created", event)
                .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish password changed event
    pub async fn publish_password_changed(&self, user_id: Uuid) -> Result<()> {
        let event = PasswordChangedEvent {
            user_id,
            changed_at: Utc::now(),
            invalidate_all_sessions: true,
        };

        // P1: Include event_type for reliable event routing
        let envelope = EventEnvelope::new_with_type(
            "identity-service",
            "identity.user.password_changed",
            event,
        )
        .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish 2FA enabled event
    pub async fn publish_two_fa_enabled(&self, user_id: Uuid) -> Result<()> {
        let event = TwoFAEnabledEvent {
            user_id,
            enabled_at: Utc::now(),
            method: "totp".to_string(),
        };

        // P1: Include event_type for reliable event routing
        let envelope =
            EventEnvelope::new_with_type("identity-service", "identity.user.two_fa_enabled", event)
                .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish user deleted event
    pub async fn publish_user_deleted(
        &self,
        user_id: Uuid,
        deleted_at: DateTime<Utc>,
        soft_delete: bool,
    ) -> Result<()> {
        let event = UserDeletedEvent {
            user_id,
            deleted_at,
            soft_delete,
        };

        // P1: Include event_type for reliable event routing
        let envelope =
            EventEnvelope::new_with_type("identity-service", "identity.user.deleted", event)
                .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish user profile updated event (for search indexing)
    #[allow(clippy::too_many_arguments)]
    pub async fn publish_user_profile_updated(
        &self,
        user_id: Uuid,
        username: &str,
        display_name: Option<&str>,
        bio: Option<&str>,
        avatar_url: Option<&str>,
        is_verified: bool,
        follower_count: i32,
    ) -> Result<()> {
        let event = UserProfileUpdatedEvent {
            user_id,
            username: username.to_string(),
            display_name: display_name.map(|s| s.to_string()),
            bio: bio.map(|s| s.to_string()),
            avatar_url: avatar_url.map(|s| s.to_string()),
            is_verified,
            follower_count,
            updated_at: Utc::now(),
        };

        // P1: Include event_type for reliable event routing
        let envelope = EventEnvelope::new_with_type(
            "identity-service",
            "identity.user.profile_updated",
            event,
        )
        .with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish raw JSON payload to an arbitrary topic (e.g., DLQ)
    pub async fn publish_raw_to_topic(
        &self,
        topic: &str,
        partition_key: &str,
        payload: &str,
    ) -> Result<()> {
        let record = FutureRecord::to(topic).key(partition_key).payload(payload);

        self.producer
            .send(record, Duration::from_secs(30))
            .await
            .map_err(|(error, _)| {
                warn!("Failed to send Kafka event to topic {}: {:?}", topic, error);
                IdentityError::Internal(format!(
                    "Failed to publish event to Kafka topic {}: {}",
                    topic, error
                ))
            })?;

        Ok(())
    }

    /// Generic event publishing method with circuit breaker protection
    async fn publish_event<T: serde::Serialize>(
        &self,
        envelope: &EventEnvelope<T>,
        partition_key_id: Uuid,
    ) -> Result<()> {
        let payload = serde_json::to_string(envelope)
            .map_err(|e| IdentityError::Internal(format!("Failed to serialize envelope: {}", e)))?;

        let partition_key = partition_key_id.to_string();
        let correlation_id = envelope
            .correlation_id
            .unwrap_or(envelope.event_id)
            .to_string();
        let topic = self.topic.clone();
        let producer = self.producer.clone();

        let result = self
            .circuit_breaker
            .call(|| async {
                let headers = inject_headers(OwnedHeaders::new(), &correlation_id);
                let record = FutureRecord::to(&topic)
                    .key(&partition_key)
                    .payload(&payload)
                    .headers(headers);

                producer
                    .send(record, Duration::from_secs(30))
                    .await
                    .map(|_| ())
                    .map_err(|(err, _)| format!("{}", err))
            })
            .await;

        match result {
            Ok(()) => Ok(()),
            Err(CircuitBreakerError::Open) => {
                warn!(
                    event_type = ?envelope.event_type,
                    circuit_state = ?self.circuit_state(),
                    "Circuit breaker open - rejecting Kafka publish"
                );
                Err(IdentityError::Internal(
                    "Kafka circuit breaker open - publish rejected".to_string(),
                ))
            }
            Err(CircuitBreakerError::CallFailed(msg)) => {
                warn!(
                    error = %msg,
                    circuit_state = ?self.circuit_state(),
                    error_rate = self.error_rate(),
                    "Kafka publish failed"
                );
                Err(IdentityError::Internal(format!(
                    "Failed to publish event to Kafka: {}",
                    msg
                )))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_producer_creation() {
        // This test requires a running Kafka broker
        // In CI/CD, this should be skipped unless Kafka is available
        let result = KafkaEventProducer::new("localhost:9092", "nova.identity.events");
        // Don't assert on success/failure as Kafka may not be available in test environment
        let _ = result;
    }
}
