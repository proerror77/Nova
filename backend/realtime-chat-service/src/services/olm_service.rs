//! Olm Service - 1:1 End-to-End Encryption using vodozemac
//!
//! Implements the Olm protocol (Double Ratchet) for secure 1:1 messaging
//! between devices.
//!
//! # Security Architecture
//!
//! - **Account Storage**: Olm accounts are pickled and encrypted at rest using AES-256-GCM
//! - **Session Management**: Each device-to-device pair has a unique session
//! - **Key Rotation**: One-time keys enable forward secrecy
//! - **No Plaintext**: All sensitive crypto state is encrypted before database storage
//!
//! # Dependencies Required
//!
//! Add to Cargo.toml:
//! ```toml
//! [dependencies]
//! aes-gcm = "0.10"
//! getrandom = "0.2"
//! hex = "0.4"
//! vodozemac = "0.7"
//! zeroize = "1.7"
//! serde_json = "1.0"
//! ```

// TODO: Upgrade to aes-gcm 0.11 when stable (uses hybrid-array instead of generic-array)
#[allow(deprecated)]
use aes_gcm::{
    aead::{generic_array::GenericArray, Aead, KeyInit},
    Aes256Gcm,
};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use thiserror::Error;
use tracing::{debug, info, instrument};
use uuid::Uuid;
use vodozemac::{
    olm::{Account, AccountPickle, OlmMessage, Session, SessionConfig, SessionPickle},
    Curve25519PublicKey, Ed25519PublicKey,
};
use zeroize::Zeroize;

#[derive(Debug, Error)]
pub enum OlmError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Encryption error: {0}")]
    Encryption(String),

    #[error("Decryption error: {0}")]
    Decryption(String),

    #[error("No one-time key available for device {0}")]
    NoOneTimeKey(String),

    #[error("Session not found for device {0}")]
    SessionNotFound(String),

    #[error("Account not found for device {0}")]
    AccountNotFound(String),

    #[error("Invalid key format: {0}")]
    InvalidKey(String),

    #[error("Pickle error: {0}")]
    PickleError(String),
}

/// Key for encrypting pickled crypto state at rest
///
/// SECURITY: This key MUST be:
/// - Generated using a CSPRNG
/// - Stored in a secure key management system (AWS KMS, HashiCorp Vault)
/// - Rotated periodically
/// - Never logged or committed to version control
pub struct AccountEncryptionKey(pub [u8; 32]);

impl AccountEncryptionKey {
    /// Load encryption key from environment variable
    ///
    /// Environment variable format: `OLM_ACCOUNT_KEY=<64-char hex string>`
    ///
    /// # Example
    /// ```bash
    /// export OLM_ACCOUNT_KEY=$(openssl rand -hex 32)
    /// ```
    pub fn from_env() -> Result<Self, OlmError> {
        let key_hex = std::env::var("OLM_ACCOUNT_KEY")
            .map_err(|_| OlmError::Encryption("OLM_ACCOUNT_KEY not set".into()))?;

        let key_bytes = hex::decode(&key_hex)
            .map_err(|e| OlmError::Encryption(format!("Invalid hex key: {}", e)))?;

        if key_bytes.len() != 32 {
            return Err(OlmError::Encryption(
                "Key must be 32 bytes (64 hex chars)".into(),
            ));
        }

        let mut key = [0u8; 32];
        key.copy_from_slice(&key_bytes);
        Ok(Self(key))
    }

    /// Create from raw bytes (for testing or key rotation)
    #[cfg(test)]
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
}

impl Drop for AccountEncryptionKey {
    fn drop(&mut self) {
        // Zero out key material on drop
        self.0.zeroize();
    }
}

/// Device identity information
///
/// Contains the public keys that identify a device in the E2EE system
#[derive(Debug, Clone)]
pub struct DeviceKeys {
    pub device_id: String,
    pub identity_key: Curve25519PublicKey,
    pub signing_key: Ed25519PublicKey,
}

/// Olm service for managing 1:1 E2EE sessions
///
/// This service handles:
/// - Device account creation and storage
/// - One-time key generation and claiming
/// - Session establishment (inbound/outbound)
/// - Message encryption/decryption
pub struct OlmService {
    pool: PgPool,
    encryption_key: Arc<AccountEncryptionKey>,
}

impl OlmService {
    pub fn new(pool: PgPool, encryption_key: AccountEncryptionKey) -> Self {
        Self {
            pool,
            encryption_key: Arc::new(encryption_key),
        }
    }

    /// Create a new Olm account for a device
    ///
    /// This should be called when a user logs in on a new device or
    /// when their existing device needs to regenerate keys.
    ///
    /// # Arguments
    /// * `user_id` - The user owning this device
    /// * `device_id` - Unique identifier for the device
    /// * `device_name` - Human-readable name (e.g., "iPhone 14 Pro")
    ///
    /// # Returns
    /// The public identity keys for this device, which should be uploaded
    /// to the identity service for key distribution
    #[instrument(skip(self))]
    pub async fn create_account(
        &self,
        user_id: Uuid,
        device_id: &str,
        device_name: Option<&str>,
    ) -> Result<DeviceKeys, OlmError> {
        // Generate new Olm account
        let account = Account::new();

        // Get identity keys
        let identity_key = account.curve25519_key();
        let signing_key = account.ed25519_key();

        // Pickle and encrypt the account using serde_json serialization
        let pickled = account.pickle();
        let pickle_bytes = serde_json::to_vec(&pickled)
            .map_err(|e| OlmError::PickleError(format!("Failed to serialize pickle: {}", e)))?;
        let (encrypted_pickle, nonce) = self.encrypt_pickle(&pickle_bytes)?;

        // Store device and account in transaction
        let mut tx = self.pool.begin().await?;

        // Insert device
        sqlx::query(
            r#"
            INSERT INTO user_devices (user_id, device_id, device_name, identity_key, signing_key)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (device_id) DO UPDATE SET
                last_seen_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(device_id)
        .bind(device_name)
        .bind(identity_key.to_base64())
        .bind(signing_key.to_base64())
        .execute(&mut *tx)
        .await?;

        // Insert Olm account
        sqlx::query(
            r#"
            INSERT INTO olm_accounts (device_id, pickled_account, pickle_nonce)
            VALUES ($1, $2, $3)
            ON CONFLICT (device_id) DO UPDATE SET
                pickled_account = $2,
                pickle_nonce = $3,
                updated_at = NOW()
            "#,
        )
        .bind(device_id)
        .bind(&encrypted_pickle)
        .bind(&nonce)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        info!(
            device_id = %device_id,
            user_id = %user_id,
            "Created new Olm account"
        );

        Ok(DeviceKeys {
            device_id: device_id.to_string(),
            identity_key,
            signing_key,
        })
    }

    /// Generate and upload one-time keys
    ///
    /// One-time keys are used to establish new Olm sessions. Each key
    /// can only be used once, providing forward secrecy.
    ///
    /// # Best Practices
    /// - Generate 50-100 keys per device
    /// - Monitor key usage and regenerate when < 10 remain
    /// - Keys should be rotated regularly (e.g., weekly)
    ///
    /// # Arguments
    /// * `device_id` - Device to generate keys for
    /// * `count` - Number of keys to generate
    #[instrument(skip(self))]
    pub async fn generate_one_time_keys(
        &self,
        device_id: &str,
        count: usize,
    ) -> Result<usize, OlmError> {
        // Load account
        let mut account = self.load_account(device_id).await?;

        // Generate new one-time keys
        account.generate_one_time_keys(count);
        let otks = account.one_time_keys();

        let mut tx = self.pool.begin().await?;

        // Store each one-time key
        let mut stored_count = 0;
        for (key_id, public_key) in otks.iter() {
            let result = sqlx::query(
                r#"
                INSERT INTO olm_one_time_keys (device_id, key_id, public_key)
                VALUES ($1, $2, $3)
                ON CONFLICT (device_id, key_id) DO NOTHING
                RETURNING id
                "#,
            )
            .bind(device_id)
            .bind(key_id.to_base64())
            .bind(public_key.to_base64())
            .fetch_optional(&mut *tx)
            .await?;

            if result.is_some() {
                stored_count += 1;
            }
        }

        // Mark keys as published
        account.mark_keys_as_published();

        // Save updated account
        self.save_account(device_id, &account, &mut tx).await?;

        // Update uploaded count
        sqlx::query(
            r#"
            UPDATE olm_accounts
            SET uploaded_otk_count = uploaded_otk_count + $1, updated_at = NOW()
            WHERE device_id = $2
            "#,
        )
        .bind(stored_count as i32)
        .bind(device_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;

        debug!(
            device_id = %device_id,
            requested = count,
            stored = stored_count,
            "Generated one-time keys"
        );

        Ok(stored_count)
    }

    /// Claim a one-time key from a device (for establishing session)
    ///
    /// This is called by the initiator of a conversation to get a one-time
    /// key from the recipient's device. The key is marked as claimed to
    /// prevent reuse.
    ///
    /// # Arguments
    /// * `target_device_id` - Device to claim key from
    /// * `claimer_device_id` - Device claiming the key (for audit trail)
    ///
    /// # Returns
    /// Tuple of (key_id, public_key) that can be used to create outbound session
    #[instrument(skip(self))]
    pub async fn claim_one_time_key(
        &self,
        target_device_id: &str,
        claimer_device_id: &str,
    ) -> Result<(String, Curve25519PublicKey), OlmError> {
        let row = sqlx::query(
            r#"
            UPDATE olm_one_time_keys
            SET claimed = true, claimed_by_device_id = $1, claimed_at = NOW()
            WHERE id = (
                SELECT id FROM olm_one_time_keys
                WHERE device_id = $2 AND NOT claimed
                ORDER BY created_at ASC
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            )
            RETURNING key_id, public_key
            "#,
        )
        .bind(claimer_device_id)
        .bind(target_device_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| OlmError::NoOneTimeKey(target_device_id.to_string()))?;

        let key_id: String = row.get("key_id");
        let public_key_b64: String = row.get("public_key");

        let public_key = Curve25519PublicKey::from_base64(&public_key_b64)
            .map_err(|e| OlmError::InvalidKey(e.to_string()))?;

        debug!(
            target = %target_device_id,
            claimer = %claimer_device_id,
            key_id = %key_id,
            "Claimed one-time key"
        );

        Ok((key_id, public_key))
    }

    /// Create outbound Olm session (when initiating conversation)
    ///
    /// Call this when starting a new conversation with a device.
    /// The first message MUST be a PreKey message that includes
    /// the one-time key.
    ///
    /// # Flow
    /// 1. Call `claim_one_time_key` to get recipient's OTK
    /// 2. Call this method to create session
    /// 3. Use `encrypt` to create PreKey message
    /// 4. Send PreKey message to recipient
    #[instrument(skip(self))]
    pub async fn create_outbound_session(
        &self,
        our_device_id: &str,
        their_identity_key: &Curve25519PublicKey,
        their_one_time_key: &Curve25519PublicKey,
    ) -> Result<Session, OlmError> {
        let account = self.load_account(our_device_id).await?;

        let session = account.create_outbound_session(
            SessionConfig::default(),
            *their_identity_key,
            *their_one_time_key,
        );

        // Save session
        self.save_session(our_device_id, their_identity_key, &session)
            .await?;

        info!(
            our_device = %our_device_id,
            their_identity = %their_identity_key.to_base64(),
            "Created outbound Olm session"
        );

        Ok(session)
    }

    /// Create inbound Olm session (when receiving first message)
    ///
    /// Call this when receiving a PreKey message from a device
    /// you haven't communicated with before.
    ///
    /// # Returns
    /// Tuple of (session, decrypted_plaintext)
    #[instrument(skip(self, message))]
    pub async fn create_inbound_session(
        &self,
        our_device_id: &str,
        their_identity_key: &Curve25519PublicKey,
        message: &OlmMessage,
    ) -> Result<(Session, Vec<u8>), OlmError> {
        let mut account = self.load_account(our_device_id).await?;

        let result = match message {
            OlmMessage::PreKey(pre_key_message) => account
                .create_inbound_session(*their_identity_key, pre_key_message)
                .map_err(|e| OlmError::Decryption(e.to_string()))?,
            OlmMessage::Normal(_) => {
                return Err(OlmError::Decryption(
                    "Expected PreKey message for new session".into(),
                ));
            }
        };

        // Save updated account (one-time key removed)
        let mut tx = self.pool.begin().await?;
        self.save_account(our_device_id, &account, &mut tx).await?;
        tx.commit().await?;

        // Save new session
        self.save_session(our_device_id, their_identity_key, &result.session)
            .await?;

        info!(
            our_device = %our_device_id,
            their_identity = %their_identity_key.to_base64(),
            "Created inbound Olm session"
        );

        Ok((result.session, result.plaintext))
    }

    /// Encrypt a message using Olm
    ///
    /// # Arguments
    /// * `our_device_id` - Our device sending the message
    /// * `their_identity_key` - Recipient device identity key
    /// * `plaintext` - Message to encrypt
    ///
    /// # Returns
    /// OlmMessage (PreKey for first message, Normal for subsequent)
    #[instrument(skip(self, plaintext), fields(plaintext_len = plaintext.len()))]
    pub async fn encrypt(
        &self,
        our_device_id: &str,
        their_identity_key: &Curve25519PublicKey,
        plaintext: &[u8],
    ) -> Result<OlmMessage, OlmError> {
        let mut session = self.load_session(our_device_id, their_identity_key).await?;

        let message = session.encrypt(plaintext);

        // Save updated session (ratchet advanced)
        self.save_session(our_device_id, their_identity_key, &session)
            .await?;

        debug!(
            our_device = %our_device_id,
            their_identity = %their_identity_key.to_base64(),
            message_type = ?message,
            "Encrypted Olm message"
        );

        Ok(message)
    }

    /// Decrypt a message using Olm
    ///
    /// # Arguments
    /// * `our_device_id` - Our device receiving the message
    /// * `their_identity_key` - Sender device identity key
    /// * `message` - OlmMessage to decrypt
    ///
    /// # Returns
    /// Decrypted plaintext bytes
    #[instrument(skip(self, message))]
    pub async fn decrypt(
        &self,
        our_device_id: &str,
        their_identity_key: &Curve25519PublicKey,
        message: &OlmMessage,
    ) -> Result<Vec<u8>, OlmError> {
        let mut session = self.load_session(our_device_id, their_identity_key).await?;

        let plaintext = session
            .decrypt(message)
            .map_err(|e| OlmError::Decryption(e.to_string()))?;

        // Save updated session (ratchet advanced)
        self.save_session(our_device_id, their_identity_key, &session)
            .await?;

        debug!(
            our_device = %our_device_id,
            their_identity = %their_identity_key.to_base64(),
            plaintext_len = plaintext.len(),
            "Decrypted Olm message"
        );

        Ok(plaintext)
    }

    /// Get device keys for a user
    ///
    /// Used for key distribution - returns all devices and their
    /// public identity keys for a given user.
    pub async fn get_device_keys(&self, user_id: Uuid) -> Result<Vec<DeviceKeys>, OlmError> {
        let rows = sqlx::query(
            r#"
            SELECT device_id, identity_key, signing_key
            FROM user_devices
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        let mut keys = Vec::new();
        for row in rows {
            let device_id: String = row.get("device_id");
            let identity_key_b64: String = row.get("identity_key");
            let signing_key_b64: String = row.get("signing_key");

            let identity_key = Curve25519PublicKey::from_base64(&identity_key_b64)
                .map_err(|e| OlmError::InvalidKey(e.to_string()))?;
            let signing_key = Ed25519PublicKey::from_base64(&signing_key_b64)
                .map_err(|e| OlmError::InvalidKey(e.to_string()))?;

            keys.push(DeviceKeys {
                device_id,
                identity_key,
                signing_key,
            });
        }

        Ok(keys)
    }

    /// Get one-time key count for a device
    ///
    /// Used to monitor when new keys need to be generated
    pub async fn get_one_time_key_count(&self, device_id: &str) -> Result<i64, OlmError> {
        let row = sqlx::query(
            r#"
            SELECT COUNT(*) as count FROM olm_one_time_keys
            WHERE device_id = $1 AND NOT claimed
            "#,
        )
        .bind(device_id)
        .fetch_one(&self.pool)
        .await?;

        let count: i64 = row.get("count");
        Ok(count)
    }

    // ========================================================================
    // Internal helper methods
    // ========================================================================

    /// Load and decrypt Olm account from database
    async fn load_account(&self, device_id: &str) -> Result<Account, OlmError> {
        let row = sqlx::query(
            r#"
            SELECT pickled_account, pickle_nonce
            FROM olm_accounts
            WHERE device_id = $1
            "#,
        )
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| OlmError::AccountNotFound(device_id.to_string()))?;

        let pickled_account: Vec<u8> = row.get("pickled_account");
        let pickle_nonce: Vec<u8> = row.get("pickle_nonce");

        let decrypted = self.decrypt_pickle(&pickled_account, &pickle_nonce)?;
        let pickle: AccountPickle = serde_json::from_slice(&decrypted)
            .map_err(|e| OlmError::PickleError(format!("Failed to deserialize pickle: {}", e)))?;

        Ok(Account::from_pickle(pickle))
    }

    /// Pickle, encrypt, and save Olm account to database
    async fn save_account(
        &self,
        device_id: &str,
        account: &Account,
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    ) -> Result<(), OlmError> {
        let pickled = account.pickle();
        let pickle_bytes = serde_json::to_vec(&pickled)
            .map_err(|e| OlmError::PickleError(format!("Failed to serialize pickle: {}", e)))?;
        let (encrypted, nonce) = self.encrypt_pickle(&pickle_bytes)?;

        sqlx::query(
            r#"
            UPDATE olm_accounts
            SET pickled_account = $1, pickle_nonce = $2, updated_at = NOW()
            WHERE device_id = $3
            "#,
        )
        .bind(&encrypted)
        .bind(&nonce)
        .bind(device_id)
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    /// Load and decrypt Olm session from database
    async fn load_session(
        &self,
        our_device_id: &str,
        their_identity_key: &Curve25519PublicKey,
    ) -> Result<Session, OlmError> {
        let their_key_b64 = their_identity_key.to_base64();

        let row = sqlx::query(
            r#"
            SELECT pickled_session, pickle_nonce
            FROM olm_sessions
            WHERE our_device_id = $1 AND their_identity_key = $2
            "#,
        )
        .bind(our_device_id)
        .bind(&their_key_b64)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| OlmError::SessionNotFound(their_key_b64.clone()))?;

        let pickled_session: Vec<u8> = row.get("pickled_session");
        let pickle_nonce: Vec<u8> = row.get("pickle_nonce");

        let decrypted = self.decrypt_pickle(&pickled_session, &pickle_nonce)?;
        let pickle: SessionPickle = serde_json::from_slice(&decrypted).map_err(|e| {
            OlmError::PickleError(format!("Failed to deserialize session pickle: {}", e))
        })?;

        Ok(Session::from_pickle(pickle))
    }

    /// Pickle, encrypt, and save Olm session to database
    async fn save_session(
        &self,
        our_device_id: &str,
        their_identity_key: &Curve25519PublicKey,
        session: &Session,
    ) -> Result<(), OlmError> {
        let pickled = session.pickle();
        let pickle_bytes = serde_json::to_vec(&pickled).map_err(|e| {
            OlmError::PickleError(format!("Failed to serialize session pickle: {}", e))
        })?;
        let (encrypted, nonce) = self.encrypt_pickle(&pickle_bytes)?;
        let their_key_b64 = their_identity_key.to_base64();

        sqlx::query(
            r#"
            INSERT INTO olm_sessions (our_device_id, their_identity_key, pickled_session, pickle_nonce)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (our_device_id, their_identity_key) DO UPDATE SET
                pickled_session = $3,
                pickle_nonce = $4,
                last_used_at = NOW()
            "#
        )
        .bind(our_device_id)
        .bind(their_key_b64)
        .bind(&encrypted)
        .bind(&nonce)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Encrypt pickle using AES-256-GCM
    ///
    /// SECURITY: Uses randomly generated nonce for each encryption
    fn encrypt_pickle(&self, data: &[u8]) -> Result<(Vec<u8>, Vec<u8>), OlmError> {
        let cipher = Aes256Gcm::new_from_slice(&self.encryption_key.0)
            .map_err(|e| OlmError::Encryption(e.to_string()))?;

        // Generate random nonce (96 bits for GCM)
        let mut nonce_bytes = [0u8; 12];
        getrandom::getrandom(&mut nonce_bytes)
            .map_err(|e| OlmError::Encryption(format!("RNG failure: {}", e)))?;
        let nonce = GenericArray::from_slice(&nonce_bytes);

        let ciphertext = cipher
            .encrypt(nonce, data)
            .map_err(|e| OlmError::Encryption(e.to_string()))?;

        Ok((ciphertext, nonce_bytes.to_vec()))
    }

    /// Decrypt pickle using AES-256-GCM
    fn decrypt_pickle(&self, ciphertext: &[u8], nonce: &[u8]) -> Result<Vec<u8>, OlmError> {
        let nonce_array: [u8; 12] = nonce.try_into().map_err(|_| {
            OlmError::Decryption(format!(
                "Invalid nonce length: expected 12, got {}",
                nonce.len()
            ))
        })?;

        let cipher = Aes256Gcm::new_from_slice(&self.encryption_key.0)
            .map_err(|e| OlmError::Decryption(e.to_string()))?;

        let nonce = GenericArray::from_slice(&nonce_array);

        cipher
            .decrypt(nonce, ciphertext)
            .map_err(|e| OlmError::Decryption(format!("AES-GCM decryption failed: {}", e)))
    }
}

// ========================================================================
// To-device message methods
// ========================================================================

/// Record for to-device messages returned from database
#[derive(Debug, Clone)]
pub struct ToDeviceMessageRecord {
    pub id: Uuid,
    pub sender_user_id: Uuid,
    pub sender_device_id: String,
    pub message_type: String,
    pub content: Vec<u8>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl OlmService {
    /// Store a to-device message in the queue
    ///
    /// To-device messages are used for:
    /// - Room key sharing (m.room_key)
    /// - Device verification (m.key.verification.*)
    /// - Out-of-band signaling
    ///
    /// Messages are delivered on next sync and deleted after acknowledgment.
    #[instrument(skip(self, content))]
    pub async fn store_to_device_message(
        &self,
        sender_user_id: Uuid,
        sender_device_id: &str,
        recipient_user_id: Uuid,
        recipient_device_id: &str,
        message_type: &str,
        content: &[u8],
    ) -> Result<Uuid, OlmError> {
        let row = sqlx::query(
            r#"
            INSERT INTO to_device_messages (
                sender_user_id, sender_device_id,
                recipient_user_id, recipient_device_id,
                message_type, content
            )
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id
            "#,
        )
        .bind(sender_user_id)
        .bind(sender_device_id)
        .bind(recipient_user_id)
        .bind(recipient_device_id)
        .bind(message_type)
        .bind(content)
        .fetch_one(&self.pool)
        .await?;

        let id: Uuid = row.get("id");

        info!(
            message_id = %id,
            sender_user = %sender_user_id,
            recipient_user = %recipient_user_id,
            message_type = %message_type,
            "Stored to-device message"
        );

        Ok(id)
    }

    /// Get pending to-device messages for a device
    ///
    /// Returns undelivered messages in chronological order.
    /// Messages are NOT deleted by this call - use `mark_messages_delivered`
    /// after the client acknowledges receipt.
    #[instrument(skip(self))]
    pub async fn get_to_device_messages(
        &self,
        recipient_user_id: Uuid,
        recipient_device_id: &str,
        limit: i32,
    ) -> Result<Vec<ToDeviceMessageRecord>, OlmError> {
        let rows = sqlx::query(
            r#"
            SELECT id, sender_user_id, sender_device_id, message_type, content, created_at
            FROM to_device_messages
            WHERE recipient_user_id = $1
              AND recipient_device_id = $2
              AND NOT delivered
              AND expires_at > NOW()
            ORDER BY created_at ASC
            LIMIT $3
            "#,
        )
        .bind(recipient_user_id)
        .bind(recipient_device_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let messages: Vec<ToDeviceMessageRecord> = rows
            .into_iter()
            .map(|row| ToDeviceMessageRecord {
                id: row.get("id"),
                sender_user_id: row.get("sender_user_id"),
                sender_device_id: row.get("sender_device_id"),
                message_type: row.get("message_type"),
                content: row.get("content"),
                created_at: row.get("created_at"),
            })
            .collect();

        debug!(
            recipient_user = %recipient_user_id,
            recipient_device = %recipient_device_id,
            count = messages.len(),
            "Retrieved to-device messages"
        );

        Ok(messages)
    }

    /// Mark to-device messages as delivered
    ///
    /// Called after the client acknowledges receipt. Marks messages as delivered
    /// (soft delete for audit) rather than hard deleting.
    #[instrument(skip(self))]
    pub async fn mark_messages_delivered(&self, message_ids: &[Uuid]) -> Result<usize, OlmError> {
        if message_ids.is_empty() {
            return Ok(0);
        }

        let result = sqlx::query(
            r#"
            UPDATE to_device_messages
            SET delivered = true, delivered_at = NOW()
            WHERE id = ANY($1) AND NOT delivered
            "#,
        )
        .bind(message_ids)
        .execute(&self.pool)
        .await?;

        let count = result.rows_affected() as usize;

        debug!(
            message_count = message_ids.len(),
            marked = count,
            "Marked to-device messages as delivered"
        );

        Ok(count)
    }

    /// Delete a specific to-device message (for acknowledgment endpoint)
    ///
    /// Used when a client explicitly acknowledges a single message.
    #[instrument(skip(self))]
    pub async fn delete_to_device_message(
        &self,
        message_id: Uuid,
        recipient_user_id: Uuid,
        recipient_device_id: &str,
    ) -> Result<bool, OlmError> {
        let result = sqlx::query(
            r#"
            UPDATE to_device_messages
            SET delivered = true, delivered_at = NOW()
            WHERE id = $1
              AND recipient_user_id = $2
              AND recipient_device_id = $3
              AND NOT delivered
            "#,
        )
        .bind(message_id)
        .bind(recipient_user_id)
        .bind(recipient_device_id)
        .execute(&self.pool)
        .await?;

        let deleted = result.rows_affected() > 0;

        if deleted {
            debug!(message_id = %message_id, "Acknowledged to-device message");
        } else {
            debug!(message_id = %message_id, "To-device message not found or already acknowledged");
        }

        Ok(deleted)
    }

    /// Store room key for group E2EE
    ///
    /// Called when sharing Megolm session keys with new conversation members.
    /// The exported_key should be Olm-encrypted for the target device.
    #[instrument(skip(self, exported_key))]
    pub async fn store_room_key(
        &self,
        room_id: Uuid,
        session_id: &str,
        for_device_id: &str,
        exported_key: &[u8],
        from_index: i32,
    ) -> Result<Uuid, OlmError> {
        let row = sqlx::query(
            r#"
            INSERT INTO room_key_history (room_id, session_id, for_device_id, exported_key, from_index)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (for_device_id, session_id) DO UPDATE SET
                exported_key = $4,
                from_index = LEAST(room_key_history.from_index, $5)
            RETURNING id
            "#,
        )
        .bind(room_id)
        .bind(session_id)
        .bind(for_device_id)
        .bind(exported_key)
        .bind(from_index)
        .fetch_one(&self.pool)
        .await?;

        let id: Uuid = row.get("id");

        debug!(
            room_id = %room_id,
            session_id = %session_id,
            for_device = %for_device_id,
            "Stored room key in history"
        );

        Ok(id)
    }

    /// Cleanup expired to-device messages
    ///
    /// Call periodically (e.g., daily cron) to remove stale messages.
    /// Returns the number of messages deleted.
    #[instrument(skip(self))]
    pub async fn cleanup_expired_messages(&self) -> Result<usize, OlmError> {
        let result = sqlx::query(
            r#"
            DELETE FROM to_device_messages
            WHERE expires_at < NOW() OR delivered = true
            "#,
        )
        .execute(&self.pool)
        .await?;

        let count = result.rows_affected() as usize;

        if count > 0 {
            info!(deleted = count, "Cleaned up expired/delivered to-device messages");
        }

        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Add integration tests with testcontainers
    // Required test coverage:
    // 1. Account creation and retrieval
    // 2. One-time key generation and claiming
    // 3. Outbound session creation
    // 4. Inbound session creation from PreKey message
    // 5. Message encryption/decryption flow
    // 6. Concurrent key claiming (ensure atomic claim)
    // 7. Pickle encryption/decryption
    // 8. Error cases: missing account, missing session, invalid keys

    #[test]
    fn test_account_encryption_key_from_bytes() {
        let key_bytes = [42u8; 32];
        let key = AccountEncryptionKey::from_bytes(key_bytes);
        assert_eq!(key.0, key_bytes);
    }

    #[test]
    fn test_account_encryption_key_zeroized() {
        let key_bytes = [42u8; 32];
        let mut key = AccountEncryptionKey::from_bytes(key_bytes);

        // Manually drop and verify zeroization
        key.0.zeroize();
        assert_eq!(key.0, [0u8; 32]);
    }
}
