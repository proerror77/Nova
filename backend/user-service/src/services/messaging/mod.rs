//! Private Messaging Service with End-to-End Encryption
//!
//! Phase 5 Feature 2: Complete messaging implementation with E2E encryption and real-time delivery
//!
//! ## Architecture
//!
//! This module provides secure 1:1 messaging with client-side encryption:
//!
//! 1. **End-to-End Encryption**: All messages encrypted with NaCl Box (Curve25519 + ChaCha20-Poly1305)
//! 2. **Key Exchange Protocol**: Diffie-Hellman based public key exchange
//! 3. **Server-Side Key Management**: Stores and distributes public keys without exposing private keys
//! 4. **Forward Secrecy**: Per-message nonces, key rotation support (30-day default)
//! 5. **Delivery Tracking**: Track message delivery (sent → delivered → read)
//! 6. **Real-Time Delivery**: Redis Pub/Sub for WebSocket message pushing
//! 7. **Event Streaming**: Kafka events for analytics and audit trail

// Core encryption module (implemented and tested)
pub mod encryption;

// Message service with database operations
pub mod message_service;

// Kafka event definitions for event streaming
pub mod events;

// Real-time message delivery via Redis Pub/Sub + WebSocket
pub mod websocket_handler;

// Kafka event publishing for message lifecycle
pub mod kafka_events_publisher;

// Phase 4 (Future) - Group Messaging & Typing Indicators
// See GitHub Issue #T217 for implementation roadmap
// pub mod conversation_service; // Group messaging support
// pub mod typing_indicators;    // Typing notification aggregation

pub use encryption::{
    EncryptionService, PublicKey, Nonce, KeyExchange, KeyExchangeStatus,
    EncryptedMessage, UserPublicKey,
};
pub use message_service::MessageService;
pub use events::*;
pub use websocket_handler::{MessagingWebSocketHandler, MessageEvent, TypingEvent, ReadReceiptEvent, DeliveredEvent};
pub use kafka_events_publisher::{MessagingKafkaPublisher, KafkaEvent};
