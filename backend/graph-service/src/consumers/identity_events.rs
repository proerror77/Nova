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
use rdkafka::message::{BorrowedMessage, Headers, Message};
use serde::de::DeserializeOwned;
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
                        if let Err(e) = self.process_message(&message, payload).await {
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
    async fn process_message(
        &self,
        message: &BorrowedMessage<'_>,
        payload: &[u8],
    ) -> Result<()> {
        let payload_str = std::str::from_utf8(payload)?;
        let header_event_type = header_value(message, "event_type");

        // Parse as generic JSON to inspect event_type
        let envelope_value: serde_json::Value = serde_json::from_str(payload_str)?;

        // Prefer Kafka header event_type; fall back to envelope field if present.
        if let Some(event_type) = header_event_type
            .or_else(|| envelope_value.get("event_type").and_then(|v| v.as_str()))
        {
            return match event_type {
                "identity.user.created" | "UserCreatedEvent" => {
                    let event = parse_enveloped_or_direct::<UserCreatedEvent>(payload)?;
                    self.handle_user_created(event).await
                }
                "identity.user.profile_updated" | "UserProfileUpdatedEvent" => {
                    let event = parse_enveloped_or_direct::<UserProfileUpdatedEvent>(payload)?;
                    self.handle_user_profile_updated(event).await
                }
                "identity.user.deleted" | "UserDeletedEvent" => {
                    let event = parse_enveloped_or_direct::<UserDeletedEvent>(payload)?;
                    self.handle_user_deleted(event).await
                }
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
                let event = parse_enveloped_or_direct::<UserDeletedEvent>(payload)?;
                return self.handle_user_deleted(event).await;
            }
            if data.get("username").is_some() && data.get("email").is_some() {
                if data.get("created_at").is_some() && data.get("updated_at").is_none() {
                    warn!("Legacy event format (no event_type). Processing as UserCreatedEvent.");
                    let event = parse_enveloped_or_direct::<UserCreatedEvent>(payload)?;
                    return self.handle_user_created(event).await;
                }
                if data.get("display_name").is_some() {
                    warn!(
                        "Legacy event format (no event_type). Processing as UserProfileUpdatedEvent."
                    );
                    let event = parse_enveloped_or_direct::<UserProfileUpdatedEvent>(payload)?;
                    return self.handle_user_profile_updated(event).await;
                }
            }
        }

        debug!("Ignoring unknown identity event");
        Ok(())
    }

    /// Handle UserCreatedEvent
    async fn handle_user_created(&self, event: UserCreatedEvent) -> Result<()> {
        info!(
            "Processing UserCreatedEvent: user_id={}, username={}",
            event.user_id, event.username
        );

        self.repository
            .upsert_user(event.user_id, &event.username)
            .await?;

        info!(
            "Successfully created user in graph-service: {}",
            event.user_id
        );
        Ok(())
    }

    /// Handle UserProfileUpdatedEvent
    async fn handle_user_profile_updated(&self, event: UserProfileUpdatedEvent) -> Result<()> {
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
    async fn handle_user_deleted(&self, event: UserDeletedEvent) -> Result<()> {
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

fn parse_enveloped_or_direct<T: DeserializeOwned>(payload: &[u8]) -> Result<T> {
    if let Ok(envelope) = serde_json::from_slice::<EventEnvelope<T>>(payload) {
        return Ok(envelope.data);
    }
    Ok(serde_json::from_slice::<T>(payload)?)
}

fn header_value<'a>(message: &'a BorrowedMessage<'a>, key: &str) -> Option<&'a str> {
    message
        .headers()
        .and_then(|headers| {
            headers
                .iter()
                .find(|header| header.key == key)
                .and_then(|header| header.value)
        })
        .and_then(|value| std::str::from_utf8(value).ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_consumer_creation() {
        // This test requires Kafka broker - skip in unit tests
    }
}
