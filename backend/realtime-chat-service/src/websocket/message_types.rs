use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Inbound WebSocket events from client to server
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsInboundEvent {
    // ============================================================
    // Basic Messaging Events
    // ============================================================
    #[serde(rename = "typing")]
    Typing {
        conversation_id: Uuid,
        user_id: Uuid,
    },
    #[serde(rename = "ack")]
    Ack {
        msg_id: String,
        conversation_id: Uuid,
    },
    #[serde(rename = "get_unacked")]
    GetUnacked,

    // ============================================================
    // E2EE Events (End-to-End Encryption)
    // ============================================================
    /// Request to-device messages for this device (key sharing, verification, etc.)
    #[serde(rename = "get_to_device_messages")]
    GetToDeviceMessages {
        device_id: String,
        #[serde(default)]
        since: Option<String>,
    },

    /// Acknowledge receipt of a to-device message
    #[serde(rename = "ack_to_device_message")]
    AckToDeviceMessage { message_id: String },

    /// Request room keys for a conversation (when joining late or after device rotation)
    #[serde(rename = "request_room_keys")]
    RequestRoomKeys {
        conversation_id: Uuid,
        device_id: String,
        session_id: String,
    },

    /// Share a room key with another device (Olm-encrypted Megolm key)
    #[serde(rename = "share_room_key")]
    ShareRoomKey {
        target_device_id: String,
        room_id: Uuid,
        /// Olm-encrypted room key content (base64)
        encrypted_key: String,
    },

    /// Send an E2EE encrypted message using Megolm
    #[serde(rename = "send_e2ee_message")]
    SendE2eeMessage {
        conversation_id: Uuid,
        device_id: String,
        /// Megolm session ID used for encryption
        session_id: String,
        /// Base64-encoded Megolm ciphertext
        ciphertext: String,
        /// Message index for ordering and replay prevention
        message_index: u32,
    },
}

/// Outbound WebSocket events from server to client
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsOutboundEvent {
    // ============================================================
    // Basic Messaging Events
    // ============================================================
    #[serde(rename = "typing")]
    Typing {
        conversation_id: Uuid,
        user_id: Uuid,
    },

    // ============================================================
    // E2EE Events (End-to-End Encryption)
    // ============================================================
    /// New to-device message arrived (key sharing, verification, etc.)
    #[serde(rename = "to_device_message")]
    ToDeviceMessage {
        id: String,
        sender_user_id: String,
        sender_device_id: String,
        message_type: String,
        /// Olm-encrypted content (base64)
        content: String,
    },

    /// Room key request from another device in the same account
    #[serde(rename = "room_key_request")]
    RoomKeyRequest {
        requester_device_id: String,
        room_id: Uuid,
        session_id: String,
    },

    /// E2EE encrypted message received from another user
    #[serde(rename = "e2ee_message")]
    E2eeMessage {
        message_id: Uuid,
        conversation_id: Uuid,
        sender_id: Uuid,
        sender_device_id: String,
        /// Megolm session ID used for encryption
        session_id: String,
        /// Base64-encoded Megolm ciphertext
        ciphertext: String,
        /// Message index for ordering and replay prevention
        message_index: u32,
        created_at: String,
    },

    /// Session rotation notification (new Megolm session created)
    #[serde(rename = "session_rotated")]
    SessionRotated {
        room_id: Uuid,
        old_session_id: String,
        new_session_id: String,
    },

    /// One-time key count low warning (client should upload more OTKs)
    #[serde(rename = "otk_count_low")]
    OtkCountLow {
        device_id: String,
        remaining_count: i32,
    },
}
