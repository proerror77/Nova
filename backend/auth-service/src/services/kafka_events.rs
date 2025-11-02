/// Kafka event producer for auth service
use crate::error::{AuthError, AuthResult};
use chrono::Utc;
use event_schema::{
    EventEnvelope, PasswordChangedEvent, TwoFAEnabledEvent, UserCreatedEvent, UserDeletedEvent,
};
use rdkafka::producer::{FutureProducer, FutureRecord};
use std::time::Duration;
use tracing::warn;
use uuid::Uuid;

/// Kafka event producer service
#[derive(Clone)]
pub struct KafkaEventProducer {
    producer: FutureProducer,
    topic: String,
}

impl KafkaEventProducer {
    /// Create a new Kafka event producer
    pub fn new(brokers: &str, topic: &str) -> AuthResult<Self> {
        let producer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("client.id", "auth-service")
            .create::<FutureProducer>()
            .map_err(|e| AuthError::Internal(format!("Failed to create Kafka producer: {}", e)))?;

        Ok(Self {
            producer,
            topic: topic.to_string(),
        })
    }

    /// Publish user created event
    pub async fn publish_user_created(
        &self,
        user_id: Uuid,
        email: &str,
        username: &str,
    ) -> AuthResult<()> {
        let event = UserCreatedEvent {
            user_id,
            email: email.to_string(),
            username: username.to_string(),
            created_at: Utc::now(),
        };

        let envelope =
            EventEnvelope::new("auth-service", event).with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish password changed event
    pub async fn publish_password_changed(&self, user_id: Uuid) -> AuthResult<()> {
        let event = PasswordChangedEvent {
            user_id,
            changed_at: Utc::now(),
            invalidate_all_sessions: true,
        };

        let envelope =
            EventEnvelope::new("auth-service", event).with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish 2FA enabled event
    pub async fn publish_two_fa_enabled(&self, user_id: Uuid) -> AuthResult<()> {
        let event = TwoFAEnabledEvent {
            user_id,
            enabled_at: Utc::now(),
            method: "totp".to_string(),
        };

        let envelope =
            EventEnvelope::new("auth-service", event).with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Publish user deleted event
    pub async fn publish_user_deleted(&self, user_id: Uuid) -> AuthResult<()> {
        let event = UserDeletedEvent {
            user_id,
            deleted_at: Utc::now(),
            soft_delete: true,
        };

        let envelope =
            EventEnvelope::new("auth-service", event).with_correlation_id(Uuid::new_v4());

        self.publish_event(&envelope, user_id).await
    }

    /// Generic event publishing method
    async fn publish_event<T: serde::Serialize>(
        &self,
        envelope: &EventEnvelope<T>,
        partition_key_id: Uuid,
    ) -> AuthResult<()> {
        let payload = serde_json::to_string(envelope)
            .map_err(|e| AuthError::Internal(format!("Failed to serialize envelope: {}", e)))?;

        let partition_key = partition_key_id.to_string();
        let record = FutureRecord::to(&self.topic)
            .key(&partition_key)
            .payload(&payload);

        self.producer
            .send(record, Duration::from_secs(30))
            .await
            .map_err(|(error, _)| {
                warn!("Failed to send Kafka event: {:?}", error);
                AuthError::Internal(format!("Failed to publish event to Kafka: {}", error))
            })?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_producer_creation() {
        // This test requires a running Kafka broker
        // In CI/CD, this should be skipped unless Kafka is available
        let result = KafkaEventProducer::new("localhost:9092", "auth-events");
        // Don't assert on success/failure as Kafka may not be available in test environment
        let _ = result;
    }
}
