pub mod auth_client;
pub mod call_service;
pub mod conversation_service;
pub mod e2ee;
pub mod e2ee_message_service;
pub mod encryption;
pub mod graph_client;
pub mod key_exchange;
pub mod location_service;
pub mod megolm_service;
pub mod message_service;
pub mod offline_queue;
pub mod olm_service;
pub mod relationship_service;

// Re-export key types for convenience
pub use olm_service::{OlmService, OlmError, DeviceKeys, AccountEncryptionKey};
pub use megolm_service::{MegolmService, MegolmError, MegolmCiphertext, RoomKey};
pub use e2ee_message_service::{E2eeMessageService, E2eeMessage, E2eeMessageError, SendE2eeMessageRequest};
pub use relationship_service::{RelationshipService, RelationshipServiceV2, CanMessageResult, RelationshipStatus};
pub use graph_client::GraphClient;
