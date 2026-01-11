/// Kafka consumer for Nova identity service events
///
/// Consumes events from `nova.identity.events` topic and syncs user lifecycle
/// events to Matrix (Synapse) via Admin API.
///
/// Supported events:
/// - UserDeletedEvent -> Deactivate Matrix account
/// - UserProfileUpdatedEvent -> Update Matrix displayname/avatar
use crate::error::AppError;
use crate::services::matrix_admin::MatrixAdminClient;
use event_schema::{EventEnvelope, UserDeletedEvent, UserProfileUpdatedEvent};
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::{Headers, Message};
use serde::de::DeserializeOwned;
use serde_json;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{error, info, warn};

/// Identity event consumer configuration
#[derive(Debug, Clone)]
pub struct IdentityEventConsumerConfig {
    /// Kafka broker addresses (comma-separated)
    pub brokers: String,
    /// Consumer group ID
    pub group_id: String,
    /// Topic to consume from
    pub topic: String,
    /// Whether Matrix sync is enabled
    pub matrix_enabled: bool,
}

/// Kafka consumer for identity events with Matrix sync
pub struct IdentityEventConsumer {
    consumer: StreamConsumer,
    matrix_admin: Option<Arc<MatrixAdminClient>>,
    avatar_sync: Option<Arc<crate::services::avatar_sync::AvatarSyncService>>,
    config: IdentityEventConsumerConfig,
}

impl IdentityEventConsumer {
    /// Create a new identity event consumer
    ///
    /// # Arguments
    /// * `config` - Consumer configuration
    /// * `matrix_admin` - Optional Matrix admin client (None if Matrix is disabled)
    /// * `avatar_sync` - Optional avatar sync service (None if Matrix is disabled)
    pub fn new(
        config: IdentityEventConsumerConfig,
        matrix_admin: Option<Arc<MatrixAdminClient>>,
        avatar_sync: Option<Arc<crate::services::avatar_sync::AvatarSyncService>>,
    ) -> Result<Self, AppError> {
        info!(
            "Initializing IdentityEventConsumer: brokers={}, group_id={}, topic={}, matrix_enabled={}",
            config.brokers, config.group_id, config.topic, config.matrix_enabled
        );

        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("group.id", &config.group_id)
            .set("enable.auto.commit", "true")
            .set("auto.offset.reset", "latest") // Start from latest to avoid replaying all historical events
            .set("session.timeout.ms", "30000")
            .set("enable.partition.eof", "false")
            .create()
            .map_err(|e| AppError::StartServer(format!("Failed to create Kafka consumer: {}", e)))?;

        consumer
            .subscribe(&[&config.topic])
            .map_err(|e| AppError::StartServer(format!("Failed to subscribe to topic: {}", e)))?;

        info!(
            "Successfully subscribed to Kafka topic: {}",
            config.topic
        );

        Ok(Self {
            consumer,
            matrix_admin,
            avatar_sync,
            config,
        })
    }

    /// Start consuming events in a background loop
    ///
    /// This method runs forever and should be spawned in a background task.
    /// It automatically retries on transient errors with exponential backoff.
    pub async fn start_consuming(self: Arc<Self>) {
        info!("Starting IdentityEventConsumer loop...");

        loop {
            match self.consume_loop().await {
                Ok(_) => {
                    warn!("Kafka consumer loop exited unexpectedly, restarting...");
                }
                Err(e) => {
                    error!("Kafka consumer error: {}, retrying in 5s...", e);
                    sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    /// Internal consume loop
    async fn consume_loop(&self) -> Result<(), AppError> {
        loop {
            match self.consumer.recv().await {
                Ok(message) => {
                    if let Err(e) = self.handle_message(&message).await {
                        error!(
                            "Failed to handle Kafka message from topic {}: {}",
                            self.config.topic, e
                        );
                        // Continue processing other messages even if one fails
                    }
                }
                Err(e) => {
                    error!("Kafka recv error: {}", e);
                    return Err(AppError::StartServer(format!("Kafka recv failed: {}", e)));
                }
            }
        }
    }

    /// Handle a single Kafka message
    async fn handle_message(
        &self,
        message: &rdkafka::message::BorrowedMessage<'_>,
    ) -> Result<(), AppError> {
        let payload = match message.payload() {
            Some(p) => p,
            None => {
                warn!("Received Kafka message with no payload, skipping");
                return Ok(());
            }
        };

        let payload_str = std::str::from_utf8(payload).map_err(|e| {
            AppError::StartServer(format!("Invalid UTF-8 in Kafka message payload: {}", e))
        })?;
        let header_event_type = header_value(message, "event_type");

        // Try to parse as a generic serde_json::Value first to inspect event type
        let envelope_value: serde_json::Value = serde_json::from_str(payload_str).map_err(|e| {
            warn!("Failed to parse Kafka message as JSON: {}", e);
            AppError::StartServer(format!("Invalid JSON in Kafka message: {}", e))
        })?;

        // Prefer Kafka header event_type; fall back to envelope field if present.
        if let Some(event_type) = header_event_type
            .or_else(|| envelope_value.get("event_type").and_then(|v| v.as_str()))
        {
            return match event_type {
                "identity.user.deleted" | "UserDeletedEvent" => {
                    let event = parse_enveloped_or_direct::<UserDeletedEvent>(payload)?;
                    self.handle_user_deleted(event).await
                }
                "identity.user.profile_updated" | "UserProfileUpdatedEvent" => {
                    let event = parse_enveloped_or_direct::<UserProfileUpdatedEvent>(payload)?;
                    self.handle_user_profile_updated(event).await
                }
                _ => {
                    // Unknown event type, skip silently
                    // This allows us to ignore other events like UserCreatedEvent, PasswordChangedEvent, etc.
                    Ok(())
                }
            };
        }

        // Fallback: Legacy field inspection for backward compatibility
        // Remove this fallback once all producers include event_type
        if let Some(data) = envelope_value.get("data") {
            // Check for UserDeletedEvent by looking for 'deleted_at' and 'soft_delete' fields
            if data.get("deleted_at").is_some() && data.get("soft_delete").is_some() {
                warn!("Legacy event format detected (no event_type field). Consider updating producer to include event_type.");
                let event = parse_enveloped_or_direct::<UserDeletedEvent>(payload)?;
                return self.handle_user_deleted(event).await;
            }

            // Check for UserProfileUpdatedEvent by looking for 'username' and 'updated_at' fields
            if data.get("username").is_some() && data.get("updated_at").is_some() && data.get("display_name").is_some() {
                warn!("Legacy event format detected (no event_type field). Consider updating producer to include event_type.");
                let event = parse_enveloped_or_direct::<UserProfileUpdatedEvent>(payload)?;
                return self.handle_user_profile_updated(event).await;
            }
        }

        // Unknown event type, skip silently
        Ok(())
    }

    /// Handle UserDeletedEvent
    async fn handle_user_deleted(&self, event: UserDeletedEvent) -> Result<(), AppError> {
        info!(
            "Processing UserDeletedEvent: user_id={}, soft_delete={}, deleted_at={}",
            event.user_id, event.soft_delete, event.deleted_at
        );

        // Only sync to Matrix if enabled
        if !self.config.matrix_enabled {
            info!("Matrix sync disabled, skipping Matrix deactivation for user {}", event.user_id);
            return Ok(());
        }

        let matrix_admin = match &self.matrix_admin {
            Some(client) => client,
            None => {
                warn!("Matrix admin client not initialized, skipping Matrix deactivation");
                return Ok(());
            }
        };

        // Deactivate Matrix account
        // erase=true if soft_delete=false (hard delete removes profile data)
        let erase = !event.soft_delete;
        if let Err(e) = matrix_admin.deactivate_user(event.user_id, erase).await {
            error!(
                "Failed to deactivate Matrix user for user_id={}: {}",
                event.user_id, e
            );
            // Don't propagate error - we want to continue processing other events
        } else {
            info!(
                "Successfully deactivated Matrix user for user_id={}, erase={}",
                event.user_id, erase
            );
        }

        Ok(())
    }

    /// Handle UserProfileUpdatedEvent
    async fn handle_user_profile_updated(
        &self,
        event: UserProfileUpdatedEvent,
    ) -> Result<(), AppError> {
        info!(
            "Processing UserProfileUpdatedEvent: user_id={}, username={}, display_name={:?}, avatar={:?}",
            event.user_id, event.username, event.display_name, event.avatar_url
        );

        // Only sync to Matrix if enabled
        if !self.config.matrix_enabled {
            info!("Matrix sync disabled, skipping Matrix profile update for user {}", event.user_id);
            return Ok(());
        }

        let matrix_admin = match &self.matrix_admin {
            Some(client) => client,
            None => {
                warn!("Matrix admin client not initialized, skipping Matrix profile update");
                return Ok(());
            }
        };

        // Use display_name if available, otherwise fall back to username
        let displayname = event.display_name.or(Some(event.username));

        // Sync avatar to Matrix if avatar_sync service is available
        let mxc_avatar_url = if let Some(avatar_sync) = &self.avatar_sync {
            match avatar_sync.sync_avatar_to_matrix(event.user_id, event.avatar_url.clone()).await {
                Ok(mxc_url) => {
                    if let Some(ref mxc) = mxc_url {
                        info!("Successfully synced avatar to Matrix for user {}: {}", event.user_id, mxc);
                    }
                    mxc_url
                }
                Err(e) => {
                    error!("Failed to sync avatar to Matrix for user {}: {}", event.user_id, e);
                    // Fall back to original avatar_url if sync fails
                    event.avatar_url.clone()
                }
            }
        } else {
            // No avatar sync service - use original avatar_url
            event.avatar_url.clone()
        };

        // Update Matrix profile with display_name and synced avatar mxc:// URL
        if let Err(e) = matrix_admin
            .update_profile(event.user_id, displayname, mxc_avatar_url)
            .await
        {
            error!(
                "Failed to update Matrix profile for user_id={}: {}",
                event.user_id, e
            );
            // Don't propagate error - we want to continue processing other events
        } else {
            info!(
                "Successfully updated Matrix profile for user_id={}",
                event.user_id
            );
        }

        Ok(())
    }
}

fn parse_enveloped_or_direct<T: DeserializeOwned>(payload: &[u8]) -> Result<T, AppError> {
    if let Ok(envelope) = serde_json::from_slice::<EventEnvelope<T>>(payload) {
        return Ok(envelope.data);
    }
    serde_json::from_slice::<T>(payload).map_err(|e| {
        AppError::StartServer(format!("Failed to deserialize identity event payload: {}", e))
    })
}

fn header_value<'a>(
    message: &'a rdkafka::message::BorrowedMessage<'a>,
    key: &str,
) -> Option<&'a str> {
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
    fn test_consumer_config_creation() {
        let config = IdentityEventConsumerConfig {
            brokers: "localhost:9092".to_string(),
            group_id: "realtime-chat-service".to_string(),
            topic: "nova.identity.events".to_string(),
            matrix_enabled: true,
        };

        assert_eq!(config.brokers, "localhost:9092");
        assert_eq!(config.topic, "nova.identity.events");
    }
}
