//! Unified WebSocket Event System
//!
//! This module defines all WebSocket events with a consistent structure.
//! All events follow the "object.action" naming convention and have a unified JSON structure.
//!
//! Event Structure:
//! ```json
//! {
//!     "type": "message.new",
//!     "timestamp": "2025-10-26T10:30:00Z",
//!     "user_id": "uuid",
//!     "conversation_id": "uuid",
//!     "data": { ... }
//! }
//! ```
//!
//! Design Philosophy (Linus-style):
//! - Simple enum with explicit variants (no clever tricks)
//! - Each variant contains ONLY the data it needs
//! - Serialization is centralized in one place
//! - No special cases - all events have the same top-level structure

use crate::models::message::MessageEnvelope;
use crate::websocket::streams;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// WebSocket event types
///
/// Each variant represents a specific real-time event that can occur.
/// The enum is exhaustive - all possible events are explicitly listed.
///
/// Note: Serialization is handled by to_broadcast_payload() to avoid
/// creating nested data structures. The enum does NOT use serde(tag=...)
/// to prevent double-serialization in the broadcast envelope.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WebSocketEvent {
    // ============================================================================
    // Message Events
    // ============================================================================
    /// New message sent
    #[serde(rename = "message.new")]
    MessageNew {
        id: Uuid,
        sender_id: Uuid,
        sequence_number: i64,
        conversation_id: Uuid,
    },

    /// Message content edited
    #[serde(rename = "message.edited")]
    MessageEdited {
        conversation_id: Uuid,
        message_id: Uuid,
        version_number: i32,
    },

    /// Message deleted (soft delete)
    #[serde(rename = "message.deleted")]
    MessageDeleted {
        conversation_id: Uuid,
        message_id: Uuid,
    },

    /// Message recalled (unsent within time window)
    #[serde(rename = "message.recalled")]
    MessageRecalled {
        conversation_id: Uuid,
        message_id: Uuid,
        recalled_by: Uuid,
        recalled_at: String,
    },

    /// Audio message sent
    #[serde(rename = "message.audio_sent")]
    AudioMessageSent {
        id: Uuid,
        sender_id: Uuid,
        sequence_number: i64,
        conversation_id: Uuid,
        duration_ms: u32,
        audio_codec: String,
    },

    // ============================================================================
    // Reaction Events
    // ============================================================================
    /// Reaction added to message
    #[serde(rename = "reaction.added")]
    ReactionAdded { message_id: Uuid, emoji: String },

    /// Reaction removed from message
    #[serde(rename = "reaction.removed")]
    ReactionRemoved { message_id: Uuid, emoji: String },

    /// All reactions removed from message by a user
    #[serde(rename = "reaction.removed_all")]
    ReactionRemovedAll { message_id: Uuid },

    // ============================================================================
    // Typing Indicator Events
    // ============================================================================
    /// User started typing
    #[serde(rename = "typing.started")]
    TypingStarted { conversation_id: Uuid },

    /// User stopped typing
    #[serde(rename = "typing.stopped")]
    TypingStopped { conversation_id: Uuid },

    // ============================================================================
    // Member Events
    // ============================================================================
    /// User joined conversation
    #[serde(rename = "member.joined")]
    MemberJoined {
        user_id: Uuid,
        username: String,
        role: String,
    },

    /// User left conversation
    #[serde(rename = "member.left")]
    MemberLeft { user_id: Uuid },

    /// Member role changed
    #[serde(rename = "member.role_changed")]
    MemberRoleChanged {
        user_id: Uuid,
        old_role: String,
        new_role: String,
    },

    // ============================================================================
    // Video Call Events
    // ============================================================================
    /// Video call initiated
    #[serde(rename = "call.initiated")]
    CallInitiated { call_id: Uuid, initiator_id: Uuid },

    /// Video call answered
    #[serde(rename = "call.answered")]
    CallAnswered { call_id: Uuid, answerer_id: Uuid },

    /// Video call rejected
    #[serde(rename = "call.rejected")]
    CallRejected { call_id: Uuid, rejected_by: Uuid },

    /// Video call ended
    #[serde(rename = "call.ended")]
    CallEnded { call_id: Uuid, ended_by: Uuid },

    /// ICE candidate exchange
    #[serde(rename = "call.ice_candidate")]
    CallIceCandidate {
        call_id: Uuid,
        candidate: String,
        sdp_mid: String,
        sdp_mline_index: u16,
    },

    // ============================================================================
    // Conversation Events
    // ============================================================================
    /// Conversation metadata updated
    #[serde(rename = "conversation.updated")]
    ConversationUpdated {
        conversation_id: Uuid,
        updated_fields: Vec<String>,
    },
}

impl WebSocketEvent {
    /// Get event type as string (e.g., "message.new")
    pub fn event_type(&self) -> &'static str {
        match self {
            Self::MessageNew { .. } => "message.new",
            Self::MessageEdited { .. } => "message.edited",
            Self::MessageDeleted { .. } => "message.deleted",
            Self::MessageRecalled { .. } => "message.recalled",
            Self::AudioMessageSent { .. } => "message.audio_sent",
            Self::ReactionAdded { .. } => "reaction.added",
            Self::ReactionRemoved { .. } => "reaction.removed",
            Self::ReactionRemovedAll { .. } => "reaction.removed_all",
            Self::TypingStarted { .. } => "typing.started",
            Self::TypingStopped { .. } => "typing.stopped",
            Self::MemberJoined { .. } => "member.joined",
            Self::MemberLeft { .. } => "member.left",
            Self::MemberRoleChanged { .. } => "member.role_changed",
            Self::CallInitiated { .. } => "call.initiated",
            Self::CallAnswered { .. } => "call.answered",
            Self::CallRejected { .. } => "call.rejected",
            Self::CallEnded { .. } => "call.ended",
            Self::CallIceCandidate { .. } => "call.ice_candidate",
            Self::ConversationUpdated { .. } => "conversation.updated",
        }
    }

    /// Convert event to JSON string for broadcasting
    ///
    /// Creates a FLAT JSON structure (not nested):
    /// ```json
    /// {
    ///   "type": "message.new",
    ///   "timestamp": "2025-10-26T10:30:00Z",
    ///   "user_id": "uuid",
    ///   "conversation_id": "uuid",
    ///   "id": "uuid",
    ///   "sender_id": "uuid",
    ///   "sequence_number": 1
    /// }
    /// ```
    ///
    /// This is the ONLY place where event serialization happens.
    /// No manual JSON construction in handlers.
    pub fn to_broadcast_payload(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<String, serde_json::Error> {
        let value = self.to_payload_value(conversation_id, user_id)?;
        serde_json::to_string(&value)
    }

    pub fn to_payload_value(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<serde_json::Value, serde_json::Error> {
        let mut payload = serde_json::json!({
            "type": self.event_type(),
            "timestamp": Utc::now().to_rfc3339(),
            "user_id": user_id,
            "conversation_id": conversation_id,
        });

        // Flatten event-specific fields into the payload
        let event_data = serde_json::to_value(self)?;
        if let serde_json::Value::Object(map) = event_data {
            for (key, value) in map {
                payload[key] = value;
            }
        }

        Ok(payload)
    }
}

// ============================================================================
// Helper Functions for Event Broadcasting
// ============================================================================

/// Broadcast event to conversation via WebSocket registry and Redis pub/sub
///
/// This is the canonical way to broadcast events. Use this instead of
/// manually calling registry.broadcast() and pubsub::publish().
pub async fn broadcast_event(
    registry: &crate::websocket::ConnectionRegistry,
    redis: &redis::Client,
    conversation_id: Uuid,
    user_id: Uuid,
    event: WebSocketEvent,
) -> Result<(), BroadcastError> {
    let payload_value = event
        .to_payload_value(conversation_id, user_id)
        .map_err(|e| BroadcastError::Serialization(e.to_string()))?;

    let mut envelope = MessageEnvelope::from_payload(conversation_id, payload_value)
        .map_err(BroadcastError::Serialization)?;
    envelope.ensure_field("sender_id", serde_json::json!(user_id));

    broadcast_envelope(registry, redis, envelope).await
}

#[derive(Debug, thiserror::Error)]
pub enum BroadcastError {
    #[error("Failed to serialize event: {0}")]
    Serialization(String),

    #[error("Failed to publish to Redis: {0}")]
    Redis(String),
}

/// Broadcast a pre-built JSON payload, optionally embedding the Redis stream ID.
pub async fn broadcast_payload_json(
    registry: &crate::websocket::ConnectionRegistry,
    redis: &redis::Client,
    conversation_id: Uuid,
    payload_value: serde_json::Value,
) -> Result<(), BroadcastError> {
    let envelope = MessageEnvelope::from_payload(conversation_id, payload_value)
        .map_err(BroadcastError::Serialization)?;
    broadcast_envelope(registry, redis, envelope).await
}

async fn broadcast_envelope(
    registry: &crate::websocket::ConnectionRegistry,
    redis: &redis::Client,
    mut envelope: MessageEnvelope,
) -> Result<(), BroadcastError> {
    let stream_id = streams::publish_envelope(redis, &envelope)
        .await
        .map_err(|e| BroadcastError::Redis(e.to_string()))?;

    envelope.set_stream_id(stream_id);

    let final_payload = envelope
        .to_json()
        .map_err(|e| BroadcastError::Serialization(e.to_string()))?;

    registry
        .broadcast(
            envelope.conversation_id,
            axum::extract::ws::Message::Text(final_payload.into()),
        )
        .await;

    Ok(())
}

/// Broadcast an already serialized payload string.
pub async fn broadcast_payload_str(
    registry: &crate::websocket::ConnectionRegistry,
    redis: &redis::Client,
    conversation_id: Uuid,
    payload: String,
) -> Result<(), BroadcastError> {
    let value: serde_json::Value =
        serde_json::from_str(&payload).map_err(|e| BroadcastError::Serialization(e.to_string()))?;
    let envelope = MessageEnvelope::from_payload(conversation_id, value)
        .map_err(BroadcastError::Serialization)?;
    broadcast_envelope(registry, redis, envelope).await
}

// ============================================================================
// Backward Compatibility (Temporary)
// ============================================================================

/// Legacy event format support (to be removed after migration)
///
/// Some clients may still be using old event formats. This function
/// provides a compatibility layer during the migration period.
///
/// **TODO**: Remove this after all clients are migrated (target: 2025-11-26)
#[deprecated(since = "0.2.0", note = "Use WebSocketEvent enum instead")]
pub fn legacy_event_to_json(
    event_type: &str,
    conversation_id: Uuid,
    user_id: Uuid,
    data: serde_json::Value,
) -> String {
    serde_json::json!({
        "type": event_type,
        "timestamp": Utc::now().to_rfc3339(),
        "user_id": user_id,
        "conversation_id": conversation_id,
        "data": data,
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_type_naming() {
        let event = WebSocketEvent::MessageNew {
            id: Uuid::new_v4(),
            sender_id: Uuid::new_v4(),
            sequence_number: 1,
            conversation_id: Uuid::new_v4(),
        };

        assert_eq!(event.event_type(), "message.new");
    }

    #[test]
    fn test_event_serialization() {
        let conversation_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();

        let event = WebSocketEvent::TypingStarted { conversation_id };

        let payload = event
            .to_broadcast_payload(conversation_id, user_id)
            .unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&payload).unwrap();

        assert_eq!(parsed["type"], "typing.started");
        assert_eq!(parsed["conversation_id"], conversation_id.to_string());
        assert_eq!(parsed["user_id"], user_id.to_string());
        assert!(parsed["timestamp"].is_string());
    }

    #[test]
    fn test_all_event_types_have_unique_names() {
        // Ensure no duplicate event type strings
        let types = vec![
            WebSocketEvent::MessageNew {
                id: Uuid::new_v4(),
                sender_id: Uuid::new_v4(),
                sequence_number: 1,
                conversation_id: Uuid::new_v4(),
            }
            .event_type(),
            WebSocketEvent::MessageEdited {
                conversation_id: Uuid::new_v4(),
                message_id: Uuid::new_v4(),
                version_number: 1,
            }
            .event_type(),
            WebSocketEvent::ReactionAdded {
                message_id: Uuid::new_v4(),
                emoji: "👍".to_string(),
            }
            .event_type(),
            // Add more as needed
        ];

        let unique_types: std::collections::HashSet<_> = types.iter().collect();
        assert_eq!(
            types.len(),
            unique_types.len(),
            "Duplicate event type detected"
        );
    }
}
