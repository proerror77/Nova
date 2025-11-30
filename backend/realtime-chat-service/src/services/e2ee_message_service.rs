//! E2EE Message Service
//!
//! Provides message storage and retrieval for end-to-end encrypted messages.
//! Key principle: Server NEVER has access to plaintext or encryption keys.
//!
//! ## Message Flow
//! 1. Client encrypts message with Megolm session key
//! 2. Client sends encrypted blob + session_id + message_index
//! 3. Server stores encrypted blob (cannot decrypt)
//! 4. Recipients fetch encrypted blob
//! 5. Recipients decrypt locally with their copy of the session key

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use uuid::Uuid;
use thiserror::Error;
use tracing::{debug, info, instrument};

#[derive(Debug, Error)]
pub enum E2eeMessageError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Message not found: {0}")]
    NotFound(Uuid),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Invalid session: {0}")]
    InvalidSession(String),
}

/// Encrypted message as stored in database
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct E2eeMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub sender_device_id: String,
    /// Megolm session ID used for encryption
    pub session_id: String,
    /// Base64-encoded Megolm ciphertext
    pub ciphertext: String,
    /// Message index in the Megolm ratchet
    pub message_index: u32,
    pub sequence_number: i64,
    pub created_at: DateTime<Utc>,
    /// Optional: message type (text, image, audio, etc.)
    pub message_type: Option<String>,
}

/// Request to send an E2EE message
#[derive(Debug, Deserialize)]
pub struct SendE2eeMessageRequest {
    pub conversation_id: Uuid,
    pub sender_device_id: String,
    pub session_id: String,
    pub ciphertext: String,
    pub message_index: u32,
    #[serde(default)]
    pub message_type: Option<String>,
    #[serde(default)]
    pub idempotency_key: Option<String>,
}

pub struct E2eeMessageService;

impl E2eeMessageService {
    /// Store an E2EE encrypted message
    ///
    /// The server stores the encrypted blob without any ability to decrypt.
    /// This is TRUE E2EE - the server is a dumb storage layer.
    #[instrument(skip(db, request))]
    pub async fn store_message(
        db: &PgPool,
        sender_id: Uuid,
        request: SendE2eeMessageRequest,
    ) -> Result<E2eeMessage, E2eeMessageError> {
        let id = Uuid::new_v4();

        // Verify sender is a member of the conversation
        let is_member = Self::is_conversation_member(db, request.conversation_id, sender_id).await?;
        if !is_member {
            return Err(E2eeMessageError::Unauthorized(
                "Sender is not a member of this conversation".into()
            ));
        }

        // Store the encrypted message with atomic sequence number
        let row = sqlx::query(
            r#"
            WITH next AS (
                INSERT INTO conversation_counters (conversation_id, last_seq)
                VALUES ($2, 1)
                ON CONFLICT (conversation_id)
                DO UPDATE SET last_seq = conversation_counters.last_seq + 1
                RETURNING last_seq
            )
            INSERT INTO messages (
                id,
                conversation_id,
                sender_id,
                content,
                message_type,
                idempotency_key,
                sequence_number,
                -- E2EE-specific fields
                sender_device_id,
                megolm_session_id,
                megolm_ciphertext,
                megolm_message_index,
                encryption_version
            )
            SELECT
                $1,
                $2,
                $3,
                '',  -- No plaintext content for E2EE messages
                $4,
                $5,
                next.last_seq,
                $6,
                $7,
                $8,
                $9,
                2    -- encryption_version = 2 indicates Megolm E2EE
            FROM next
            RETURNING id, conversation_id, sender_id, sequence_number, created_at, message_type
            "#,
        )
        .bind(id)
        .bind(request.conversation_id)
        .bind(sender_id)
        .bind(&request.message_type)
        .bind(&request.idempotency_key)
        .bind(&request.sender_device_id)
        .bind(&request.session_id)
        .bind(&request.ciphertext)
        .bind(request.message_index as i32)
        .fetch_one(db)
        .await?;

        let message = E2eeMessage {
            id: row.get("id"),
            conversation_id: row.get("conversation_id"),
            sender_id: row.get("sender_id"),
            sender_device_id: request.sender_device_id,
            session_id: request.session_id,
            ciphertext: request.ciphertext,
            message_index: request.message_index,
            sequence_number: row.get("sequence_number"),
            created_at: row.get("created_at"),
            message_type: row.get("message_type"),
        };

        info!(
            message_id = %message.id,
            conversation_id = %message.conversation_id,
            session_id = %message.session_id,
            "Stored E2EE message"
        );

        Ok(message)
    }

    /// Get E2EE messages for a conversation
    ///
    /// Returns encrypted blobs that must be decrypted client-side.
    #[instrument(skip(db))]
    pub async fn get_messages(
        db: &PgPool,
        conversation_id: Uuid,
        user_id: Uuid,
        limit: i64,
        before_sequence: Option<i64>,
    ) -> Result<Vec<E2eeMessage>, E2eeMessageError> {
        // Verify user is a member
        let is_member = Self::is_conversation_member(db, conversation_id, user_id).await?;
        if !is_member {
            return Err(E2eeMessageError::Unauthorized(
                "User is not a member of this conversation".into()
            ));
        }

        let limit = limit.min(200);

        let rows = if let Some(before_seq) = before_sequence {
            sqlx::query(
                r#"
                SELECT
                    id, conversation_id, sender_id, sender_device_id,
                    megolm_session_id, megolm_ciphertext, megolm_message_index,
                    sequence_number, created_at, message_type
                FROM messages
                WHERE conversation_id = $1
                  AND deleted_at IS NULL
                  AND encryption_version = 2
                  AND sequence_number < $2
                ORDER BY sequence_number DESC
                LIMIT $3
                "#,
            )
            .bind(conversation_id)
            .bind(before_seq)
            .bind(limit)
            .fetch_all(db)
            .await?
        } else {
            sqlx::query(
                r#"
                SELECT
                    id, conversation_id, sender_id, sender_device_id,
                    megolm_session_id, megolm_ciphertext, megolm_message_index,
                    sequence_number, created_at, message_type
                FROM messages
                WHERE conversation_id = $1
                  AND deleted_at IS NULL
                  AND encryption_version = 2
                ORDER BY sequence_number DESC
                LIMIT $2
                "#,
            )
            .bind(conversation_id)
            .bind(limit)
            .fetch_all(db)
            .await?
        };

        let messages: Vec<E2eeMessage> = rows
            .into_iter()
            .map(|row| E2eeMessage {
                id: row.get("id"),
                conversation_id: row.get("conversation_id"),
                sender_id: row.get("sender_id"),
                sender_device_id: row.get::<Option<String>, _>("sender_device_id").unwrap_or_default(),
                session_id: row.get::<Option<String>, _>("megolm_session_id").unwrap_or_default(),
                ciphertext: row.get::<Option<String>, _>("megolm_ciphertext").unwrap_or_default(),
                message_index: row.get::<Option<i32>, _>("megolm_message_index").unwrap_or(0) as u32,
                sequence_number: row.get("sequence_number"),
                created_at: row.get("created_at"),
                message_type: row.get("message_type"),
            })
            .collect();

        debug!(
            conversation_id = %conversation_id,
            count = messages.len(),
            "Retrieved E2EE messages"
        );

        Ok(messages)
    }

    /// Get messages since a specific sequence number (for sync)
    #[instrument(skip(db))]
    pub async fn get_messages_since(
        db: &PgPool,
        conversation_id: Uuid,
        user_id: Uuid,
        since_sequence: i64,
        limit: i64,
    ) -> Result<Vec<E2eeMessage>, E2eeMessageError> {
        let is_member = Self::is_conversation_member(db, conversation_id, user_id).await?;
        if !is_member {
            return Err(E2eeMessageError::Unauthorized(
                "User is not a member of this conversation".into()
            ));
        }

        let limit = limit.min(500);

        let rows = sqlx::query(
            r#"
            SELECT
                id, conversation_id, sender_id, sender_device_id,
                megolm_session_id, megolm_ciphertext, megolm_message_index,
                sequence_number, created_at, message_type
            FROM messages
            WHERE conversation_id = $1
              AND deleted_at IS NULL
              AND encryption_version = 2
              AND sequence_number > $2
            ORDER BY sequence_number ASC
            LIMIT $3
            "#,
        )
        .bind(conversation_id)
        .bind(since_sequence)
        .bind(limit)
        .fetch_all(db)
        .await?;

        let messages: Vec<E2eeMessage> = rows
            .into_iter()
            .map(|row| E2eeMessage {
                id: row.get("id"),
                conversation_id: row.get("conversation_id"),
                sender_id: row.get("sender_id"),
                sender_device_id: row.get::<Option<String>, _>("sender_device_id").unwrap_or_default(),
                session_id: row.get::<Option<String>, _>("megolm_session_id").unwrap_or_default(),
                ciphertext: row.get::<Option<String>, _>("megolm_ciphertext").unwrap_or_default(),
                message_index: row.get::<Option<i32>, _>("megolm_message_index").unwrap_or(0) as u32,
                sequence_number: row.get("sequence_number"),
                created_at: row.get("created_at"),
                message_type: row.get("message_type"),
            })
            .collect();

        Ok(messages)
    }

    /// Soft delete an E2EE message
    #[instrument(skip(db))]
    pub async fn delete_message(
        db: &PgPool,
        message_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), E2eeMessageError> {
        // Verify user is the sender
        let result = sqlx::query(
            r#"
            UPDATE messages
            SET deleted_at = NOW()
            WHERE id = $1 AND sender_id = $2
            RETURNING id
            "#,
        )
        .bind(message_id)
        .bind(user_id)
        .fetch_optional(db)
        .await?;

        if result.is_none() {
            return Err(E2eeMessageError::NotFound(message_id));
        }

        info!(message_id = %message_id, "Deleted E2EE message");

        Ok(())
    }

    /// Check if a user is a member of a conversation
    async fn is_conversation_member(
        db: &PgPool,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, E2eeMessageError> {
        let result = sqlx::query_scalar::<_, bool>(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM conversation_members
                WHERE conversation_id = $1 AND user_id = $2
            )
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_one(db)
        .await?;

        Ok(result)
    }

    /// Get unique session IDs used in a conversation
    /// Useful for clients to know which room keys they need
    #[instrument(skip(db))]
    pub async fn get_required_session_ids(
        db: &PgPool,
        conversation_id: Uuid,
        since_sequence: Option<i64>,
    ) -> Result<Vec<String>, E2eeMessageError> {
        let since = since_sequence.unwrap_or(0);

        let rows = sqlx::query_scalar::<_, String>(
            r#"
            SELECT DISTINCT megolm_session_id
            FROM messages
            WHERE conversation_id = $1
              AND deleted_at IS NULL
              AND encryption_version = 2
              AND megolm_session_id IS NOT NULL
              AND sequence_number > $2
            "#,
        )
        .bind(conversation_id)
        .bind(since)
        .fetch_all(db)
        .await?;

        Ok(rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Add integration tests
}
