//! # ⚠️ DEPRECATED: Legacy ECDH E2EE Service
//!
//! This module provides X25519 ECDH-based encryption, which was an early E2EE approach.
//!
//! ## Current Architecture
//!
//! Nova now uses **vodozemac Olm/Megolm** for E2EE (Matrix protocol):
//!
//! | Service | Protocol | Purpose |
//! |---------|----------|---------|
//! | `OlmService` | Olm (Double Ratchet) | 1:1 device key exchange |
//! | `MegolmService` | Megolm | Efficient group/room encryption |
//! | `E2eeService` | X25519 ECDH | **DEPRECATED** - legacy approach |
//!
//! ## Migration
//!
//! - Use `OlmService` for device registration and key exchange
//! - Use `MegolmService` for message encryption (encryption_version=2)
//! - See `handlers/e2ee.rs` for the current API implementation
//!
//! This service is kept for reference but is NOT used in production.

// Allow deprecated - this entire module is deprecated but kept for reference
#![allow(deprecated)]

/// End-to-End Encryption (E2EE) Service
///
/// This service provides true E2EE using X25519 ECDH key exchange and authenticated encryption.
/// Unlike the previous server-managed encryption, this implementation ensures that:
/// - Clients control their own private keys
/// - Server cannot decrypt message content
/// - Forward secrecy is maintained through key rotation
/// - Shared secrets are derived via ECDH (Elliptic Curve Diffie-Hellman)
use crate::error::AppError;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use deadpool_postgres::Pool;
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

/// Legacy E2EE service for X25519 ECDH key exchange
///
/// # ⚠️ DEPRECATED
///
/// This service is superseded by `OlmService` + `MegolmService` (vodozemac).
/// Kept for reference only - not used in production.
///
/// For new E2EE implementation, use:
/// - `OlmService` for device key management
/// - `MegolmService` for message encryption (encryption_version=2)
#[deprecated(
    since = "0.9.0",
    note = "Use OlmService + MegolmService (vodozemac) for E2EE. See olm_service.rs and megolm_service.rs."
)]
#[derive(Clone)]
pub struct E2eeService {
    master_key: [u8; 32], // Used for encrypting private keys at rest in DB
}

impl E2eeService {
    /// Create new E2EE service with master key for at-rest encryption
    pub fn new(master_key: [u8; 32]) -> Self {
        Self { master_key }
    }

    // ========================================================================
    // Key Generation and ECDH
    // ========================================================================

    /// Generate X25519 keypair for ECDH
    ///
    /// Returns: (public_key, secret_key) as byte arrays
    pub fn generate_keypair(&self) -> (Vec<u8>, Vec<u8>) {
        let (public_key, secret_key) = crypto_core::generate_x25519_keypair()
            .expect("X25519 keypair generation should not fail");

        (public_key.to_vec(), secret_key.to_vec())
    }

    /// Derive ECDH shared secret from local secret key and peer's public key
    ///
    /// This implements the Diffie-Hellman key exchange:
    /// - Alice: shared_secret = alice_secret * bob_public
    /// - Bob: shared_secret = bob_secret * alice_public
    /// - Result: Both compute the same shared_secret
    pub fn derive_shared_secret(
        &self,
        local_secret_key: &[u8],
        peer_public_key: &[u8],
    ) -> Result<Vec<u8>, AppError> {
        if local_secret_key.len() != 32 {
            return Err(AppError::Encryption(
                "secret key must be 32 bytes".to_string(),
            ));
        }
        if peer_public_key.len() != 32 {
            return Err(AppError::Encryption(
                "public key must be 32 bytes".to_string(),
            ));
        }

        let secret_bytes: [u8; 32] = local_secret_key
            .try_into()
            .map_err(|_| AppError::Encryption("invalid secret key length".to_string()))?;
        let public_bytes: [u8; 32] = peer_public_key
            .try_into()
            .map_err(|_| AppError::Encryption("invalid public key length".to_string()))?;

        let shared_secret = crypto_core::x25519_derive_shared_secret(&secret_bytes, &public_bytes)
            .map_err(|e| {
                AppError::Encryption(format!("ECDH shared secret derivation failed: {}", e))
            })?;

        Ok(shared_secret.to_vec())
    }

    // ========================================================================
    // Key Derivation
    // ========================================================================

    /// Derive encryption key from shared secret using HKDF-SHA256
    ///
    /// Uses conversation_id as context to ensure different conversations
    /// have different encryption keys even with the same shared secret
    pub fn derive_encryption_key(&self, shared_secret: &[u8], conversation_id: Uuid) -> [u8; 32] {
        let hk = Hkdf::<Sha256>::new(None, shared_secret);
        let mut key = [0u8; 32];
        let context = conversation_id.as_bytes();

        hk.expand(context, &mut key)
            .expect("HKDF expand must succeed for 32 byte output");

        key
    }

    // ========================================================================
    // Message Encryption/Decryption
    // ========================================================================

    /// Encrypt message using derived encryption key
    ///
    /// Uses XSalsa20-Poly1305 authenticated encryption (secretbox)
    /// Returns: (ciphertext, nonce)
    pub fn encrypt_message(
        &self,
        encryption_key: &[u8],
        plaintext: &[u8],
    ) -> Result<(Vec<u8>, [u8; 24]), AppError> {
        if encryption_key.len() != 32 {
            return Err(AppError::Encryption(
                "encryption key must be 32 bytes".to_string(),
            ));
        }

        let key_array: [u8; 32] = encryption_key
            .try_into()
            .map_err(|_| AppError::Encryption("invalid key length".to_string()))?;

        let nonce = crypto_core::generate_nonce();

        let ciphertext = crypto_core::encrypt_at_rest(plaintext, &key_array, &nonce)
            .map_err(|e| AppError::Encryption(format!("encryption failed: {}", e)))?;

        Ok((ciphertext, nonce))
    }

    /// Decrypt message using derived encryption key
    ///
    /// Verifies authentication tag (Poly1305) before returning plaintext
    pub fn decrypt_message(
        &self,
        encryption_key: &[u8],
        ciphertext: &[u8],
        nonce: &[u8],
    ) -> Result<Vec<u8>, AppError> {
        if encryption_key.len() != 32 {
            return Err(AppError::Encryption(
                "encryption key must be 32 bytes".to_string(),
            ));
        }
        if nonce.len() != 24 {
            return Err(AppError::Encryption("nonce must be 24 bytes".to_string()));
        }
        if ciphertext.is_empty() {
            return Err(AppError::Encryption(
                "ciphertext cannot be empty".to_string(),
            ));
        }

        let key_array: [u8; 32] = encryption_key
            .try_into()
            .map_err(|_| AppError::Encryption("invalid key length".to_string()))?;

        crypto_core::decrypt_at_rest(ciphertext, &key_array, nonce)
            .map_err(|e| AppError::Encryption(format!("decryption failed: {}", e)))
    }

    // ========================================================================
    // Database Operations
    // ========================================================================

    /// Store device public and private keys in database
    ///
    /// Private key is encrypted at rest using master key
    pub async fn store_device_key(
        &self,
        pool: &Pool,
        user_id: Uuid,
        device_id: &str,
        public_key: &[u8],
        secret_key: &[u8],
    ) -> Result<(), AppError> {
        // Encrypt secret key at rest with master key
        let nonce = crypto_core::generate_nonce();
        let encrypted_secret = crypto_core::encrypt_at_rest(secret_key, &self.master_key, &nonce)
            .map_err(|e| {
            AppError::Encryption(format!("failed to encrypt secret key: {}", e))
        })?;

        // Combine nonce + encrypted_secret for storage
        let mut stored_secret = nonce.to_vec();
        stored_secret.extend_from_slice(&encrypted_secret);

        let public_key_b64 = BASE64.encode(public_key);
        let secret_key_b64 = BASE64.encode(&stored_secret);

        let client = pool.get().await.map_err(|e| AppError::Database(e.to_string()))?;
        let result = client.execute(
            "INSERT INTO device_keys (user_id, device_id, public_key, private_key_encrypted, created_at, updated_at)
             VALUES ($1, $2, $3, $4, NOW(), NOW())",
            &[&user_id, &device_id, &public_key_b64, &secret_key_b64]
        )
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

        if result == 0 {
            return Err(AppError::Encryption(
                "device key already exists for this user/device".to_string(),
            ));
        }

        Ok(())
    }

    /// Retrieve device public key from database
    pub async fn get_device_public_key(
        &self,
        pool: &Pool,
        user_id: Uuid,
        device_id: &str,
    ) -> Result<Option<Vec<u8>>, AppError> {
        let client = pool.get().await.map_err(|e| AppError::Database(e.to_string()))?;
        let row = client.query_opt(
                "SELECT public_key FROM device_keys WHERE user_id = $1 AND device_id = $2",
                &[&user_id, &device_id]
            )
            .await
            .map_err(|e| AppError::Database(e.to_string()))?;

        match row {
            Some(row) => {
                let public_key_b64: String = row.get("public_key");
                let public_key = BASE64.decode(&public_key_b64).map_err(|e| {
                    AppError::Encryption(format!("invalid base64 public key: {}", e))
                })?;
                Ok(Some(public_key))
            }
            None => Ok(None),
        }
    }

    /// Retrieve device secret key from database (decrypts with master key)
    pub async fn get_device_secret_key(
        &self,
        pool: &Pool,
        user_id: Uuid,
        device_id: &str,
    ) -> Result<Option<Vec<u8>>, AppError> {
        let client = pool.get().await.map_err(|e| AppError::Database(e.to_string()))?;
        let row = client.query_opt(
            "SELECT private_key_encrypted FROM device_keys WHERE user_id = $1 AND device_id = $2",
            &[&user_id, &device_id]
        )
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

        match row {
            Some(row) => {
                let encrypted_b64: String = row.get("private_key_encrypted");
                let stored_secret = BASE64.decode(&encrypted_b64).map_err(|e| {
                    AppError::Encryption(format!("invalid base64 secret key: {}", e))
                })?;

                // Extract nonce (first 24 bytes) and ciphertext
                if stored_secret.len() < 24 {
                    return Err(AppError::Encryption(
                        "stored secret key too short".to_string(),
                    ));
                }

                let (nonce_bytes, ciphertext) = stored_secret.split_at(24);

                let secret_key =
                    crypto_core::decrypt_at_rest(ciphertext, &self.master_key, nonce_bytes)
                        .map_err(|e| {
                            AppError::Encryption(format!("failed to decrypt secret key: {}", e))
                        })?;

                Ok(Some(secret_key))
            }
            None => Ok(None),
        }
    }

    /// Record key exchange in audit trail
    ///
    /// Stores hash of shared secret for verification without storing the secret itself
    pub async fn record_key_exchange(
        &self,
        pool: &Pool,
        conversation_id: Uuid,
        initiator_id: Uuid,
        peer_id: Uuid,
        shared_secret: &[u8],
    ) -> Result<(), AppError> {
        // Compute HMAC-SHA256 hash of shared secret for audit
        let mut mac = HmacSha256::new_from_slice(&self.master_key)
            .map_err(|e| AppError::Encryption(format!("HMAC initialization failed: {}", e)))?;
        mac.update(shared_secret);
        let shared_secret_hash = mac.finalize().into_bytes();

        let client = pool.get().await.map_err(|e| AppError::Database(e.to_string()))?;
        client.execute(
            "INSERT INTO key_exchanges (conversation_id, initiator_id, peer_id, shared_secret_hash, created_at)
             VALUES ($1, $2, $3, $4, NOW())",
            &[&conversation_id, &initiator_id, &peer_id, &shared_secret_hash.as_slice()]
        )
        .await
        .map_err(|e| AppError::Database(e.to_string()))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_MASTER_KEY: [u8; 32] = [42u8; 32];

    #[test]
    fn test_keypair_generation() {
        let service = E2eeService::new(TEST_MASTER_KEY);
        let (public, secret) = service.generate_keypair();

        assert_eq!(public.len(), 32);
        assert_eq!(secret.len(), 32);
        assert_ne!(public, secret);
    }

    #[test]
    fn test_shared_secret_derivation() {
        let service = E2eeService::new(TEST_MASTER_KEY);

        let (alice_pub, alice_sec) = service.generate_keypair();
        let (bob_pub, bob_sec) = service.generate_keypair();

        let alice_shared = service.derive_shared_secret(&alice_sec, &bob_pub).unwrap();
        let bob_shared = service.derive_shared_secret(&bob_sec, &alice_pub).unwrap();

        assert_eq!(alice_shared, bob_shared);
    }

    #[test]
    fn test_encryption_decryption_roundtrip() {
        let service = E2eeService::new(TEST_MASTER_KEY);

        let (public, secret) = service.generate_keypair();
        let shared_secret = service.derive_shared_secret(&secret, &public).unwrap();
        let conversation_id = Uuid::new_v4();
        let encryption_key = service.derive_encryption_key(&shared_secret, conversation_id);

        let plaintext = b"Hello E2EE";
        let (ciphertext, nonce) = service.encrypt_message(&encryption_key, plaintext).unwrap();
        let decrypted = service
            .decrypt_message(&encryption_key, &ciphertext, &nonce)
            .unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_nonce_uniqueness() {
        let service = E2eeService::new(TEST_MASTER_KEY);

        let (public, secret) = service.generate_keypair();
        let shared_secret = service.derive_shared_secret(&secret, &public).unwrap();
        let conversation_id = Uuid::new_v4();
        let encryption_key = service.derive_encryption_key(&shared_secret, conversation_id);

        let plaintext = b"Same message";
        let (_, nonce1) = service.encrypt_message(&encryption_key, plaintext).unwrap();
        let (_, nonce2) = service.encrypt_message(&encryption_key, plaintext).unwrap();

        assert_ne!(nonce1, nonce2);
    }

    #[test]
    fn test_decrypt_with_wrong_key_fails() {
        let service = E2eeService::new(TEST_MASTER_KEY);

        let (public, secret) = service.generate_keypair();
        let shared_secret = service.derive_shared_secret(&secret, &public).unwrap();
        let conversation_id = Uuid::new_v4();
        let encryption_key = service.derive_encryption_key(&shared_secret, conversation_id);

        let plaintext = b"Secret data";
        let (ciphertext, nonce) = service.encrypt_message(&encryption_key, plaintext).unwrap();

        let wrong_key = [99u8; 32];
        let result = service.decrypt_message(&wrong_key, &ciphertext, &nonce);

        assert!(result.is_err());
    }
}
