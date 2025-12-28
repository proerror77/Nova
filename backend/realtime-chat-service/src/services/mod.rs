//! # Realtime Chat Services
//!
//! This module contains all business logic services for the chat system.
//!
//! ## Message Encryption Architecture
//!
//! Nova supports a dual-path encryption model based on conversation privacy settings:
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────────┐
//! │                    Message Encryption Paths                         │
//! ├─────────────────────────────────────────────────────────────────────┤
//! │                                                                     │
//! │  encryption_version = 0 (Plaintext + TDE)                          │
//! │  ├── Service: message_service.rs                                   │
//! │  ├── Storage: content field (TEXT)                                 │
//! │  ├── Server can read: YES                                          │
//! │  ├── Searchable: YES (PostgreSQL FTS)                              │
//! │  └── Use case: Search-enabled conversations                        │
//! │                                                                     │
//! │  encryption_version = 1 (Server-side encryption) ⚠️ DEPRECATED     │
//! │  ├── Service: encryption.rs (EncryptionService)                    │
//! │  ├── Status: Legacy, do not use for new messages                   │
//! │  └── Kept for backward compatibility only                          │
//! │                                                                     │
//! │  encryption_version = 2 (Megolm E2EE) ✅ RECOMMENDED FOR E2EE      │
//! │  ├── Services: olm_service.rs + megolm_service.rs                  │
//! │  ├── Storage: megolm_ciphertext, megolm_session_id                 │
//! │  ├── Server can read: NO (true E2EE)                               │
//! │  ├── Searchable: NO                                                │
//! │  ├── Protocol: Matrix Olm/Megolm via vodozemac                     │
//! │  └── Use case: Privacy-first conversations                         │
//! │                                                                     │
//! └─────────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Privacy Mode Routing
//!
//! Conversations have a `privacy_mode` that determines encryption behavior:
//!
//! | Privacy Mode | encryption_version | FTS Search | Key Derivation |
//! |--------------|-------------------|------------|----------------|
//! | `strict_e2e` | 2 (Megolm) | Disabled | Client-side Megolm |
//! | `search_enabled` | 0 (Plaintext) | Enabled | None (TDE only) |
//!
//! **Client Responsibility**: Clients choose which API endpoint to call based on
//! conversation `privacy_mode`. The server enforces search restrictions but does
//! not automatically route between encryption paths.
//!
//! **API Endpoints**:
//! - `/api/v2/messages/*` - Plaintext path (MessageService)
//! - `/api/v2/e2ee/*` - E2EE path (OlmService + MegolmService)
//!
//! ## Service Reference
//!
//! | Service | Status | Purpose |
//! |---------|--------|---------|
//! | `OlmService` | ✅ Active | Device registration, 1:1 key exchange |
//! | `MegolmService` | ✅ Active | Room/group message encryption |
//! | `E2eeMessageService` | ✅ Active | E2EE message storage/retrieval |
//! | `MessageService` | ✅ Active | Plaintext message handling |
//! | `EncryptionService` | ⚠️ Deprecated | Legacy server-side encryption |
//! | `E2eeService` | ⚠️ Deprecated | Legacy ECDH approach |

pub mod call_service;
pub mod conversation_service;
pub mod e2ee;
pub mod e2ee_message_service;
pub mod encryption;
pub mod graph_client;
pub mod identity_client;
pub mod identity_event_consumer;
pub mod key_exchange;
pub mod location_service;
pub mod matrix_admin;
pub mod matrix_client;
pub mod matrix_db;
pub mod matrix_event_handler;
pub mod matrix_voip_service;
pub mod megolm_service;
pub mod message_service;
pub mod offline_queue;
pub mod olm_service;
pub mod relationship_service;

// Re-export key types for convenience
pub use e2ee_message_service::{
    E2eeMessage, E2eeMessageError, E2eeMessageService, SendE2eeMessageRequest,
};
pub use graph_client::GraphClient;
pub use identity_client::IdentityClient;
pub use identity_event_consumer::{IdentityEventConsumer, IdentityEventConsumerConfig};
pub use matrix_admin::MatrixAdminClient;
pub use matrix_voip_service::{IceCandidate, MatrixVoipService};
pub use megolm_service::{MegolmCiphertext, MegolmError, MegolmService, RoomKey};
pub use olm_service::{AccountEncryptionKey, DeviceKeys, OlmError, OlmService};
pub use relationship_service::{
    CanMessageResult, RelationshipService, RelationshipServiceV2, RelationshipStatus,
};
