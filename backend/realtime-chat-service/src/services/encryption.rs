//! # ⚠️ DEPRECATED: Server-Side Encryption Service
//!
//! This service implements `encryption_version = 1` (server-managed symmetric encryption).
//!
//! ## Current Architecture
//!
//! Nova now uses a dual-path encryption model:
//!
//! | Version | Description | Service | Server Can Decrypt |
//! |---------|-------------|---------|-------------------|
//! | 0 | Plaintext + PostgreSQL TDE | `message_service.rs` | Yes (TDE at rest) |
//! | 1 | Server-side encryption | `encryption.rs` | Yes (**DEPRECATED**) |
//! | 2 | Megolm E2EE (vodozemac) | `megolm_service.rs` | **No** |
//!
//! ## Migration Path
//!
//! - New messages should use either plaintext (v0) or Megolm E2EE (v2)
//! - This service is kept for backward compatibility with existing v1 messages
//! - Do NOT use this service for new message encryption
//!
//! ## Recommended Alternative
//!
//! Use `MegolmService` for true E2EE where server cannot decrypt content.
//! See `megolm_service.rs` and `e2ee_message_service.rs`.

// Allow deprecated - this entire module is deprecated but kept for backward compatibility
#![allow(deprecated)]

use crate::error::AppError;
use crypto_core::{decrypt_at_rest, encrypt_at_rest, generate_nonce};
use hkdf::Hkdf;
use sha2::Sha256;
use uuid::Uuid;

/// Server-managed symmetric encryption derived from a master key.
///
/// # ⚠️ DEPRECATED
///
/// This corresponds to `encryption_version = 1` which is no longer used for new messages.
/// Kept for backward compatibility with existing encrypted messages.
///
/// For new messages, use:
/// - `encryption_version = 0`: Plaintext with PostgreSQL TDE (searchable)
/// - `encryption_version = 2`: Megolm E2EE via `MegolmService` (true E2EE)
#[deprecated(
    since = "0.9.0",
    note = "Use MegolmService for E2EE or plaintext with TDE. See encryption.rs module docs."
)]
#[derive(Clone)]
pub struct EncryptionService {
    master_key: [u8; 32],
}

impl EncryptionService {
    pub fn new(master_key: [u8; 32]) -> Self {
        Self { master_key }
    }

    pub fn conversation_key(&self, conversation_id: Uuid) -> [u8; 32] {
        self.derive_conversation_key(conversation_id)
    }

    fn derive_conversation_key(&self, conversation_id: Uuid) -> [u8; 32] {
        let hk = Hkdf::<Sha256>::new(None, &self.master_key);
        let mut key = [0u8; 32];
        hk.expand(conversation_id.as_bytes(), &mut key)
            .expect("HKDF expand must succeed for 32 byte output");
        key
    }

    pub fn encrypt(
        &self,
        conversation_id: Uuid,
        plaintext: &[u8],
    ) -> Result<(Vec<u8>, [u8; 24]), AppError> {
        let key = self.derive_conversation_key(conversation_id);
        let nonce = generate_nonce();
        let ciphertext = encrypt_at_rest(plaintext, &key, &nonce)
            .map_err(|e| AppError::Encryption(e.to_string()))?;
        Ok((ciphertext, nonce))
    }

    pub fn decrypt(
        &self,
        conversation_id: Uuid,
        ciphertext: &[u8],
        nonce: &[u8],
    ) -> Result<Vec<u8>, AppError> {
        let key = self.derive_conversation_key(conversation_id);
        decrypt_at_rest(ciphertext, &key, nonce).map_err(|e| AppError::Encryption(e.to_string()))
    }
}
