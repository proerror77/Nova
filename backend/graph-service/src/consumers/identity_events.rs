//! Kafka consumer for identity-service events
//!
//! P1: Syncs user data from identity-service to graph-service local users table.
//! This ensures FK constraints are satisfied when follow/block/mute events arrive.
//!
//! Supported events:
//! - UserCreatedEvent -> Upsert user in local users table
//! - UserProfileUpdatedEvent -> Update username in local users table
//! - UserDeletedEvent -> Soft delete user in local users table

use anyhow::Result;
use event_schema::{EventEnvelope, UserCreatedEvent, UserDeletedEvent, UserProfileUpdatedEvent};
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use std::time::Duration;
use tracing::{debug, error, info, warn};

use crate::repository::PostgresGraphRepository;

/// Consumer for identity-service events (user lifecycle)
pub struct IdentityEventsConsumer {
    consumer: StreamConsumer,
    repository: PostgresGraphRepository,
    topic: String,
}

impl IdentityEventsConsumer {
    /// Create a new IdentityEventsConsumer
    pub fn new(
        brokers: &str,
        group_id: &str,
        topic: &str,
        repository: PostgresGraphRepository,
    ) -> Result<Self> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("group.id", group_id)
            .set("enable.auto.commit", "true")
            .set("auto.offset.reset", "earliest")
            .set("session.timeout.ms", "30000")
            .set("enable.partition.eof", "false")
            .create()?;

        consumer.subscribe(&[topic])?;
        info!(
            "Created Kafka consumer for identity events: topic='{}', group='{}'",
            topic, group_id
        );

        Ok(Self {
            consumer,
            repository,
            topic: topic.to_string(),
        })
    }

    /// Start consuming events
    pub async fn start(self) -> Result<()> {
        info!(
            "Starting identity events consumer for topic '{}'",
            self.topic
        );

        loop {
            match self.consumer.recv().await {
                Ok(message) => {
                    if let Some(payload) = message.payload() {
                        if let Err(e) = self.process_message(payload).await {
                            error!("Failed to process identity event: {}", e);
                        }
                    }
                }
                Err(e) => {
                    error!("Kafka consumer error: {}", e);
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    /// Process a single Kafka message
    async fn process_message(&self, payload: &[u8]) -> Result<()> {
        let payload_str = std::str::from_utf8(payload)?;

        // Parse as generic JSON to inspect event_type
        let envelope_value: serde_json::Value = serde_json::from_str(payload_str)?;

        // P1: Use event_type field if present (preferred)
        if let Some(event_type) = envelope_value.get("event_type").and_then(|v| v.as_str()) {
            return match event_type {
                "UserCreatedEvent" => self.handle_user_created(payload_str).await,
                "UserProfileUpdatedEvent" => self.handle_user_profile_updated(payload_str).await,
                "UserDeletedEvent" => self.handle_user_deleted(payload_str).await,
                _ => {
                    debug!("Ignoring identity event type: {}", event_type);
                    Ok(())
                }
            };
        }

        // Fallback: Inspect payload fields for backward compatibility
        if let Some(data) = envelope_value.get("data") {
            if data.get("deleted_at").is_some() && data.get("soft_delete").is_some() {
                warn!("Legacy event format (no event_type). Processing as UserDeletedEvent.");
                return self.handle_user_deleted(payload_str).await;
            }
            if data.get("username").is_some() && data.get("email").is_some() {
                if data.get("created_at").is_some() && data.get("updated_at").is_none() {
                    warn!("Legacy event format (no event_type). Processing as UserCreatedEvent.");
                    return self.handle_user_created(payload_str).await;
                }
                if data.get("display_name").is_some() {
                    warn!(
                        "Legacy event format (no event_type). Processing as UserProfileUpdatedEvent."
                    );
                    return self.handle_user_profile_updated(payload_str).await;
                }
            }
        }

        debug!("Ignoring unknown identity event");
        Ok(())
    }

    /// Handle UserCreatedEvent
    async fn handle_user_created(&self, payload: &str) -> Result<()> {
        let envelope: EventEnvelope<UserCreatedEvent> = serde_json::from_str(payload)?;
        let event = envelope.data;

        info!(
            "Processing UserCreatedEvent: user_id={}, username={}",
            event.user_id, event.username
        );

        self.repository
            .upsert_user(event.user_id, &event.username)
            .await?;

        info!("Successfully created user in graph-service: {}", event.user_id);
        Ok(())
    }

    /// Handle UserProfileUpdatedEvent
    async fn handle_user_profile_updated(&self, payload: &str) -> Result<()> {
        let envelope: EventEnvelope<UserProfileUpdatedEvent> = serde_json::from_str(payload)?;
        let event = envelope.data;

        info!(
            "Processing UserProfileUpdatedEvent: user_id={}, username={}",
            event.user_id, event.username
        );

        self.repository
            .upsert_user(event.user_id, &event.username)
            .await?;

        info!(
            "Successfully updated user in graph-service: {}",
            event.user_id
        );
        Ok(())
    }

    /// Handle UserDeletedEvent
    async fn handle_user_deleted(&self, payload: &str) -> Result<()> {
        let envelope: EventEnvelope<UserDeletedEvent> = serde_json::from_str(payload)?;
        let event = envelope.data;

        info!(
            "Processing UserDeletedEvent: user_id={}, soft_delete={}",
            event.user_id, event.soft_delete
        );

        if event.soft_delete {
            self.repository.soft_delete_user(event.user_id).await?;
            info!(
                "Successfully soft deleted user in graph-service: {}",
                event.user_id
            );
        } else {
            // For hard deletes, the FK CASCADE will handle cleanup
            // We still soft delete to preserve audit trail
            self.repository.soft_delete_user(event.user_id).await?;
            info!(
                "Soft deleted user (hard delete requested) in graph-service: {}",
                event.user_id
            );
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_consumer_creation() {
        // This test requires Kafka broker - skip in unit tests
    }
}
