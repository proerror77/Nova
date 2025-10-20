// Phase 7B Feature 2: Private Messaging System
// Service layer modules for messaging functionality

pub mod conversation_service;
pub mod message_service;
pub mod encryption;
pub mod websocket_handler;

pub use conversation_service::ConversationService;
pub use message_service::MessageService;
pub use encryption::{EncryptionService, PublicKey, Nonce};
pub use websocket_handler::MessagingWebSocketHandler;

// Re-export common types
pub use crate::db::messaging::{
    Conversation, ConversationType, ConversationMember, MemberRole, Message, MessageType,
};
