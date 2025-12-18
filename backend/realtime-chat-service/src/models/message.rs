use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value as JsonValue};
use uuid::Uuid;

/// Message struct matching database schema
/// Schema note: Columns from migrations 0004 (base), 0005 (content), and 0011 (megolm)
/// E2E encryption fields (content_encrypted, content_nonce, encryption_version) were dropped in migration 0009
/// PostgreSQL TDE handles encryption at the database level
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub content: String,
    pub sequence_number: i64,
    pub idempotency_key: Option<String>,
    pub created_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub reaction_count: i32,
    pub version_number: i32,
    pub recalled_at: Option<DateTime<Utc>>,
}

/// Envelope used for realtime fanout and Redis Streams persistence.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageEnvelope {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stream_id: Option<String>,
    pub conversation_id: Uuid,
    #[serde(flatten)]
    pub data: Map<String, JsonValue>,
}

impl MessageEnvelope {
    /// Build an envelope from a JSON object representing the event payload.
    /// Automatically stamps `conversation_id` and ensures `timestamp` field exists.
    pub fn from_payload(conversation_id: Uuid, payload: JsonValue) -> Result<Self, String> {
        let mut data = payload
            .as_object()
            .cloned()
            .ok_or_else(|| "event payload must be a JSON object".to_string())?;

        data.remove("stream_id");
        data.remove("conversation_id");

        // Ensure timestamp exists so downstream consumers have ordering context.
        if !data.contains_key("timestamp") {
            data.insert(
                "timestamp".to_string(),
                JsonValue::String(Utc::now().to_rfc3339()),
            );
        }

        Ok(Self {
            stream_id: None,
            conversation_id,
            data,
        })
    }

    /// Parse an envelope from the serialized JSON string stored in Redis Streams.
    pub fn from_json(payload: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str::<MessageEnvelope>(payload)
    }

    /// Convert envelope to JSON string for storage / broadcast.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Set the stream identifier (after persisting to Redis Streams).
    pub fn set_stream_id(&mut self, id: String) {
        self.stream_id = Some(id.clone());
        // Reflect stream id into payload for backward compatibility.
        self.data
            .insert("stream_id".to_string(), JsonValue::String(id));
    }

    /// Ensure a field exists with the provided value if missing.
    pub fn ensure_field<V: Into<JsonValue>>(&mut self, key: &str, value: V) {
        self.data
            .entry(key.to_string())
            .or_insert_with(|| value.into());
    }

    /// Retrieve the event type (if present).
    pub fn event_type(&self) -> Option<&str> {
        self.data.get("type").and_then(|v| v.as_str())
    }

    /// Retrieve the sender id if encoded in payload.
    pub fn sender_id(&self) -> Option<Uuid> {
        self.data
            .get("sender_id")
            .and_then(|v| v.as_str())
            .and_then(|s| Uuid::parse_str(s).ok())
    }
}
