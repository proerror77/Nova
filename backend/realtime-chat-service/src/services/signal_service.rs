//! Signal Protocol Key Distribution Service
//!
//! Implements server-side key management for Signal Protocol:
//! - Device registration with identity keys
//! - PreKey bundle distribution (X3DH)
//! - One-time prekey management
//! - Kyber (post-quantum) prekey support
//! - Sender Key distribution for groups

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use thiserror::Error;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Signal Service errors
#[derive(Debug, Error)]
pub enum SignalError {
    #[error("Device not found: {0}")]
    DeviceNotFound(String),

    #[error("No prekeys available for device: {0}")]
    NoPrekeysAvailable(String),

    #[error("Invalid key format: {0}")]
    InvalidKeyFormat(String),

    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    #[error("Registration failed: {0}")]
    RegistrationFailed(String),
}

/// Device registration with Signal Protocol keys
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalDevice {
    pub user_id: String,
    pub device_id: u32,
    pub registration_id: u32,
    pub identity_key: Vec<u8>,
    pub device_name: Option<String>,
    pub platform: String,
    pub registered_at: DateTime<Utc>,
    pub last_active_at: DateTime<Utc>,
}

/// Signed PreKey (rotated periodically)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedPreKey {
    pub key_id: u32,
    pub public_key: Vec<u8>,
    pub signature: Vec<u8>,
    pub timestamp: i64,
}

/// One-time PreKey (consumed on use)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreKey {
    pub key_id: u32,
    pub public_key: Vec<u8>,
}

/// Kyber PreKey (post-quantum)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KyberPreKey {
    pub key_id: u32,
    pub public_key: Vec<u8>,
    pub signature: Vec<u8>,
    pub timestamp: i64,
}

/// PreKey bundle for session establishment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreKeyBundle {
    pub user_id: String,
    pub device_id: u32,
    pub registration_id: u32,
    pub identity_key: Vec<u8>,
    pub signed_pre_key: SignedPreKey,
    pub pre_key: Option<PreKey>,
    pub kyber_pre_key: Option<KyberPreKey>,
}

/// Sender Key distribution for groups
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SenderKeyDistribution {
    pub group_id: String,
    pub sender_user_id: String,
    pub sender_device_id: u32,
    pub distribution_message: Vec<u8>,
    pub uploaded_at: DateTime<Utc>,
}

/// Signal Protocol Key Distribution Service
#[derive(Clone)]
pub struct SignalService {
    pool: PgPool,
}

impl SignalService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Register a device with its Signal Protocol keys
    pub async fn register_device(
        &self,
        user_id: &str,
        device_id: u32,
        registration_id: u32,
        identity_key: &[u8],
        signed_pre_key: &SignedPreKey,
        pre_keys: &[PreKey],
        kyber_pre_key: Option<&KyberPreKey>,
        device_name: Option<&str>,
        platform: &str,
    ) -> Result<SignalDevice, SignalError> {
        let identity_key_b64 = BASE64.encode(identity_key);

        // Insert device
        let device: SignalDevice = sqlx::query_as!(
            SignalDevice,
            r#"
            INSERT INTO signal_devices (
                user_id, device_id, registration_id, identity_key,
                device_name, platform, registered_at, last_active_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
            ON CONFLICT (user_id, device_id) DO UPDATE SET
                registration_id = EXCLUDED.registration_id,
                identity_key = EXCLUDED.identity_key,
                device_name = EXCLUDED.device_name,
                platform = EXCLUDED.platform,
                last_active_at = NOW()
            RETURNING
                user_id,
                device_id as "device_id: u32",
                registration_id as "registration_id: u32",
                decode(identity_key, 'base64') as "identity_key!: Vec<u8>",
                device_name,
                platform,
                registered_at,
                last_active_at
            "#,
            user_id,
            device_id as i32,
            registration_id as i32,
            &identity_key_b64,
            device_name,
            platform,
        )
        .fetch_one(&self.pool)
        .await?;

        // Store signed prekey
        self.store_signed_prekey(user_id, device_id, signed_pre_key)
            .await?;

        // Store one-time prekeys
        for pre_key in pre_keys {
            self.store_prekey(user_id, device_id, pre_key).await?;
        }

        // Store Kyber prekey if provided
        if let Some(kyber) = kyber_pre_key {
            self.store_kyber_prekey(user_id, device_id, kyber).await?;
        }

        info!(
            user_id = user_id,
            device_id = device_id,
            prekeys_count = pre_keys.len(),
            "Signal device registered"
        );

        Ok(device)
    }

    /// Get prekey bundle for establishing a session
    pub async fn get_prekey_bundle(
        &self,
        user_id: &str,
        device_id: u32,
    ) -> Result<PreKeyBundle, SignalError> {
        // Get device info
        let device = sqlx::query!(
            r#"
            SELECT
                registration_id,
                decode(identity_key, 'base64') as "identity_key!: Vec<u8>"
            FROM signal_devices
            WHERE user_id = $1 AND device_id = $2
            "#,
            user_id,
            device_id as i32,
        )
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| SignalError::DeviceNotFound(format!("{}:{}", user_id, device_id)))?;

        // Get signed prekey (latest)
        let signed_prekey = sqlx::query!(
            r#"
            SELECT
                key_id,
                decode(public_key, 'base64') as "public_key!: Vec<u8>",
                decode(signature, 'base64') as "signature!: Vec<u8>",
                EXTRACT(EPOCH FROM timestamp)::bigint as "timestamp!: i64"
            FROM signal_signed_prekeys
            WHERE user_id = $1 AND device_id = $2
            ORDER BY uploaded_at DESC
            LIMIT 1
            "#,
            user_id,
            device_id as i32,
        )
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| SignalError::NoPrekeysAvailable(format!("{}:{}", user_id, device_id)))?;

        // Claim one-time prekey (atomic)
        let prekey = self.claim_prekey(user_id, device_id).await?;

        // Get Kyber prekey (latest unused)
        let kyber_prekey = sqlx::query!(
            r#"
            SELECT
                key_id,
                decode(public_key, 'base64') as "public_key!: Vec<u8>",
                decode(signature, 'base64') as "signature!: Vec<u8>",
                EXTRACT(EPOCH FROM timestamp)::bigint as "timestamp!: i64"
            FROM signal_kyber_prekeys
            WHERE user_id = $1 AND device_id = $2 AND used = false
            ORDER BY uploaded_at DESC
            LIMIT 1
            "#,
            user_id,
            device_id as i32,
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(PreKeyBundle {
            user_id: user_id.to_string(),
            device_id,
            registration_id: device.registration_id as u32,
            identity_key: device.identity_key,
            signed_pre_key: SignedPreKey {
                key_id: signed_prekey.key_id as u32,
                public_key: signed_prekey.public_key,
                signature: signed_prekey.signature,
                timestamp: signed_prekey.timestamp,
            },
            pre_key: prekey,
            kyber_pre_key: kyber_prekey.map(|k| KyberPreKey {
                key_id: k.key_id as u32,
                public_key: k.public_key,
                signature: k.signature,
                timestamp: k.timestamp,
            }),
        })
    }

    /// Claim a one-time prekey (atomic operation)
    async fn claim_prekey(
        &self,
        user_id: &str,
        device_id: u32,
    ) -> Result<Option<PreKey>, SignalError> {
        // Atomically claim the oldest unclaimed prekey
        let prekey = sqlx::query!(
            r#"
            WITH claimed AS (
                SELECT key_id, public_key
                FROM signal_prekeys
                WHERE user_id = $1 AND device_id = $2 AND claimed_at IS NULL
                ORDER BY key_id ASC
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            )
            UPDATE signal_prekeys p
            SET claimed_at = NOW()
            FROM claimed c
            WHERE p.user_id = $1 AND p.device_id = $2 AND p.key_id = c.key_id
            RETURNING
                p.key_id,
                decode(p.public_key, 'base64') as "public_key!: Vec<u8>"
            "#,
            user_id,
            device_id as i32,
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(prekey.map(|p| PreKey {
            key_id: p.key_id as u32,
            public_key: p.public_key,
        }))
    }

    /// Get remaining prekey count
    pub async fn get_prekey_count(&self, user_id: &str, device_id: u32) -> Result<u32, SignalError> {
        let count = sqlx::query_scalar!(
            r#"
            SELECT COUNT(*) as "count!: i64"
            FROM signal_prekeys
            WHERE user_id = $1 AND device_id = $2 AND claimed_at IS NULL
            "#,
            user_id,
            device_id as i32,
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(count as u32)
    }

    /// Upload additional prekeys
    pub async fn upload_prekeys(
        &self,
        user_id: &str,
        device_id: u32,
        pre_keys: &[PreKey],
    ) -> Result<u32, SignalError> {
        let mut count = 0;
        for pre_key in pre_keys {
            if self.store_prekey(user_id, device_id, pre_key).await.is_ok() {
                count += 1;
            }
        }

        info!(
            user_id = user_id,
            device_id = device_id,
            uploaded = count,
            "Uploaded prekeys"
        );

        Ok(count)
    }

    /// Upload new signed prekey
    pub async fn upload_signed_prekey(
        &self,
        user_id: &str,
        device_id: u32,
        signed_pre_key: &SignedPreKey,
    ) -> Result<(), SignalError> {
        self.store_signed_prekey(user_id, device_id, signed_pre_key)
            .await?;

        info!(
            user_id = user_id,
            device_id = device_id,
            key_id = signed_pre_key.key_id,
            "Uploaded signed prekey"
        );

        Ok(())
    }

    /// List all devices for a user
    pub async fn list_devices(&self, user_id: &str) -> Result<Vec<u32>, SignalError> {
        let devices = sqlx::query_scalar!(
            r#"
            SELECT device_id as "device_id!: i32"
            FROM signal_devices
            WHERE user_id = $1
            ORDER BY device_id
            "#,
            user_id,
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(devices.into_iter().map(|d| d as u32).collect())
    }

    /// Remove a device
    pub async fn remove_device(&self, user_id: &str, device_id: u32) -> Result<bool, SignalError> {
        // Delete in order: prekeys, signed prekeys, kyber prekeys, device
        sqlx::query!(
            "DELETE FROM signal_prekeys WHERE user_id = $1 AND device_id = $2",
            user_id,
            device_id as i32,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query!(
            "DELETE FROM signal_signed_prekeys WHERE user_id = $1 AND device_id = $2",
            user_id,
            device_id as i32,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query!(
            "DELETE FROM signal_kyber_prekeys WHERE user_id = $1 AND device_id = $2",
            user_id,
            device_id as i32,
        )
        .execute(&self.pool)
        .await?;

        let result = sqlx::query!(
            "DELETE FROM signal_devices WHERE user_id = $1 AND device_id = $2",
            user_id,
            device_id as i32,
        )
        .execute(&self.pool)
        .await?;

        info!(user_id = user_id, device_id = device_id, "Removed device");

        Ok(result.rows_affected() > 0)
    }

    /// Store sender key distribution for group
    pub async fn store_sender_key(
        &self,
        group_id: &str,
        sender_user_id: &str,
        sender_device_id: u32,
        distribution_message: &[u8],
    ) -> Result<(), SignalError> {
        let dist_b64 = BASE64.encode(distribution_message);

        sqlx::query!(
            r#"
            INSERT INTO signal_sender_keys (
                group_id, sender_user_id, sender_device_id, distribution_message, uploaded_at
            )
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (group_id, sender_user_id, sender_device_id) DO UPDATE SET
                distribution_message = EXCLUDED.distribution_message,
                uploaded_at = NOW()
            "#,
            group_id,
            sender_user_id,
            sender_device_id as i32,
            &dist_b64,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Get sender key distribution for group
    pub async fn get_sender_key(
        &self,
        group_id: &str,
        sender_user_id: &str,
        sender_device_id: u32,
    ) -> Result<Option<Vec<u8>>, SignalError> {
        let result = sqlx::query_scalar!(
            r#"
            SELECT decode(distribution_message, 'base64') as "distribution_message!: Vec<u8>"
            FROM signal_sender_keys
            WHERE group_id = $1 AND sender_user_id = $2 AND sender_device_id = $3
            "#,
            group_id,
            sender_user_id,
            sender_device_id as i32,
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(result)
    }

    // Internal helpers

    async fn store_prekey(
        &self,
        user_id: &str,
        device_id: u32,
        pre_key: &PreKey,
    ) -> Result<(), SignalError> {
        let public_key_b64 = BASE64.encode(&pre_key.public_key);

        sqlx::query!(
            r#"
            INSERT INTO signal_prekeys (user_id, device_id, key_id, public_key, uploaded_at)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (user_id, device_id, key_id) DO NOTHING
            "#,
            user_id,
            device_id as i32,
            pre_key.key_id as i32,
            &public_key_b64,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    async fn store_signed_prekey(
        &self,
        user_id: &str,
        device_id: u32,
        signed_pre_key: &SignedPreKey,
    ) -> Result<(), SignalError> {
        let public_key_b64 = BASE64.encode(&signed_pre_key.public_key);
        let signature_b64 = BASE64.encode(&signed_pre_key.signature);

        sqlx::query!(
            r#"
            INSERT INTO signal_signed_prekeys (
                user_id, device_id, key_id, public_key, signature, timestamp, uploaded_at
            )
            VALUES ($1, $2, $3, $4, $5, to_timestamp($6), NOW())
            ON CONFLICT (user_id, device_id, key_id) DO UPDATE SET
                public_key = EXCLUDED.public_key,
                signature = EXCLUDED.signature,
                timestamp = EXCLUDED.timestamp,
                uploaded_at = NOW()
            "#,
            user_id,
            device_id as i32,
            signed_pre_key.key_id as i32,
            &public_key_b64,
            &signature_b64,
            signed_pre_key.timestamp as f64 / 1000.0,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    async fn store_kyber_prekey(
        &self,
        user_id: &str,
        device_id: u32,
        kyber_pre_key: &KyberPreKey,
    ) -> Result<(), SignalError> {
        let public_key_b64 = BASE64.encode(&kyber_pre_key.public_key);
        let signature_b64 = BASE64.encode(&kyber_pre_key.signature);

        sqlx::query!(
            r#"
            INSERT INTO signal_kyber_prekeys (
                user_id, device_id, key_id, public_key, signature, timestamp, used, uploaded_at
            )
            VALUES ($1, $2, $3, $4, $5, to_timestamp($6), false, NOW())
            ON CONFLICT (user_id, device_id, key_id) DO UPDATE SET
                public_key = EXCLUDED.public_key,
                signature = EXCLUDED.signature,
                timestamp = EXCLUDED.timestamp,
                uploaded_at = NOW()
            "#,
            user_id,
            device_id as i32,
            kyber_pre_key.key_id as i32,
            &public_key_b64,
            &signature_b64,
            kyber_pre_key.timestamp as f64 / 1000.0,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_prekey_serialization() {
        let prekey = PreKey {
            key_id: 1,
            public_key: vec![1, 2, 3, 4],
        };

        let json = serde_json::to_string(&prekey).unwrap();
        let decoded: PreKey = serde_json::from_str(&json).unwrap();

        assert_eq!(prekey.key_id, decoded.key_id);
        assert_eq!(prekey.public_key, decoded.public_key);
    }
}
