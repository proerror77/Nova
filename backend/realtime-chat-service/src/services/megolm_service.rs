//! Megolm Service - Group End-to-End Encryption using vodozemac
//!
//! Implements the Megolm protocol for efficient group messaging encryption.
//! Uses a symmetric ratchet that only moves forward, providing forward secrecy.
//!
//! # Architecture
//!
//! - **Outbound sessions**: Each device maintains one outbound session per room
//! - **Inbound sessions**: Devices receive and store inbound sessions from each sender
//! - **Session rotation**: Automatic rotation based on message count or age
//! - **Key distribution**: Room keys shared via Olm (1-to-1 encryption)
//!
//! # Security Properties
//!
//! - Forward secrecy through ratcheting
//! - Message authentication via HMAC
//! - Session keys never stored in plaintext
//! - Pickle encryption at rest using AES-256-GCM

// TODO: Upgrade to aes-gcm 0.11 when stable (uses hybrid-array instead of generic-array)
#[allow(deprecated)]
use aes_gcm::{
    aead::{generic_array::GenericArray, Aead, KeyInit},
    Aes256Gcm,
};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use thiserror::Error;
use tracing::{debug, error, info, instrument, warn};
use uuid::Uuid;
use vodozemac::{
    megolm::{
        GroupSession, GroupSessionPickle, InboundGroupSession, InboundGroupSessionPickle,
        SessionConfig, SessionKey,
    },
    Curve25519PublicKey,
};

use crate::error::AppError;

// NOTE: This assumes an OlmService exists with the following interface:
// - OlmService::get_device_keys_for_device(&str) -> DeviceKeys
// - OlmService::encrypt(device_id, identity_key, plaintext) -> OlmCiphertext
// - DeviceKeys { identity_key: Curve25519PublicKey }
//
// If OlmService doesn't exist yet, you'll need to create it or adjust this integration.

#[derive(Debug, Error)]
pub enum MegolmError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Application error: {0}")]
    App(#[from] AppError),

    #[error("Encryption error: {0}")]
    Encryption(String),

    #[error("Decryption error: {0}")]
    Decryption(String),

    #[error("Session not found: room={room_id}, session={session_id}")]
    SessionNotFound { room_id: Uuid, session_id: String },

    #[error("Session needs rotation: message_count={0}, max={1}")]
    SessionNeedsRotation(i32, i32),

    #[error("No outbound session for room {0}")]
    NoOutboundSession(Uuid),

    #[error("Pickle error: {0}")]
    PickleError(String),

    #[error("Invalid session key")]
    InvalidSessionKey,

    #[error("Invalid identity key: {0}")]
    InvalidIdentityKey(String),
}

/// Encrypted message with Megolm
#[derive(Debug, Clone)]
pub struct MegolmCiphertext {
    pub session_id: String,
    pub ciphertext: Vec<u8>,
    pub message_index: u32,
}

/// Room key to be shared with room members
pub struct RoomKey {
    pub room_id: Uuid,
    pub session_id: String,
    pub session_key: SessionKey,
    pub sender_identity_key: Curve25519PublicKey,
}

/// Encryption key wrapper for pickle encryption
#[derive(Clone)]
pub struct AccountEncryptionKey(pub [u8; 32]);

impl AccountEncryptionKey {
    pub fn new(key: [u8; 32]) -> Self {
        Self(key)
    }

    pub fn from_slice(slice: &[u8]) -> Result<Self, MegolmError> {
        if slice.len() != 32 {
            return Err(MegolmError::Encryption(
                "Encryption key must be 32 bytes".to_string(),
            ));
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(slice);
        Ok(Self(key))
    }
}

pub struct MegolmService {
    pool: PgPool,
    encryption_key: Arc<AccountEncryptionKey>,
}

impl MegolmService {
    /// Create a new MegolmService
    ///
    /// # Arguments
    ///
    /// * `pool` - PostgreSQL connection pool
    /// * `encryption_key` - Master key for encrypting pickled sessions at rest
    pub fn new(pool: PgPool, encryption_key: AccountEncryptionKey) -> Self {
        Self {
            pool,
            encryption_key: Arc::new(encryption_key),
        }
    }

    /// Create a new outbound Megolm session for a room
    ///
    /// This creates a new group session that will be used to encrypt messages
    /// sent to the room. The session key must be distributed to all room members
    /// via Olm encryption.
    ///
    /// # Returns
    ///
    /// A `RoomKey` containing the session ID and session key to be distributed
    #[instrument(skip(self))]
    pub async fn create_outbound_session(
        &self,
        room_id: Uuid,
        device_id: &str,
        sender_identity_key: Curve25519PublicKey,
    ) -> Result<RoomKey, MegolmError> {
        // Create new Megolm group session
        let session = GroupSession::new(SessionConfig::default());
        let session_id = session.session_id().to_string();
        let session_key = session.session_key();

        // Pickle and encrypt - vodozemac's pickle() returns bytes directly
        let pickled_bytes = serde_json::to_vec(&session.pickle())
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;
        let (encrypted, nonce) = self.encrypt_pickle(&pickled_bytes)?;

        // Store in database with default rotation settings
        sqlx::query(
            r#"
            INSERT INTO megolm_outbound_sessions
            (room_id, device_id, session_id, pickled_session, pickle_nonce, message_count, max_messages, max_age_seconds, created_at)
            VALUES ($1, $2, $3, $4, $5, 0, 1000, 604800, NOW())
            ON CONFLICT (room_id, device_id) DO UPDATE SET
                session_id = $3,
                pickled_session = $4,
                pickle_nonce = $5,
                message_count = 0,
                created_at = NOW()
            "#,
        )
        .bind(room_id)
        .bind(device_id)
        .bind(&session_id)
        .bind(&encrypted)
        .bind(&nonce)
        .execute(&self.pool)
        .await?;

        info!(
            room_id = %room_id,
            session_id = %session_id,
            device_id = %device_id,
            "Created new Megolm outbound session"
        );

        Ok(RoomKey {
            room_id,
            session_id,
            session_key,
            sender_identity_key,
        })
    }

    /// Encrypt a message for a room using Megolm
    ///
    /// # Returns
    ///
    /// `MegolmCiphertext` containing the encrypted message and metadata
    ///
    /// # Errors
    ///
    /// Returns `SessionNeedsRotation` if the session has exceeded message count or age limits
    #[instrument(skip(self, plaintext))]
    pub async fn encrypt(
        &self,
        room_id: Uuid,
        device_id: &str,
        plaintext: &[u8],
    ) -> Result<MegolmCiphertext, MegolmError> {
        // Check if session needs rotation
        if self.check_session_rotation(room_id, device_id).await? {
            let (count, max) = self.get_session_limits(room_id, device_id).await?;
            return Err(MegolmError::SessionNeedsRotation(count, max));
        }

        // Load session from database
        // Note: GroupSession doesn't implement Clone, so we can't cache it effectively.
        // We could cache the pickled bytes, but for now we reload on each encrypt.
        let mut session = self.load_outbound_session(room_id, device_id).await?;

        // Encrypt
        let message = session.encrypt(plaintext);
        let message_index = session.message_index();
        let session_id = session.session_id().to_string();

        let ciphertext = MegolmCiphertext {
            session_id: session_id.clone(),
            ciphertext: message.to_bytes(),
            message_index,
        };

        // Update session in database
        self.save_outbound_session(room_id, device_id, &session)
            .await?;

        // Increment message count
        sqlx::query(
            r#"
            UPDATE megolm_outbound_sessions
            SET message_count = message_count + 1
            WHERE room_id = $1 AND device_id = $2
            "#,
        )
        .bind(room_id)
        .bind(device_id)
        .execute(&self.pool)
        .await?;

        debug!(
            room_id = %room_id,
            session_id = %session_id,
            message_index = message_index,
            "Encrypted Megolm message"
        );

        Ok(ciphertext)
    }

    /// Import a room key (received via Olm from another device)
    ///
    /// # Arguments
    ///
    /// * `our_device_id` - The device ID of the current device
    /// * `session_key` - The session key received from another device
    /// * `sender_identity_key` - The identity key of the sender device
    #[instrument(skip(self, session_key))]
    pub async fn import_room_key(
        &self,
        room_id: Uuid,
        our_device_id: &str,
        session_id: &str,
        session_key: &SessionKey,
        sender_identity_key: &Curve25519PublicKey,
    ) -> Result<(), MegolmError> {
        // Create inbound session from session key
        let session = InboundGroupSession::new(session_key, SessionConfig::default());
        let first_known_index = session.first_known_index();

        // Pickle and encrypt
        let pickled_bytes = serde_json::to_vec(&session.pickle())
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;
        let (encrypted, nonce) = self.encrypt_pickle(&pickled_bytes)?;

        // Store inbound session
        sqlx::query(
            r#"
            INSERT INTO megolm_inbound_sessions
            (room_id, our_device_id, session_id, sender_identity_key, pickled_session, pickle_nonce, first_known_index, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
            ON CONFLICT (our_device_id, session_id) DO UPDATE SET
                pickled_session = $5,
                pickle_nonce = $6,
                first_known_index = $7
            "#,
        )
        .bind(room_id)
        .bind(our_device_id)
        .bind(session_id)
        .bind(sender_identity_key.to_base64())
        .bind(&encrypted)
        .bind(&nonce)
        .bind(first_known_index as i32)
        .execute(&self.pool)
        .await?;

        info!(
            room_id = %room_id,
            session_id = %session_id,
            our_device_id = %our_device_id,
            "Imported Megolm room key"
        );

        Ok(())
    }

    /// Decrypt a message using Megolm
    ///
    /// # Returns
    ///
    /// The decrypted plaintext
    ///
    /// # Errors
    ///
    /// Returns error if session not found or decryption fails
    #[instrument(skip(self, ciphertext))]
    pub async fn decrypt(
        &self,
        room_id: Uuid,
        our_device_id: &str,
        ciphertext: &MegolmCiphertext,
    ) -> Result<Vec<u8>, MegolmError> {
        // Load inbound session
        let mut session = self
            .load_inbound_session(our_device_id, &ciphertext.session_id)
            .await?;

        // Parse ciphertext
        let message = vodozemac::megolm::MegolmMessage::from_bytes(&ciphertext.ciphertext)
            .map_err(|e| MegolmError::Decryption(e.to_string()))?;

        // Decrypt
        let result = session
            .decrypt(&message)
            .map_err(|e| MegolmError::Decryption(e.to_string()))?;

        // Save updated session (ratchet state has advanced)
        self.save_inbound_session(our_device_id, &ciphertext.session_id, &session)
            .await?;

        debug!(
            room_id = %room_id,
            session_id = %ciphertext.session_id,
            message_index = %ciphertext.message_index,
            "Decrypted Megolm message"
        );

        Ok(result.plaintext)
    }

    /// Share room key with new room members
    ///
    /// This would typically use Olm encryption to send the room key to each device.
    /// Since OlmService is not yet implemented, this is a placeholder that queues
    /// to-device messages.
    ///
    /// # Implementation Note
    ///
    /// When OlmService is available, replace the queue_to_device_message calls with
    /// actual Olm encryption.
    #[instrument(skip(self))]
    pub async fn share_room_key(
        &self,
        room_id: Uuid,
        our_device_id: &str,
        sender_identity_key: Curve25519PublicKey,
        target_device_ids: &[String],
    ) -> Result<(), MegolmError> {
        // Get the current outbound session
        let row = sqlx::query(
            r#"
            SELECT session_id, pickled_session, pickle_nonce
            FROM megolm_outbound_sessions
            WHERE room_id = $1 AND device_id = $2
            "#,
        )
        .bind(room_id)
        .bind(our_device_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| MegolmError::NoOutboundSession(room_id))?;

        // Get session key from outbound session
        let session_id: String = row.get("session_id");
        let pickled_session: Vec<u8> = row.get("pickled_session");
        let pickle_nonce: Vec<u8> = row.get("pickle_nonce");

        let decrypted = self.decrypt_pickle(&pickled_session, &pickle_nonce)?;
        let pickle: GroupSessionPickle = serde_json::from_slice(&decrypted)
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;
        let session = GroupSession::from_pickle(pickle);
        let session_key = session.session_key();

        // Create room key message
        let room_key_content = serde_json::json!({
            "type": "m.room_key",
            "room_id": room_id.to_string(),
            "session_id": session_id,
            "session_key": session_key.to_base64(),
            "algorithm": "m.megolm.v1.aes-sha2"
        });

        // Send to each target device
        // TODO: Use OlmService to encrypt these messages when available
        for target_device_id in target_device_ids {
            self.queue_to_device_message(
                our_device_id,
                target_device_id,
                "m.room_key",
                room_key_content.to_string().as_bytes(),
            )
            .await?;

            debug!(
                target = %target_device_id,
                session_id = %session_id,
                "Queued room key for device"
            );
        }

        info!(
            room_id = %room_id,
            count = target_device_ids.len(),
            "Shared room keys with devices"
        );

        Ok(())
    }

    // ========================================================================
    // Internal Helper Methods
    // ========================================================================

    /// Check if session needs rotation (message count or age)
    async fn check_session_rotation(
        &self,
        room_id: Uuid,
        device_id: &str,
    ) -> Result<bool, MegolmError> {
        let row = sqlx::query(
            r#"
            SELECT message_count, max_messages, created_at, max_age_seconds
            FROM megolm_outbound_sessions
            WHERE room_id = $1 AND device_id = $2
            "#,
        )
        .bind(room_id)
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = row {
            // Check message count
            let message_count: i32 = row.get("message_count");
            let max_messages: i32 = row.get("max_messages");
            if message_count >= max_messages {
                return Ok(true);
            }

            // Check age
            let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
            let max_age_seconds: i32 = row.get("max_age_seconds");
            let age = chrono::Utc::now().signed_duration_since(created_at);
            if age.num_seconds() > max_age_seconds as i64 {
                return Ok(true);
            }
        }

        Ok(false)
    }

    /// Get session rotation limits
    async fn get_session_limits(
        &self,
        room_id: Uuid,
        device_id: &str,
    ) -> Result<(i32, i32), MegolmError> {
        let row = sqlx::query(
            r#"
            SELECT message_count, max_messages
            FROM megolm_outbound_sessions
            WHERE room_id = $1 AND device_id = $2
            "#,
        )
        .bind(room_id)
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?;

        match row {
            Some(row) => {
                let message_count: i32 = row.get("message_count");
                let max_messages: i32 = row.get("max_messages");
                Ok((message_count, max_messages))
            }
            None => Ok((0, 1000)), // defaults
        }
    }

    async fn load_outbound_session(
        &self,
        room_id: Uuid,
        device_id: &str,
    ) -> Result<GroupSession, MegolmError> {
        let row = sqlx::query(
            r#"
            SELECT pickled_session, pickle_nonce
            FROM megolm_outbound_sessions
            WHERE room_id = $1 AND device_id = $2
            "#,
        )
        .bind(room_id)
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| MegolmError::NoOutboundSession(room_id))?;

        let pickled_session: Vec<u8> = row.get("pickled_session");
        let pickle_nonce: Vec<u8> = row.get("pickle_nonce");

        let decrypted = self.decrypt_pickle(&pickled_session, &pickle_nonce)?;
        let pickle: GroupSessionPickle = serde_json::from_slice(&decrypted)
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;

        Ok(GroupSession::from_pickle(pickle))
    }

    async fn save_outbound_session(
        &self,
        room_id: Uuid,
        device_id: &str,
        session: &GroupSession,
    ) -> Result<(), MegolmError> {
        let pickled_bytes = serde_json::to_vec(&session.pickle())
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;
        let (encrypted, nonce) = self.encrypt_pickle(&pickled_bytes)?;

        sqlx::query(
            r#"
            UPDATE megolm_outbound_sessions
            SET pickled_session = $1, pickle_nonce = $2
            WHERE room_id = $3 AND device_id = $4
            "#,
        )
        .bind(&encrypted)
        .bind(&nonce)
        .bind(room_id)
        .bind(device_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    async fn load_inbound_session(
        &self,
        our_device_id: &str,
        session_id: &str,
    ) -> Result<InboundGroupSession, MegolmError> {
        let row = sqlx::query(
            r#"
            SELECT room_id, pickled_session, pickle_nonce
            FROM megolm_inbound_sessions
            WHERE our_device_id = $1 AND session_id = $2
            "#,
        )
        .bind(our_device_id)
        .bind(session_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| MegolmError::SessionNotFound {
            room_id: Uuid::nil(),
            session_id: session_id.to_string(),
        })?;

        let pickled_session: Vec<u8> = row.get("pickled_session");
        let pickle_nonce: Vec<u8> = row.get("pickle_nonce");

        let decrypted = self.decrypt_pickle(&pickled_session, &pickle_nonce)?;
        let pickle: InboundGroupSessionPickle = serde_json::from_slice(&decrypted)
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;

        Ok(InboundGroupSession::from_pickle(pickle))
    }

    async fn save_inbound_session(
        &self,
        our_device_id: &str,
        session_id: &str,
        session: &InboundGroupSession,
    ) -> Result<(), MegolmError> {
        let pickled_bytes = serde_json::to_vec(&session.pickle())
            .map_err(|e| MegolmError::PickleError(e.to_string()))?;
        let (encrypted, nonce) = self.encrypt_pickle(&pickled_bytes)?;

        sqlx::query(
            r#"
            UPDATE megolm_inbound_sessions
            SET pickled_session = $1, pickle_nonce = $2
            WHERE our_device_id = $3 AND session_id = $4
            "#,
        )
        .bind(&encrypted)
        .bind(&nonce)
        .bind(our_device_id)
        .bind(session_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Queue a to-device message
    ///
    /// This is a placeholder implementation. When WebSocket or push notification
    /// delivery is implemented, this should route through that system.
    async fn queue_to_device_message(
        &self,
        sender_device_id: &str,
        recipient_device_id: &str,
        message_type: &str,
        content: &[u8],
    ) -> Result<(), MegolmError> {
        // Get user IDs from device IDs
        let sender = sqlx::query("SELECT user_id FROM user_devices WHERE device_id = $1")
            .bind(sender_device_id)
            .fetch_optional(&self.pool)
            .await?;

        let recipient = sqlx::query("SELECT user_id FROM user_devices WHERE device_id = $1")
            .bind(recipient_device_id)
            .fetch_optional(&self.pool)
            .await?;

        // If device not found, log warning but don't fail
        let (sender_user_id, recipient_user_id) = match (sender, recipient) {
            (Some(s), Some(r)) => {
                let sender_user_id: Uuid = s.get("user_id");
                let recipient_user_id: Uuid = r.get("user_id");
                (sender_user_id, recipient_user_id)
            }
            _ => {
                warn!(
                    sender_device = %sender_device_id,
                    recipient_device = %recipient_device_id,
                    "Device not found, skipping to-device message"
                );
                return Ok(());
            }
        };

        sqlx::query(
            r#"
            INSERT INTO to_device_messages
            (sender_user_id, sender_device_id, recipient_user_id, recipient_device_id, message_type, content, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            "#,
        )
        .bind(sender_user_id)
        .bind(sender_device_id)
        .bind(recipient_user_id)
        .bind(recipient_device_id)
        .bind(message_type)
        .bind(content)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Encrypt a pickle using AES-256-GCM
    #[allow(deprecated)]
    fn encrypt_pickle(&self, data: &[u8]) -> Result<(Vec<u8>, Vec<u8>), MegolmError> {
        let cipher = Aes256Gcm::new_from_slice(&self.encryption_key.0)
            .map_err(|e| MegolmError::Encryption(e.to_string()))?;

        let mut nonce_bytes = [0u8; 12];
        getrandom::getrandom(&mut nonce_bytes)
            .map_err(|e| MegolmError::Encryption(e.to_string()))?;
        let nonce = GenericArray::from_slice(&nonce_bytes);

        let ciphertext = cipher
            .encrypt(nonce, data)
            .map_err(|e| MegolmError::Encryption(e.to_string()))?;

        Ok((ciphertext, nonce_bytes.to_vec()))
    }

    /// Decrypt a pickle using AES-256-GCM
    #[allow(deprecated)]
    fn decrypt_pickle(&self, ciphertext: &[u8], nonce: &[u8]) -> Result<Vec<u8>, MegolmError> {
        let cipher = Aes256Gcm::new_from_slice(&self.encryption_key.0)
            .map_err(|e| MegolmError::Decryption(e.to_string()))?;

        let nonce_array: [u8; 12] = nonce
            .try_into()
            .map_err(|_| MegolmError::Decryption("Invalid nonce length".to_string()))?;
        let nonce = GenericArray::from_slice(&nonce_array);

        cipher
            .decrypt(nonce, ciphertext)
            .map_err(|e| MegolmError::Decryption(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Add integration tests with test database
    // Test scenarios:
    // 1. Create outbound session
    // 2. Encrypt/decrypt message roundtrip
    // 3. Import room key and decrypt
    // 4. Session rotation on message count
    // 5. Session rotation on age
    // 6. Multiple inbound sessions from different senders
    // 7. Pickle encryption/decryption
    // 8. Cache functionality
}
