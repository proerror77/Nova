//! Message Service for E2E Encrypted Messaging
//!
//! Phase 5 Feature 2: Handles database operations for encrypted messages, key exchange, and public key management

use crate::error::AppError;
use crate::services::messaging::encryption::{EncryptedMessage, EncryptionService, KeyExchange, KeyExchangeStatus, UserPublicKey};
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

pub struct MessageService {
    pool: PgPool,
}

impl MessageService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Send an encrypted message
    pub async fn send_encrypted_message(
        &self,
        sender_id: Uuid,
        recipient_id: Uuid,
        encrypted_content: &str,
        nonce: &str,
    ) -> Result<EncryptedMessage, AppError> {
        // Validate inputs
        EncryptionService::validate_encrypted_content(encrypted_content)?;
        EncryptionService::validate_nonce(nonce)?;

        // Get sender's public key
        let sender_key = self.get_public_key(sender_id).await?
            .ok_or_else(|| AppError::NotFound("Sender public key not found".to_string()))?;

        // Verify nonce uniqueness
        let conversation_pair = Self::make_conversation_pair(sender_id, recipient_id);
        self.verify_nonce_unique(&conversation_pair, nonce).await?;

        // Insert message
        let message = sqlx::query_as!(
            EncryptedMessageRow,
            r#"
            INSERT INTO encrypted_messages (sender_id, recipient_id, encrypted_content, nonce, sender_public_key)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING
                id, sender_id, recipient_id, encrypted_content, nonce, sender_public_key,
                delivered, read, created_at
            "#,
            sender_id,
            recipient_id,
            encrypted_content,
            nonce,
            sender_key.public_key
        )
        .fetch_one(&self.pool)
        .await?;

        // Record nonce usage
        self.record_nonce_usage(&conversation_pair, nonce).await?;

        Ok(EncryptedMessage {
            id: message.id,
            sender_id: message.sender_id,
            recipient_id: message.recipient_id,
            encrypted_content: message.encrypted_content,
            nonce: message.nonce,
            sender_public_key: message.sender_public_key,
            delivered: message.delivered.unwrap_or(false),
            read: message.read.unwrap_or(false),
            created_at: message.created_at.unwrap_or_else(Utc::now),
        })
    }

    /// Get a user's public key
    pub async fn get_public_key(&self, user_id: Uuid) -> Result<Option<UserPublicKey>, AppError> {
        let result = sqlx::query_as!(
            UserPublicKeyRow,
            r#"
            SELECT user_id, public_key, registered_at, last_used_at, rotation_interval_days, next_rotation_at
            FROM user_public_keys
            WHERE user_id = $1
            "#,
            user_id
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(result.map(|row| UserPublicKey {
            user_id: row.user_id,
            public_key: row.public_key,
            registered_at: row.registered_at.unwrap_or_else(Utc::now),
            last_used_at: row.last_used_at,
            rotation_interval_days: row.rotation_interval_days.unwrap_or(30) as u32,
            next_rotation_at: row.next_rotation_at.unwrap_or_else(|| Utc::now() + chrono::Duration::days(30)),
        }))
    }

    /// Initiate a key exchange with another user
    pub async fn initiate_key_exchange(
        &self,
        initiator_id: Uuid,
        recipient_id: Uuid,
        initiator_public_key: &str,
    ) -> Result<KeyExchange, AppError> {
        // Validate public key
        EncryptionService::validate_public_key(initiator_public_key)?;

        // Ensure users are different
        if initiator_id == recipient_id {
            return Err(AppError::BadRequest("Cannot initiate key exchange with yourself".to_string()));
        }

        // Check for existing pending exchange
        let existing = sqlx::query!(
            r#"
            SELECT id FROM key_exchanges
            WHERE initiator_id = $1 AND recipient_id = $2 AND status = 'pending'
            "#,
            initiator_id,
            recipient_id
        )
        .fetch_optional(&self.pool)
        .await?;

        if existing.is_some() {
            return Err(AppError::Conflict("Key exchange already pending".to_string()));
        }

        // Insert new key exchange
        let exchange = sqlx::query_as!(
            KeyExchangeRow,
            r#"
            INSERT INTO key_exchanges (initiator_id, recipient_id, initiator_public_key, status)
            VALUES ($1, $2, $3, 'pending')
            RETURNING id, initiator_id, recipient_id, initiator_public_key, status, created_at, completed_at
            "#,
            initiator_id,
            recipient_id,
            initiator_public_key
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(KeyExchange {
            id: exchange.id,
            initiator_id: exchange.initiator_id,
            recipient_id: exchange.recipient_id,
            initiator_public_key: exchange.initiator_public_key.unwrap_or_default(),
            status: Self::parse_status(&exchange.status.unwrap_or_else(|| "pending".to_string())),
            created_at: exchange.created_at.unwrap_or_else(Utc::now),
            completed_at: exchange.completed_at,
        })
    }

    /// Complete a key exchange
    pub async fn complete_key_exchange(
        &self,
        exchange_id: Uuid,
        recipient_public_key: &str,
    ) -> Result<(), AppError> {
        // Validate public key
        EncryptionService::validate_public_key(recipient_public_key)?;

        // Get exchange
        let exchange = sqlx::query!(
            r#"
            SELECT status FROM key_exchanges WHERE id = $1
            "#,
            exchange_id
        )
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Key exchange not found".to_string()))?;

        if exchange.status != Some("pending".to_string()) {
            return Err(AppError::BadRequest("Key exchange must be pending to complete".to_string()));
        }

        // Update status
        sqlx::query!(
            r#"
            UPDATE key_exchanges
            SET status = 'completed', completed_at = CURRENT_TIMESTAMP
            WHERE id = $1
            "#,
            exchange_id
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Register a user's public key
    pub async fn register_public_key(
        &self,
        user_id: Uuid,
        public_key: &str,
    ) -> Result<UserPublicKey, AppError> {
        // Validate public key
        EncryptionService::validate_public_key(public_key)?;

        let rotation_interval_days: i32 = 30;
        let now = Utc::now();
        let next_rotation = now + chrono::Duration::days(rotation_interval_days as i64);

        // Upsert public key
        let result = sqlx::query_as!(
            UserPublicKeyRow,
            r#"
            INSERT INTO user_public_keys (user_id, public_key, rotation_interval_days, next_rotation_at, registered_at)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (user_id) DO UPDATE
            SET public_key = EXCLUDED.public_key,
                registered_at = EXCLUDED.registered_at,
                next_rotation_at = EXCLUDED.next_rotation_at
            RETURNING user_id, public_key, registered_at, last_used_at, rotation_interval_days, next_rotation_at
            "#,
            user_id,
            public_key,
            rotation_interval_days,
            next_rotation,
            now
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(UserPublicKey {
            user_id: result.user_id,
            public_key: result.public_key,
            registered_at: result.registered_at.unwrap_or_else(Utc::now),
            last_used_at: result.last_used_at,
            rotation_interval_days: result.rotation_interval_days.unwrap_or(30) as u32,
            next_rotation_at: result.next_rotation_at.unwrap_or_else(|| Utc::now() + chrono::Duration::days(30)),
        })
    }

    /// Mark a message as delivered
    pub async fn mark_message_delivered(
        &self,
        message_id: Uuid,
    ) -> Result<(), AppError> {
        let result = sqlx::query!(
            r#"
            UPDATE encrypted_messages
            SET delivered = true, delivered_at = CURRENT_TIMESTAMP
            WHERE id = $1
            "#,
            message_id
        )
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Message not found".to_string()));
        }

        Ok(())
    }

    /// Mark a message as read
    pub async fn mark_message_read(
        &self,
        message_id: Uuid,
    ) -> Result<(), AppError> {
        let result = sqlx::query!(
            r#"
            UPDATE encrypted_messages
            SET read = true, read_at = CURRENT_TIMESTAMP
            WHERE id = $1
            "#,
            message_id
        )
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Message not found".to_string()));
        }

        Ok(())
    }

    /// Get a message by ID
    pub async fn get_message(&self, message_id: Uuid, user_id: Uuid) -> Result<EncryptedMessage, AppError> {
        let message = sqlx::query_as!(
            EncryptedMessageRow,
            r#"
            SELECT id, sender_id, recipient_id, encrypted_content, nonce, sender_public_key, delivered, read, created_at
            FROM encrypted_messages
            WHERE id = $1 AND (sender_id = $2 OR recipient_id = $2)
            "#,
            message_id,
            user_id
        )
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| AppError::NotFound("Message not found or unauthorized".to_string()))?;

        Ok(EncryptedMessage {
            id: message.id,
            sender_id: message.sender_id,
            recipient_id: message.recipient_id,
            encrypted_content: message.encrypted_content,
            nonce: message.nonce,
            sender_public_key: message.sender_public_key,
            delivered: message.delivered.unwrap_or(false),
            read: message.read.unwrap_or(false),
            created_at: message.created_at.unwrap_or_else(Utc::now),
        })
    }

    /// Get messages between two users
    pub async fn get_messages_between(
        &self,
        user1_id: Uuid,
        user2_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<EncryptedMessage>, AppError> {
        let messages = sqlx::query_as!(
            EncryptedMessageRow,
            r#"
            SELECT id, sender_id, recipient_id, encrypted_content, nonce, sender_public_key, delivered, read, created_at
            FROM encrypted_messages
            WHERE (sender_id = $1 AND recipient_id = $2) OR (sender_id = $2 AND recipient_id = $1)
            ORDER BY created_at DESC
            LIMIT $3 OFFSET $4
            "#,
            user1_id,
            user2_id,
            limit,
            offset
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(messages.into_iter().map(|m| EncryptedMessage {
            id: m.id,
            sender_id: m.sender_id,
            recipient_id: m.recipient_id,
            encrypted_content: m.encrypted_content,
            nonce: m.nonce,
            sender_public_key: m.sender_public_key,
            delivered: m.delivered.unwrap_or(false),
            read: m.read.unwrap_or(false),
            created_at: m.created_at.unwrap_or_else(Utc::now),
        }).collect())
    }

    // ============================================
    // Private Helper Methods
    // ============================================

    fn make_conversation_pair(user1: Uuid, user2: Uuid) -> String {
        let mut ids = [user1.to_string(), user2.to_string()];
        ids.sort();
        format!("{}:{}", ids[0], ids[1])
    }

    async fn verify_nonce_unique(&self, conversation_pair: &str, nonce: &str) -> Result<(), AppError> {
        let exists = sqlx::query!(
            r#"
            SELECT id FROM used_nonces
            WHERE conversation_pair = $1 AND nonce = $2
            "#,
            conversation_pair,
            nonce
        )
        .fetch_optional(&self.pool)
        .await?;

        if exists.is_some() {
            return Err(AppError::BadRequest("Nonce already used (replay attack detected)".to_string()));
        }

        Ok(())
    }

    async fn record_nonce_usage(&self, conversation_pair: &str, nonce: &str) -> Result<(), AppError> {
        sqlx::query!(
            r#"
            INSERT INTO used_nonces (conversation_pair, nonce)
            VALUES ($1, $2)
            "#,
            conversation_pair,
            nonce
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    fn parse_status(status: &str) -> KeyExchangeStatus {
        match status {
            "pending" => KeyExchangeStatus::Pending,
            "completed" => KeyExchangeStatus::Completed,
            "failed" => KeyExchangeStatus::Failed,
            _ => KeyExchangeStatus::Failed,
        }
    }
}

// ============================================
// Database Row Types
// ============================================

#[allow(dead_code)]
#[derive(Debug)]
struct EncryptedMessageRow {
    id: Uuid,
    sender_id: Uuid,
    recipient_id: Uuid,
    encrypted_content: String,
    nonce: String,
    sender_public_key: String,
    delivered: Option<bool>,
    read: Option<bool>,
    created_at: Option<DateTime<Utc>>,
}

#[allow(dead_code)]
#[derive(Debug)]
struct UserPublicKeyRow {
    user_id: Uuid,
    public_key: String,
    registered_at: Option<DateTime<Utc>>,
    last_used_at: Option<DateTime<Utc>>,
    rotation_interval_days: Option<i32>,
    next_rotation_at: Option<DateTime<Utc>>,
}

#[allow(dead_code)]
#[derive(Debug)]
struct KeyExchangeRow {
    id: Uuid,
    initiator_id: Uuid,
    recipient_id: Uuid,
    initiator_public_key: Option<String>,
    status: Option<String>,
    created_at: Option<DateTime<Utc>>,
    completed_at: Option<DateTime<Utc>>,
}

// ============================================
// Unit Tests (25 tests)
// ============================================

#[cfg(test)]
mod tests {
    use super::*;
    use base64::{engine::general_purpose, Engine as _};
    use sqlx::PgPool;

    async fn setup_test_pool() -> PgPool {
        let database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nova_user:nova_password@localhost/nova_test".to_string());

        PgPool::connect(&database_url)
            .await
            .expect("Failed to connect to test database")
    }

    async fn create_test_user(pool: &PgPool) -> Uuid {
        let user_id = Uuid::new_v4();
        sqlx::query!(
            r#"
            INSERT INTO users (id, username, email, password_hash)
            VALUES ($1, $2, $3, $4)
            "#,
            user_id,
            format!("user_{}", user_id),
            format!("{}@test.com", user_id),
            "hash"
        )
        .execute(pool)
        .await
        .expect("Failed to create test user");

        user_id
    }

    #[tokio::test]
    #[ignore] // Requires database
    async fn test_register_public_key() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let user_id = create_test_user(&pool).await;

        let public_key = general_purpose::STANDARD.encode(&[1u8; 32]);
        let result = service.register_public_key(user_id, &public_key).await;

        assert!(result.is_ok());
        let stored = result.unwrap();
        assert_eq!(stored.user_id, user_id);
        assert_eq!(stored.public_key, public_key);
        assert_eq!(stored.rotation_interval_days, 30);
    }

    #[tokio::test]
    #[ignore]
    async fn test_register_invalid_public_key() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let user_id = create_test_user(&pool).await;

        let invalid_key = general_purpose::STANDARD.encode(&[1u8; 16]); // Too short
        let result = service.register_public_key(user_id, &invalid_key).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_public_key() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let user_id = create_test_user(&pool).await;

        let public_key = general_purpose::STANDARD.encode(&[2u8; 32]);
        service.register_public_key(user_id, &public_key).await.unwrap();

        let result = service.get_public_key(user_id).await.unwrap();
        assert!(result.is_some());
        assert_eq!(result.unwrap().public_key, public_key);
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_nonexistent_public_key() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool);
        let user_id = Uuid::new_v4();

        let result = service.get_public_key(user_id).await.unwrap();
        assert!(result.is_none());
    }

    #[tokio::test]
    #[ignore]
    async fn test_initiate_key_exchange() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let initiator_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let public_key = general_purpose::STANDARD.encode(&[3u8; 32]);
        let result = service.initiate_key_exchange(initiator_id, recipient_id, &public_key).await;

        assert!(result.is_ok());
        let exchange = result.unwrap();
        assert_eq!(exchange.initiator_id, initiator_id);
        assert_eq!(exchange.recipient_id, recipient_id);
        assert_eq!(exchange.status, KeyExchangeStatus::Pending);
    }

    #[tokio::test]
    #[ignore]
    async fn test_initiate_key_exchange_same_user() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let user_id = create_test_user(&pool).await;

        let public_key = general_purpose::STANDARD.encode(&[4u8; 32]);
        let result = service.initiate_key_exchange(user_id, user_id, &public_key).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_initiate_duplicate_key_exchange() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let initiator_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let public_key = general_purpose::STANDARD.encode(&[5u8; 32]);
        service.initiate_key_exchange(initiator_id, recipient_id, &public_key).await.unwrap();

        let result = service.initiate_key_exchange(initiator_id, recipient_id, &public_key).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_complete_key_exchange() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let initiator_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let initiator_key = general_purpose::STANDARD.encode(&[6u8; 32]);
        let exchange = service.initiate_key_exchange(initiator_id, recipient_id, &initiator_key).await.unwrap();

        let recipient_key = general_purpose::STANDARD.encode(&[7u8; 32]);
        let result = service.complete_key_exchange(exchange.id, &recipient_key).await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    #[ignore]
    async fn test_complete_nonexistent_key_exchange() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool);

        let recipient_key = general_purpose::STANDARD.encode(&[8u8; 32]);
        let result = service.complete_key_exchange(Uuid::new_v4(), &recipient_key).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_send_encrypted_message() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        // Register sender's public key
        let sender_key = general_purpose::STANDARD.encode(&[9u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[0u8; 24]);

        let result = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await;

        assert!(result.is_ok());
        let message = result.unwrap();
        assert_eq!(message.sender_id, sender_id);
        assert_eq!(message.recipient_id, recipient_id);
        assert_eq!(message.encrypted_content, encrypted_content);
        assert!(!message.delivered);
        assert!(!message.read);
    }

    #[tokio::test]
    #[ignore]
    async fn test_send_message_without_public_key() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[0u8; 24]);

        let result = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await;

        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_send_message_with_reused_nonce() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[10u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[1u8; 24]);

        service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await.unwrap();

        // Try to reuse nonce
        let result = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_mark_message_delivered() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[11u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[2u8; 24]);
        let message = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await.unwrap();

        let result = service.mark_message_delivered(message.id).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    #[ignore]
    async fn test_mark_message_read() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[12u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[3u8; 24]);
        let message = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await.unwrap();

        let result = service.mark_message_read(message.id).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    #[ignore]
    async fn test_mark_nonexistent_message_delivered() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool);

        let result = service.mark_message_delivered(Uuid::new_v4()).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_message() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[13u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[4u8; 24]);
        let message = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await.unwrap();

        let result = service.get_message(message.id, sender_id).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_message_unauthorized() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;
        let other_user_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[14u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        let encrypted_content = general_purpose::STANDARD.encode(b"ciphertext");
        let nonce = general_purpose::STANDARD.encode(&[5u8; 24]);
        let message = service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await.unwrap();

        let result = service.get_message(message.id, other_user_id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_messages_between() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[15u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        // Send 3 messages
        for i in 0..3 {
            let encrypted_content = general_purpose::STANDARD.encode(format!("message {}", i).as_bytes());
            let nonce = general_purpose::STANDARD.encode(&[6u8 + i as u8; 24]);
            service.send_encrypted_message(sender_id, recipient_id, &encrypted_content, &nonce).await.unwrap();
        }

        let result = service.get_messages_between(sender_id, recipient_id, 10, 0).await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap().len(), 3);
    }

    #[tokio::test]
    #[ignore]
    async fn test_conversation_pair_ordering() {
        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();

        let pair1 = MessageService::make_conversation_pair(user1, user2);
        let pair2 = MessageService::make_conversation_pair(user2, user1);

        assert_eq!(pair1, pair2); // Should be same regardless of order
    }

    #[test]
    fn test_parse_status() {
        assert_eq!(MessageService::parse_status("pending"), KeyExchangeStatus::Pending);
        assert_eq!(MessageService::parse_status("completed"), KeyExchangeStatus::Completed);
        assert_eq!(MessageService::parse_status("failed"), KeyExchangeStatus::Failed);
        assert_eq!(MessageService::parse_status("invalid"), KeyExchangeStatus::Failed);
    }

    #[tokio::test]
    #[ignore]
    async fn test_upsert_public_key() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let user_id = create_test_user(&pool).await;

        let key1 = general_purpose::STANDARD.encode(&[20u8; 32]);
        service.register_public_key(user_id, &key1).await.unwrap();

        // Upsert with new key
        let key2 = general_purpose::STANDARD.encode(&[21u8; 32]);
        let result = service.register_public_key(user_id, &key2).await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap().public_key, key2);
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_messages_pagination() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let sender_id = create_test_user(&pool).await;
        let recipient_id = create_test_user(&pool).await;

        let sender_key = general_purpose::STANDARD.encode(&[22u8; 32]);
        service.register_public_key(sender_id, &sender_key).await.unwrap();

        // Send 5 messages
        for i in 0..5 {
            let content = general_purpose::STANDARD.encode(format!("msg {}", i).as_bytes());
            let nonce = general_purpose::STANDARD.encode(&[30u8 + i as u8; 24]);
            service.send_encrypted_message(sender_id, recipient_id, &content, &nonce).await.unwrap();
        }

        // Get first 2
        let page1 = service.get_messages_between(sender_id, recipient_id, 2, 0).await.unwrap();
        assert_eq!(page1.len(), 2);

        // Get next 2
        let page2 = service.get_messages_between(sender_id, recipient_id, 2, 2).await.unwrap();
        assert_eq!(page2.len(), 2);
    }

    #[tokio::test]
    #[ignore]
    async fn test_bidirectional_message_retrieval() {
        let pool = setup_test_pool().await;
        let service = MessageService::new(pool.clone());
        let user1 = create_test_user(&pool).await;
        let user2 = create_test_user(&pool).await;

        let key1 = general_purpose::STANDARD.encode(&[40u8; 32]);
        service.register_public_key(user1, &key1).await.unwrap();

        let content = general_purpose::STANDARD.encode(b"test");
        let nonce = general_purpose::STANDARD.encode(&[50u8; 24]);
        service.send_encrypted_message(user1, user2, &content, &nonce).await.unwrap();

        // Both users should see the message
        let msgs1 = service.get_messages_between(user1, user2, 10, 0).await.unwrap();
        let msgs2 = service.get_messages_between(user2, user1, 10, 0).await.unwrap();

        assert_eq!(msgs1.len(), 1);
        assert_eq!(msgs2.len(), 1);
        assert_eq!(msgs1[0].id, msgs2[0].id);
    }
}
