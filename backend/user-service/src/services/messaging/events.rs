//! Kafka Events for E2E Encrypted Messaging
//!
//! Phase 5 Feature 2: Event definitions for message delivery, read receipts, and key exchange

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Event published when a new encrypted message is sent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageSentEvent {
    pub message_id: Uuid,
    pub sender_id: Uuid,
    pub recipient_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,
    pub sender_public_key: String,
    pub timestamp: DateTime<Utc>,
}

/// Event published when a message is delivered to recipient
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageDeliveredEvent {
    pub message_id: Uuid,
    pub recipient_id: Uuid,
    pub delivered_at: DateTime<Utc>,
}

/// Event published when a message is read by recipient
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageReadEvent {
    pub message_id: Uuid,
    pub recipient_id: Uuid,
    pub read_at: DateTime<Utc>,
}

/// Event published when a key exchange is initiated
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyExchangeInitiatedEvent {
    pub exchange_id: Uuid,
    pub initiator_id: Uuid,
    pub recipient_id: Uuid,
    pub initiator_public_key: String,
    pub timestamp: DateTime<Utc>,
}

/// Event published when a key exchange is completed
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyExchangeCompletedEvent {
    pub exchange_id: Uuid,
    pub initiator_id: Uuid,
    pub recipient_id: Uuid,
    pub completed_at: DateTime<Utc>,
}

/// Event published when a user registers or rotates their public key
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicKeyRegisteredEvent {
    pub user_id: Uuid,
    pub public_key: String,
    pub registered_at: DateTime<Utc>,
    pub is_rotation: bool,
}

// ============================================
// Kafka Topic Constants
// ============================================

pub const TOPIC_MESSAGE_SENT: &str = "messaging.message.sent";
pub const TOPIC_MESSAGE_DELIVERED: &str = "messaging.message.delivered";
pub const TOPIC_MESSAGE_READ: &str = "messaging.message.read";
pub const TOPIC_KEY_EXCHANGE_INITIATED: &str = "messaging.key_exchange.initiated";
pub const TOPIC_KEY_EXCHANGE_COMPLETED: &str = "messaging.key_exchange.completed";
pub const TOPIC_PUBLIC_KEY_REGISTERED: &str = "messaging.public_key.registered";
