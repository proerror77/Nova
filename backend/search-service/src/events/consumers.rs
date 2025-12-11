use crate::services::elasticsearch::{
    ElasticsearchClient, ElasticsearchError, MessageDocument, UserDocument,
};
use chrono::{DateTime, Utc};
use serde::de::{Deserializer, Error as DeError};
use serde::Deserialize;
use serde_json::Value;
use std::sync::Arc;
use thiserror::Error;
use tracing::{debug, error};
use uuid::Uuid;

/// Shared context for Kafka event consumers.
///
/// Holds optional references to infrastructure components so that
/// individual handlers can remain lightweight and testable.
#[derive(Clone, Default)]
pub struct EventContext {
    search_backend: Option<Arc<ElasticsearchClient>>,
}

impl EventContext {
    /// Build a new event context with the provided Elasticsearch client.
    pub fn new(search_backend: Option<Arc<ElasticsearchClient>>) -> Self {
        Self { search_backend }
    }

    fn search_backend(&self) -> Option<&Arc<ElasticsearchClient>> {
        self.search_backend.as_ref()
    }
}

/// Errors that can occur while processing Kafka events.
#[derive(Debug, Error)]
pub enum EventError {
    #[error("failed to decode event payload: {0}")]
    Decode(#[from] serde_json::Error),
    #[error("search backend error: {0}")]
    Search(#[from] ElasticsearchError),
}

/// Event payload for `message_persisted`
#[derive(Debug, Deserialize)]
struct MessagePersistedEvent {
    message_id: Uuid,
    conversation_id: Uuid,
    sender_id: Uuid,
    #[serde(default)]
    content: Option<String>,
    #[serde(default)]
    #[serde(deserialize_with = "deserialize_optional_datetime")]
    created_at: Option<DateTime<Utc>>,
    /// Optional hint from producers to disable indexing for this message.
    #[serde(default)]
    search_disabled: Option<bool>,
}

/// Event payload for `message_deleted`
#[derive(Debug, Deserialize)]
struct MessageDeletedEvent {
    message_id: Uuid,
}

/// Handle `message_persisted` events coming from Kafka.
///
/// The handler is defensive: if the search backend is not configured or the
/// payload is missing content, the event is ignored gracefully while emitting
/// debug logs to assist with diagnosing pipeline gaps.
pub async fn on_message_persisted(ctx: &EventContext, payload: &[u8]) -> Result<(), EventError> {
    let event: MessagePersistedEvent = serde_json::from_slice(payload)?;

    if event.search_disabled.unwrap_or(false) {
        debug!(
            message_id = %event.message_id,
            "Skipping indexing for message because search was disabled by producer"
        );
        return Ok(());
    }

    let Some(content) = event
        .content
        .as_ref()
        .map(|c| c.trim())
        .filter(|c| !c.is_empty())
    else {
        debug!(
            message_id = %event.message_id,
            "Skipping message indexing: no plaintext content provided"
        );
        return Ok(());
    };

    let Some(search) = ctx.search_backend() else {
        debug!(
            message_id = %event.message_id,
            "Search backend not configured; Kafka event ignored"
        );
        return Ok(());
    };

    let document = MessageDocument {
        id: event.message_id,
        conversation_id: event.conversation_id,
        sender_id: event.sender_id,
        content: content.to_owned(),
        created_at: event.created_at.unwrap_or_else(Utc::now),
    };

    if let Err(err) = search.index_message(&document).await {
        error!(
            message_id = %event.message_id,
            "Failed to index message in Elasticsearch: {err}"
        );
        return Err(EventError::Search(err));
    }

    debug!(
        message_id = %event.message_id,
        conversation_id = %event.conversation_id,
        "Indexed message into Elasticsearch"
    );
    Ok(())
}

/// Handle `message_deleted` events coming from Kafka.
pub async fn on_message_deleted(ctx: &EventContext, payload: &[u8]) -> Result<(), EventError> {
    let event: MessageDeletedEvent = serde_json::from_slice(payload)?;

    let Some(search) = ctx.search_backend() else {
        debug!(
            message_id = %event.message_id,
            "Search backend not configured; delete event ignored"
        );
        return Ok(());
    };

    if let Err(err) = search.delete_message(event.message_id).await {
        error!(
            message_id = %event.message_id,
            "Failed to remove message from Elasticsearch: {err}"
        );
        return Err(EventError::Search(err));
    }

    debug!(
        message_id = %event.message_id,
        "Removed message document from Elasticsearch"
    );
    Ok(())
}

fn deserialize_optional_datetime<'de, D>(deserializer: D) -> Result<Option<DateTime<Utc>>, D::Error>
where
    D: Deserializer<'de>,
{
    let value: Option<Value> = Option::deserialize(deserializer)?;

    match value {
        None => Ok(None),
        Some(Value::String(s)) => DateTime::parse_from_rfc3339(&s)
            .map(|dt| Some(dt.with_timezone(&Utc)))
            .map_err(|e| D::Error::custom(format!("invalid RFC3339 timestamp: {e}"))),
        Some(Value::Number(num)) => {
            let millis = num
                .as_i64()
                .ok_or_else(|| D::Error::custom("expected integer timestamp"))?;

            // Treat 10-digit values as seconds, 13+ as milliseconds.
            let (secs, nanos) = if millis.abs() < 1_000_000_000_000 {
                (millis, 0)
            } else {
                (millis / 1000, (millis % 1000) * 1_000_000)
            };

            DateTime::<Utc>::from_timestamp(secs, nanos as u32)
                .map(Some)
                .ok_or_else(|| D::Error::custom("timestamp out of range"))
        }
        Some(other) => Err(D::Error::custom(format!(
            "unsupported timestamp representation: {other}"
        ))),
    }
}

// ============================================================================
// IDENTITY SERVICE EVENTS
// ============================================================================

/// Event envelope from identity-service
#[derive(Debug, Deserialize)]
struct IdentityEventEnvelope {
    #[serde(default)]
    event_id: Option<Uuid>,
    data: IdentityEventData,
}

/// Identity event data - can be UserCreated or UserProfileUpdated
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum IdentityEventData {
    UserCreated(UserCreatedEventData),
    UserProfileUpdated(UserProfileUpdatedEventData),
    UserDeleted(UserDeletedEventData),
}

#[derive(Debug, Deserialize)]
struct UserCreatedEventData {
    user_id: Uuid,
    #[serde(default)]
    email: Option<String>,
    username: String,
    #[serde(default)]
    created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
struct UserProfileUpdatedEventData {
    user_id: Uuid,
    username: String,
    #[serde(default)]
    display_name: Option<String>,
    #[serde(default)]
    bio: Option<String>,
    #[serde(default)]
    avatar_url: Option<String>,
    #[serde(default)]
    is_verified: bool,
    #[serde(default)]
    follower_count: i32,
    #[serde(default)]
    updated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize)]
struct UserDeletedEventData {
    user_id: Uuid,
    #[serde(default)]
    deleted_at: Option<DateTime<Utc>>,
    #[serde(default)]
    soft_delete: bool,
}

/// Handle identity events from Kafka (UserCreated, UserProfileUpdated, UserDeleted)
pub async fn on_identity_event(ctx: &EventContext, payload: &[u8]) -> Result<(), EventError> {
    let envelope: IdentityEventEnvelope = serde_json::from_slice(payload)?;

    let Some(search) = ctx.search_backend() else {
        debug!("Search backend not configured; identity event ignored");
        return Ok(());
    };

    match envelope.data {
        IdentityEventData::UserCreated(event) => {
            debug!(
                user_id = %event.user_id,
                username = %event.username,
                "Processing UserCreated event for search indexing"
            );

            // Index new user with minimal data (will be updated when profile is filled)
            let document = UserDocument {
                user_id: event.user_id,
                username: event.username,
                display_name: String::new(),
                bio: None,
                location: None,
                interests: vec![],
                is_verified: false,
                follower_count: 0,
            };

            if let Err(err) = search.index_user(&document).await {
                error!(
                    user_id = %event.user_id,
                    "Failed to index user in Elasticsearch: {err}"
                );
                return Err(EventError::Search(err));
            }

            debug!(
                user_id = %event.user_id,
                "Indexed new user into Elasticsearch"
            );
        }
        IdentityEventData::UserProfileUpdated(event) => {
            debug!(
                user_id = %event.user_id,
                username = %event.username,
                "Processing UserProfileUpdated event for search indexing"
            );

            let document = UserDocument {
                user_id: event.user_id,
                username: event.username,
                display_name: event.display_name.unwrap_or_default(),
                bio: event.bio,
                location: None,
                interests: vec![],
                is_verified: event.is_verified,
                follower_count: event.follower_count,
            };

            if let Err(err) = search.index_user(&document).await {
                error!(
                    user_id = %event.user_id,
                    "Failed to update user in Elasticsearch: {err}"
                );
                return Err(EventError::Search(err));
            }

            debug!(
                user_id = %event.user_id,
                "Updated user in Elasticsearch"
            );
        }
        IdentityEventData::UserDeleted(event) => {
            debug!(
                user_id = %event.user_id,
                soft_delete = event.soft_delete,
                "Processing UserDeleted event"
            );

            // Only remove from search index if hard delete
            if !event.soft_delete {
                if let Err(err) = search.delete_user(event.user_id).await {
                    error!(
                        user_id = %event.user_id,
                        "Failed to delete user from Elasticsearch: {err}"
                    );
                    return Err(EventError::Search(err));
                }

                debug!(
                    user_id = %event.user_id,
                    "Deleted user from Elasticsearch"
                );
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::de::IntoDeserializer;

    #[test]
    fn test_deserialize_datetime_from_rfc3339() {
        let payload = serde_json::json!("2024-05-18T12:34:56Z");
        let ts: Option<DateTime<Utc>> =
            deserialize_optional_datetime(payload.into_deserializer()).unwrap();
        assert!(ts.is_some());
        assert_eq!(ts.unwrap().timestamp(), 1716035696);
    }

    #[test]
    fn test_deserialize_datetime_from_millis() {
        let payload = serde_json::json!(1_716_035_696_123i64);
        let ts: Option<DateTime<Utc>> =
            deserialize_optional_datetime(payload.into_deserializer()).unwrap();
        assert!(ts.is_some());
        assert_eq!(ts.unwrap().timestamp_millis(), 1_716_035_696_123);
    }

    #[tokio::test]
    async fn test_skip_index_when_no_search_backend() {
        let ctx = EventContext::default();
        let event = serde_json::json!({
            "message_id": Uuid::new_v4(),
            "conversation_id": Uuid::new_v4(),
            "sender_id": Uuid::new_v4(),
            "content": "hello world"
        });

        let result = on_message_persisted(&ctx, event.to_string().as_bytes()).await;
        assert!(
            result.is_ok(),
            "Handler should succeed even without search backend"
        );
    }

    #[tokio::test]
    async fn test_skip_index_when_content_missing() {
        let ctx = EventContext::default();
        let event = serde_json::json!({
            "message_id": Uuid::new_v4(),
            "conversation_id": Uuid::new_v4(),
            "sender_id": Uuid::new_v4(),
            "content": ""
        });

        let result = on_message_persisted(&ctx, event.to_string().as_bytes()).await;
        assert!(result.is_ok(), "Handler should allow empty content");
    }
}
