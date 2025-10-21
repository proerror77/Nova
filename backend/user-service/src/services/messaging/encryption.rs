//! End-to-End Encryption Service for Private Messaging
//!
//! Phase 5 Feature 2: Complete E2E encryption implementation for 1:1 and group conversations
//!
//! ## Architecture
//!
//! 1. **Client-Side Encryption**: All encryption/decryption happens on clients
//! 2. **Server-Side Key Management**: Store and distribute public keys
//! 3. **Transport Security**: HTTPS + Encryption for defense in depth
//! 4. **Forward Secrecy**: Per-message nonces, key rotation support
//!
//! ## Encryption Methods
//!
//! - **1:1 Messages**: NaCl Box (Curve25519 + ChaCha20-Poly1305)
//! - **Group Messages**: Shared key encrypted with NaCl Box per member
//! - **Key Distribution**: Encrypted with recipient's public key

use crate::error::AppError;
use base64::{engine::general_purpose, Engine as _};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Encryption service for managing keys and validating encrypted messages
pub struct EncryptionService;

impl EncryptionService {
    /// Validate a base64-encoded public key (32 bytes)
    pub fn validate_public_key(public_key: &str) -> Result<PublicKey, AppError> {
        let decoded = general_purpose::STANDARD
            .decode(public_key)
            .map_err(|_| AppError::BadRequest("Invalid base64 encoding".to_string()))?;

        if decoded.len() != 32 {
            return Err(AppError::BadRequest(
                "Public key must be 32 bytes".to_string(),
            ));
        }

        Ok(PublicKey(public_key.to_string()))
    }

    /// Validate a base64-encoded nonce (24 bytes)
    pub fn validate_nonce(nonce: &str) -> Result<Nonce, AppError> {
        let decoded = general_purpose::STANDARD
            .decode(nonce)
            .map_err(|_| AppError::BadRequest("Invalid base64 encoding".to_string()))?;

        if decoded.len() != 24 {
            return Err(AppError::BadRequest("Nonce must be 24 bytes".to_string()));
        }

        Ok(Nonce(nonce.to_string()))
    }

    /// Validate encrypted content is valid base64
    pub fn validate_encrypted_content(content: &str) -> Result<(), AppError> {
        general_purpose::STANDARD
            .decode(content)
            .map_err(|_| AppError::BadRequest("Invalid base64 encoding".to_string()))?;
        Ok(())
    }

    /// Verify nonce uniqueness (check if nonce was used before)
    /// In production, use Redis for quick lookups
    pub fn verify_nonce_freshness(nonce: &str, _used_nonces: &[String]) -> Result<(), AppError> {
        // TODO: Implement nonce deduplication check
        // This prevents replay attacks
        Ok(())
    }

    /// Create key exchange request for new conversation
    pub fn create_key_exchange(
        initiator_id: Uuid,
        recipient_id: Uuid,
        initiator_public_key: &str,
    ) -> Result<KeyExchange, AppError> {
        Self::validate_public_key(initiator_public_key)?;

        Ok(KeyExchange {
            id: Uuid::new_v4(),
            initiator_id,
            recipient_id,
            initiator_public_key: initiator_public_key.to_string(),
            status: KeyExchangeStatus::Pending,
            created_at: Utc::now(),
            completed_at: None,
        })
    }

    /// Verify encrypted message integrity
    pub fn verify_message_encryption(
        encrypted_content: &str,
        nonce: &str,
        _sender_public_key: &str,
    ) -> Result<(), AppError> {
        Self::validate_encrypted_content(encrypted_content)?;
        Self::validate_nonce(nonce)?;
        // TODO: Verify authentication tag in encrypted_content
        // For NaCl Box, the auth tag is included in ciphertext
        Ok(())
    }

    /// Complete key exchange when both parties have exchanged keys
    pub fn complete_key_exchange(key_exchange: &mut KeyExchange) -> Result<(), AppError> {
        if key_exchange.status != KeyExchangeStatus::Pending {
            return Err(AppError::BadRequest(
                "Key exchange must be in Pending status to complete".to_string(),
            ));
        }

        key_exchange.status = KeyExchangeStatus::Completed;
        key_exchange.completed_at = Some(Utc::now());
        Ok(())
    }

    /// Mark key exchange as failed (e.g., recipient rejected or timeout)
    pub fn fail_key_exchange(key_exchange: &mut KeyExchange, _reason: &str) -> Result<(), AppError> {
        key_exchange.status = KeyExchangeStatus::Failed;
        key_exchange.completed_at = Some(Utc::now());
        Ok(())
    }

    /// Store user's public key
    pub fn store_public_key(
        user_id: Uuid,
        public_key: &str,
        rotation_interval_days: u32,
    ) -> Result<UserPublicKey, AppError> {
        Self::validate_public_key(public_key)?;

        let now = Utc::now();
        let next_rotation = now + chrono::Duration::days(rotation_interval_days as i64);

        Ok(UserPublicKey {
            user_id,
            public_key: public_key.to_string(),
            registered_at: now,
            last_used_at: None,
            rotation_interval_days,
            next_rotation_at: next_rotation,
        })
    }

    /// Update last_used_at timestamp for a public key
    pub fn update_key_usage(user_public_key: &mut UserPublicKey) {
        user_public_key.last_used_at = Some(Utc::now());
    }

    /// Check if a key needs rotation based on next_rotation_at
    pub fn needs_rotation(user_public_key: &UserPublicKey) -> bool {
        Utc::now() >= user_public_key.next_rotation_at
    }

    /// Calculate next rotation date for a public key
    pub fn calculate_next_rotation(
        current_key: &UserPublicKey,
        new_key: &str,
    ) -> Result<UserPublicKey, AppError> {
        Self::validate_public_key(new_key)?;

        let now = Utc::now();
        let next_rotation = now + chrono::Duration::days(current_key.rotation_interval_days as i64);

        Ok(UserPublicKey {
            user_id: current_key.user_id,
            public_key: new_key.to_string(),
            registered_at: now,
            last_used_at: None,
            rotation_interval_days: current_key.rotation_interval_days,
            next_rotation_at: next_rotation,
        })
    }
}

// ============================================
// Type Wrappers & Data Models
// ============================================

/// Validated public key (32 bytes, base64-encoded)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PublicKey(pub String);

impl PublicKey {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Validated nonce (24 bytes, base64-encoded)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Nonce(pub String);

impl Nonce {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Status of key exchange between users
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum KeyExchangeStatus {
    /// Waiting for recipient to exchange their public key
    #[serde(rename = "pending")]
    Pending,
    /// Both parties have exchanged keys, ready for encrypted communication
    #[serde(rename = "completed")]
    Completed,
    /// Key exchange failed or expired
    #[serde(rename = "failed")]
    Failed,
}

/// Public key exchange for establishing E2E encryption
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyExchange {
    /// Unique identifier for this key exchange
    pub id: Uuid,
    /// User initiating the key exchange
    pub initiator_id: Uuid,
    /// User receiving the key exchange
    pub recipient_id: Uuid,
    /// Initiator's public key (base64-encoded, 32 bytes)
    pub initiator_public_key: String,
    /// Current status of the exchange
    pub status: KeyExchangeStatus,
    /// When the exchange was initiated
    pub created_at: DateTime<Utc>,
    /// When the exchange was completed
    pub completed_at: Option<DateTime<Utc>>,
}

/// Encrypted message container
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedMessage {
    /// Message ID
    pub id: Uuid,
    /// Sender's ID
    pub sender_id: Uuid,
    /// Recipient's ID
    pub recipient_id: Uuid,
    /// Base64-encoded encrypted content
    /// Format: [ciphertext(encrypted plaintext + auth tag)]
    pub encrypted_content: String,
    /// Base64-encoded nonce (24 bytes)
    pub nonce: String,
    /// Sender's public key (for verification)
    pub sender_public_key: String,
    /// Whether message was delivered to recipient
    pub delivered: bool,
    /// Whether recipient read the message
    pub read: bool,
    /// Timestamp when message was sent
    pub created_at: DateTime<Utc>,
}

/// Public key storage record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPublicKey {
    /// User ID
    pub user_id: Uuid,
    /// Public key (base64-encoded, 32 bytes)
    pub public_key: String,
    /// When key was registered
    pub registered_at: DateTime<Utc>,
    /// When key was last used
    pub last_used_at: Option<DateTime<Utc>>,
    /// Key rotation interval (days)
    pub rotation_interval_days: u32,
    /// When key should be rotated
    pub next_rotation_at: DateTime<Utc>,
}

// ============================================
// Client-Side Encryption Guide (Documentation)
// ============================================

/// CLIENT-SIDE ENCRYPTION GUIDE
///
/// This service does NOT perform encryption/decryption. It's done on the client.
///
/// ## 1. Key Generation (iOS/Client)
///
/// ```swift
/// import TweetNacl
///
/// // Generate user identity key pair (once per user)
/// let keyPair = NaclBox.keyPair()
/// let publicKey = keyPair.publicKey.base64EncodedString()  // 32 bytes -> base64
/// let secretKey = keyPair.secretKey  // Store in Keychain, NEVER upload
///
/// // Upload public key to server
/// POST /api/v1/users/me/public-key
/// { "public_key": "<base64-public-key>" }
/// ```
///
/// ## 2. Encrypting a Message (1:1 Conversation)
///
/// ```swift
/// // Get recipient's public key from server
/// let recipientPublicKey = getPublicKey(userId: recipientId)
///
/// // Compute shared secret (Diffie-Hellman)
/// let sharedSecret = NaclBox.before(
///     publicKey: recipientPublicKey,
///     secretKey: mySecretKey
/// )
///
/// // Generate unique nonce
/// let nonce = NaclBox.nonce()  // 24 random bytes
///
/// // Encrypt message
/// let plaintext = "Hello, World!".data(using: .utf8)!
/// let ciphertext = NaclBox.box(
///     message: plaintext,
///     nonce: nonce,
///     sharedSecret: sharedSecret
/// )
///
/// // Send to server
/// POST /api/v1/messages
/// {
///   "conversation_id": "<uuid>",
///   "encrypted_content": "<base64-ciphertext>",
///   "nonce": "<base64-nonce>"
/// }
/// ```
///
/// ## 3. Decrypting a Message
///
/// ```swift
/// // Receive message from server (via WebSocket or HTTP)
/// let ciphertext = Data(base64Encoded: message.encrypted_content)!
/// let nonce = Data(base64Encoded: message.nonce)!
///
/// // Compute shared secret with sender
/// let senderPublicKey = getPublicKey(userId: message.sender_id)
/// let sharedSecret = NaclBox.before(
///     publicKey: senderPublicKey,
///     secretKey: mySecretKey
/// )
///
/// // Decrypt
/// let plaintext = NaclBox.open(
///     ciphertext: ciphertext,
///     nonce: nonce,
///     sharedSecret: sharedSecret
/// )
///
/// let message = String(data: plaintext, encoding: .utf8)!
/// ```
///
/// ## 4. Group Encryption (Shared Secret)
///
/// ```swift
/// // Group creator generates shared key
/// let groupKey = NaclSecretBox.key()  // 32 random bytes
///
/// // Encrypt group key for each member
/// for member in members {
///     let memberPublicKey = getPublicKey(userId: member.id)
///     let nonce = NaclBox.nonce()
///     let encryptedGroupKey = NaclBox.box(
///         message: groupKey,
///         nonce: nonce,
///         publicKey: memberPublicKey,
///         secretKey: mySecretKey
///     )
///
///     // Send encrypted group key to member
///     POST /api/v1/conversations/{id}/keys
///     {
///       "user_id": member.id,
///       "encrypted_key": "<base64-encrypted-group-key>",
///       "nonce": "<base64-nonce>"
///     }
/// }
///
/// // Encrypt message with group key
/// let nonce = NaclSecretBox.nonce()
/// let ciphertext = NaclSecretBox.box(
///     message: plaintext,
///     nonce: nonce,
///     key: groupKey
/// )
/// ```
///
/// ## Security Considerations
///
/// 1. **Private keys NEVER leave the device**: Store in Keychain (iOS) / Keystore (Android)
/// 2. **Nonce must be unique**: Use `crypto_box_random_nonce()`, never reuse
/// 3. **Forward secrecy**: Regenerate group key when members change
/// 4. **No server-side decryption**: Server only routes ciphertext
/// 5. **Lost device = lost messages**: No recovery mechanism (by design)

#[cfg(test)]
mod tests {
    use super::*;

    // ============================================
    // Public Key & Nonce Validation Tests
    // ============================================

    #[test]
    fn test_validate_public_key() {
        // Valid 32-byte key (base64-encoded)
        let valid_key = general_purpose::STANDARD.encode(&[0u8; 32]);
        assert!(EncryptionService::validate_public_key(&valid_key).is_ok());

        // Invalid: too short
        let short_key = general_purpose::STANDARD.encode(&[0u8; 16]);
        assert!(EncryptionService::validate_public_key(&short_key).is_err());

        // Invalid: not base64
        assert!(EncryptionService::validate_public_key("not-base64!!!").is_err());
    }

    #[test]
    fn test_validate_nonce() {
        // Valid 24-byte nonce (base64-encoded)
        let valid_nonce = general_purpose::STANDARD.encode(&[0u8; 24]);
        assert!(EncryptionService::validate_nonce(&valid_nonce).is_ok());

        // Invalid: too short
        let short_nonce = general_purpose::STANDARD.encode(&[0u8; 12]);
        assert!(EncryptionService::validate_nonce(&short_nonce).is_err());
    }

    #[test]
    fn test_validate_encrypted_content() {
        // Valid base64 content
        let valid_content = general_purpose::STANDARD.encode(b"ciphertext data");
        assert!(EncryptionService::validate_encrypted_content(&valid_content).is_ok());

        // Invalid base64
        assert!(EncryptionService::validate_encrypted_content("not-base64!!!").is_err());
    }

    // ============================================
    // Key Exchange Tests
    // ============================================

    #[test]
    fn test_create_key_exchange() {
        let initiator_id = Uuid::new_v4();
        let recipient_id = Uuid::new_v4();
        let public_key = general_purpose::STANDARD.encode(&[1u8; 32]);

        let exchange = EncryptionService::create_key_exchange(
            initiator_id,
            recipient_id,
            &public_key,
        ).unwrap();

        assert_eq!(exchange.initiator_id, initiator_id);
        assert_eq!(exchange.recipient_id, recipient_id);
        assert_eq!(exchange.initiator_public_key, public_key);
        assert_eq!(exchange.status, KeyExchangeStatus::Pending);
        assert!(exchange.completed_at.is_none());
    }

    #[test]
    fn test_create_key_exchange_invalid_key() {
        let initiator_id = Uuid::new_v4();
        let recipient_id = Uuid::new_v4();
        let invalid_key = general_purpose::STANDARD.encode(&[1u8; 16]); // Too short

        let result = EncryptionService::create_key_exchange(
            initiator_id,
            recipient_id,
            &invalid_key,
        );

        assert!(result.is_err());
    }

    #[test]
    fn test_complete_key_exchange() {
        let mut exchange = KeyExchange {
            id: Uuid::new_v4(),
            initiator_id: Uuid::new_v4(),
            recipient_id: Uuid::new_v4(),
            initiator_public_key: general_purpose::STANDARD.encode(&[1u8; 32]),
            status: KeyExchangeStatus::Pending,
            created_at: Utc::now(),
            completed_at: None,
        };

        let result = EncryptionService::complete_key_exchange(&mut exchange);
        assert!(result.is_ok());
        assert_eq!(exchange.status, KeyExchangeStatus::Completed);
        assert!(exchange.completed_at.is_some());
    }

    #[test]
    fn test_complete_key_exchange_already_completed() {
        let mut exchange = KeyExchange {
            id: Uuid::new_v4(),
            initiator_id: Uuid::new_v4(),
            recipient_id: Uuid::new_v4(),
            initiator_public_key: general_purpose::STANDARD.encode(&[1u8; 32]),
            status: KeyExchangeStatus::Completed,
            created_at: Utc::now(),
            completed_at: Some(Utc::now()),
        };

        let result = EncryptionService::complete_key_exchange(&mut exchange);
        assert!(result.is_err());
    }

    #[test]
    fn test_fail_key_exchange() {
        let mut exchange = KeyExchange {
            id: Uuid::new_v4(),
            initiator_id: Uuid::new_v4(),
            recipient_id: Uuid::new_v4(),
            initiator_public_key: general_purpose::STANDARD.encode(&[1u8; 32]),
            status: KeyExchangeStatus::Pending,
            created_at: Utc::now(),
            completed_at: None,
        };

        let result = EncryptionService::fail_key_exchange(&mut exchange, "User rejected");
        assert!(result.is_ok());
        assert_eq!(exchange.status, KeyExchangeStatus::Failed);
        assert!(exchange.completed_at.is_some());
    }

    // ============================================
    // Public Key Storage & Rotation Tests
    // ============================================

    #[test]
    fn test_store_public_key() {
        let user_id = Uuid::new_v4();
        let public_key = general_purpose::STANDARD.encode(&[2u8; 32]);

        let stored_key = EncryptionService::store_public_key(
            user_id,
            &public_key,
            30,
        ).unwrap();

        assert_eq!(stored_key.user_id, user_id);
        assert_eq!(stored_key.public_key, public_key);
        assert_eq!(stored_key.rotation_interval_days, 30);
        assert!(stored_key.last_used_at.is_none());
    }

    #[test]
    fn test_store_public_key_invalid() {
        let user_id = Uuid::new_v4();
        let invalid_key = "not-valid-base64!!!";

        let result = EncryptionService::store_public_key(
            user_id,
            invalid_key,
            30,
        );

        assert!(result.is_err());
    }

    #[test]
    fn test_update_key_usage() {
        let user_id = Uuid::new_v4();
        let public_key = general_purpose::STANDARD.encode(&[3u8; 32]);
        let mut stored_key = EncryptionService::store_public_key(
            user_id,
            &public_key,
            30,
        ).unwrap();

        assert!(stored_key.last_used_at.is_none());
        EncryptionService::update_key_usage(&mut stored_key);
        assert!(stored_key.last_used_at.is_some());
    }

    #[test]
    fn test_needs_rotation_false() {
        let user_id = Uuid::new_v4();
        let public_key = general_purpose::STANDARD.encode(&[4u8; 32]);
        let stored_key = EncryptionService::store_public_key(
            user_id,
            &public_key,
            365,
        ).unwrap();

        // Should not need rotation for a long time
        assert!(!EncryptionService::needs_rotation(&stored_key));
    }

    #[test]
    fn test_needs_rotation_true() {
        let user_id = Uuid::new_v4();
        let public_key = general_purpose::STANDARD.encode(&[5u8; 32]);
        let mut stored_key = EncryptionService::store_public_key(
            user_id,
            &public_key,
            0, // Rotation required immediately
        ).unwrap();

        // Manually set next_rotation to past date
        stored_key.next_rotation_at = Utc::now() - chrono::Duration::days(1);
        assert!(EncryptionService::needs_rotation(&stored_key));
    }

    #[test]
    fn test_calculate_next_rotation() {
        let user_id = Uuid::new_v4();
        let old_key = general_purpose::STANDARD.encode(&[6u8; 32]);
        let new_key = general_purpose::STANDARD.encode(&[7u8; 32]);

        let current_key = EncryptionService::store_public_key(
            user_id,
            &old_key,
            30,
        ).unwrap();

        let rotated_key = EncryptionService::calculate_next_rotation(&current_key, &new_key).unwrap();

        assert_eq!(rotated_key.user_id, user_id);
        assert_eq!(rotated_key.public_key, new_key);
        assert_eq!(rotated_key.rotation_interval_days, 30);
        assert!(rotated_key.last_used_at.is_none());
    }

    // ============================================
    // Message Verification Tests
    // ============================================

    #[test]
    fn test_verify_message_encryption() {
        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[0u8; 24]);
        let sender_key = general_purpose::STANDARD.encode(&[0u8; 32]);

        let result = EncryptionService::verify_message_encryption(
            &encrypted_content,
            &nonce,
            &sender_key,
        );

        assert!(result.is_ok());
    }

    #[test]
    fn test_verify_message_encryption_invalid_nonce() {
        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let invalid_nonce = general_purpose::STANDARD.encode(&[0u8; 12]); // Too short
        let sender_key = general_purpose::STANDARD.encode(&[0u8; 32]);

        let result = EncryptionService::verify_message_encryption(
            &encrypted_content,
            &invalid_nonce,
            &sender_key,
        );

        assert!(result.is_err());
    }
}
