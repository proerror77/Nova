use crate::error::AppError;
use base64::{engine::general_purpose, Engine as _};
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

/// Device key pair for ECDH key exchange
#[derive(Clone, Serialize, Deserialize)]
pub struct DeviceKeyPair {
    pub device_id: String,
    pub user_id: Uuid,
    /// Base64 encoded public key (32 bytes)
    pub public_key: String,
    /// Base64 encoded private key (stored securely, never transmitted)
    pub private_key_encrypted: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// ECDH Key Exchange service for end-to-end encryption
pub struct KeyExchangeService {
    db: Arc<sqlx::PgPool>,
}

impl KeyExchangeService {
    pub fn new(db: Arc<sqlx::PgPool>) -> Self {
        Self { db }
    }

    /// Generates a new X25519 key pair for a device
    pub fn generate_keypair() -> Result<(Vec<u8>, Vec<u8>), AppError> {
        // Generate a random 32-byte private key
        let mut rng = rand::thread_rng();
        let mut private_key = [0u8; 32];
        rng.fill(&mut private_key);

        // Derive public key from private key using x25519
        let public_key = x25519_dalek::x25519(private_key, x25519_dalek::X25519_BASEPOINT_BYTES);

        Ok((private_key.to_vec(), public_key.to_vec()))
    }

    /// Performs ECDH to derive a shared secret
    pub fn perform_ecdh(
        our_private_key: &[u8],
        their_public_key: &[u8],
    ) -> Result<Vec<u8>, AppError> {
        if our_private_key.len() != 32 {
            return Err(AppError::BadRequest(
                "Private key must be 32 bytes".to_string(),
            ));
        }
        if their_public_key.len() != 32 {
            return Err(AppError::BadRequest(
                "Public key must be 32 bytes".to_string(),
            ));
        }

        let private_array =
            <[u8; 32]>::try_from(our_private_key).map_err(|_| AppError::Internal)?;
        let public_array =
            <[u8; 32]>::try_from(their_public_key).map_err(|_| AppError::Internal)?;

        let shared_secret = x25519_dalek::x25519(private_array, public_array);

        Ok(shared_secret.to_vec())
    }

    /// Derives a message encryption key from the shared secret
    pub fn derive_message_key(
        shared_secret: &[u8],
        conversation_id: Uuid,
        sequence: u64,
    ) -> Result<[u8; 32], AppError> {
        use hkdf::Hkdf;
        use sha2::Sha256;

        // Use conversation_id and sequence as additional context
        let mut info = Vec::new();
        info.extend_from_slice(conversation_id.as_bytes());
        info.extend_from_slice(&sequence.to_le_bytes());

        let hk = Hkdf::<Sha256>::new(Some(&info), shared_secret);
        let mut key = [0u8; 32];
        hk.expand(b"message_key", &mut key)
            .map_err(|e| AppError::Encryption(format!("HKDF expand failed: {}", e)))?;

        Ok(key)
    }

    /// Stores device public key in the database
    pub async fn store_device_key(
        &self,
        user_id: Uuid,
        device_id: String,
        public_key: Vec<u8>,
        private_key_encrypted: Vec<u8>,
    ) -> Result<(), AppError> {
        let public_key_b64 = general_purpose::STANDARD.encode(&public_key);
        let private_key_encrypted_b64 = general_purpose::STANDARD.encode(&private_key_encrypted);

        sqlx::query(
            r#"
            INSERT INTO device_keys (user_id, device_id, public_key, private_key_encrypted)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (user_id, device_id) DO UPDATE SET
                public_key = EXCLUDED.public_key,
                private_key_encrypted = EXCLUDED.private_key_encrypted,
                updated_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(&device_id)
        .bind(&public_key_b64)
        .bind(&private_key_encrypted_b64)
        .execute(&*self.db)
        .await?;

        Ok(())
    }

    /// Retrieves device public key from database
    pub async fn get_device_public_key(
        &self,
        user_id: Uuid,
        device_id: String,
    ) -> Result<Option<Vec<u8>>, AppError> {
        let row = sqlx::query_scalar::<_, String>(
            "SELECT public_key FROM device_keys WHERE user_id = $1 AND device_id = $2",
        )
        .bind(user_id)
        .bind(device_id)
        .fetch_optional(&*self.db)
        .await?;

        match row {
            Some(key_b64) => {
                let key = general_purpose::STANDARD
                    .decode(&key_b64)
                    .map_err(|e| AppError::Encryption(format!("Base64 decode failed: {}", e)))?;
                Ok(Some(key))
            }
            None => Ok(None),
        }
    }

    /// Records a key exchange event for audit trail
    pub async fn record_key_exchange(
        &self,
        conversation_id: Uuid,
        initiator_id: Uuid,
        peer_id: Uuid,
        shared_secret_hash: Vec<u8>,
    ) -> Result<(), AppError> {
        sqlx::query(
            r#"
            INSERT INTO key_exchanges (conversation_id, initiator_id, peer_id, shared_secret_hash)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(conversation_id)
        .bind(initiator_id)
        .bind(peer_id)
        .bind(shared_secret_hash)
        .execute(&*self.db)
        .await?;

        Ok(())
    }

    /// Lists all key exchanges for a conversation
    pub async fn list_key_exchanges(
        &self,
        conversation_id: Uuid,
    ) -> Result<Vec<KeyExchangeRecord>, AppError> {
        let records = sqlx::query_as::<_, KeyExchangeRecord>(
            "SELECT * FROM key_exchanges WHERE conversation_id = $1 ORDER BY created_at DESC",
        )
        .bind(conversation_id)
        .fetch_all(&*self.db)
        .await?;

        Ok(records)
    }
}

/// Key exchange record for audit trail
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct KeyExchangeRecord {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub initiator_id: Uuid,
    pub peer_id: Uuid,
    pub shared_secret_hash: Vec<u8>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_keypair() {
        let (private, public) = KeyExchangeService::generate_keypair().unwrap();
        assert_eq!(private.len(), 32);
        assert_eq!(public.len(), 32);
    }

    #[test]
    fn test_ecdh_derives_same_secret() {
        let (alice_priv, alice_pub) = KeyExchangeService::generate_keypair().unwrap();
        let (bob_priv, bob_pub) = KeyExchangeService::generate_keypair().unwrap();

        let alice_secret = KeyExchangeService::perform_ecdh(&alice_priv, &bob_pub).unwrap();
        let bob_secret = KeyExchangeService::perform_ecdh(&bob_priv, &alice_pub).unwrap();

        assert_eq!(alice_secret, bob_secret);
        assert_eq!(alice_secret.len(), 32);
    }

    #[test]
    fn test_derive_message_key() {
        let (alice_priv, alice_pub) = KeyExchangeService::generate_keypair().unwrap();
        let (bob_priv, bob_pub) = KeyExchangeService::generate_keypair().unwrap();

        let shared_secret = KeyExchangeService::perform_ecdh(&alice_priv, &bob_pub).unwrap();
        let conversation_id = Uuid::new_v4();

        let key1 =
            KeyExchangeService::derive_message_key(&shared_secret, conversation_id, 1).unwrap();
        let key2 =
            KeyExchangeService::derive_message_key(&shared_secret, conversation_id, 2).unwrap();

        assert_eq!(key1.len(), 32);
        assert_eq!(key2.len(), 32);
        assert_ne!(key1, key2); // Different sequence numbers should produce different keys
    }
}
