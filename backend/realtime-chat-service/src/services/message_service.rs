//! # Message Service
//!
//! Handles plaintext message storage with PostgreSQL TDE (encryption_version=0).
//!
//! ## Note on EncryptionService Parameter
//!
//! Many functions accept `&EncryptionService` but don't use it. This is for API
//! compatibility - callers pass `state.encryption` which is also used by
//! `routes/conversations.rs` for legacy key derivation.
//!
//! The parameter is marked with `_encryption` to indicate it's unused.
//! A future refactor could remove this parameter once the legacy key
//! derivation endpoint is deprecated.
//!
//! ## For E2EE Messages
//!
//! Use `E2eeMessageService` with `MegolmService` for encryption_version=2 messages.

// Allow deprecated EncryptionService - kept for API compatibility (see module docs)
#![allow(deprecated)]

use crate::error::AppError;
use crate::models::message::Message as MessageRow;
use crate::routes::messages::{MessageAttachment, MessageDto, MessageReaction};
use crate::services::conversation_service::PrivacyMode;
use crate::services::encryption::EncryptionService;
use chrono::Utc;
use deadpool_postgres::{Object, Pool};
use matrix_sdk::ruma::OwnedRoomId;
use std::sync::Arc;
use uuid::Uuid;

pub struct MessageService;

/// Result of preparing a Matrix room for message sending
struct MatrixRoomContext {
    room_id: OwnedRoomId,
}

impl MessageService {
    /// Extracts filename from a URL, handling query parameters and fragments.
    /// Returns default_name if extraction fails.
    fn extract_filename_from_url<'a>(url: &'a str, default_name: &'a str) -> &'a str {
        url.split('/')
            .next_back()
            .unwrap_or(default_name)
            .split('?')
            .next()
            .unwrap_or(default_name)
            .split('#')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(default_name)
    }

    /// Gets a database client from the pool with standardized error handling.
    async fn get_db_client(db: &Pool, context: &str) -> Result<Object, AppError> {
        db.get()
            .await
            .map_err(|e| AppError::StartServer(format!("{context}: {e}")))
    }

    /// Constructs a MessageDto from a database row.
    /// Used by get_message_history_db, get_message_history_with_details, and search_messages.
    fn row_to_message_dto(
        row: &tokio_postgres::Row,
        reactions: Vec<MessageReaction>,
        attachments: Vec<MessageAttachment>,
        encrypted: bool,
    ) -> MessageDto {
        let id: Uuid = row.get("id");
        let sender_id: Uuid = row.get("sender_id");
        let seq: i64 = row.get("sequence_number");
        let created_at: chrono::DateTime<Utc> = row.get("created_at");
        let recalled_at: Option<chrono::DateTime<Utc>> = row.get("recalled_at");
        let edited_at: Option<chrono::DateTime<Utc>> = row.get("edited_at");
        let version_number: i64 = row.get("version_number");
        let content: String = row.get("content");

        MessageDto {
            id,
            sender_id,
            sequence_number: seq,
            created_at: created_at.to_rfc3339(),
            content,
            encrypted,
            encrypted_payload: None,
            nonce: None,
            recalled_at: recalled_at.map(|t| t.to_rfc3339()),
            updated_at: edited_at.map(|t| t.to_rfc3339()),
            version_number: version_number as i32,
            message_type: None,
            reactions,
            attachments,
        }
    }

    /// Updates message with Matrix event_id, logging any errors.
    /// Used after successfully sending a message to Matrix.
    async fn save_matrix_event_id(db: &Pool, message_id: Uuid, event_id: &str) {
        if let Err(e) = super::matrix_db::update_message_matrix_event_id(db, message_id, event_id).await {
            tracing::warn!(
                error = %e,
                message_id = %message_id,
                "Failed to update message with matrix_event_id"
            );
        }
    }

    /// Prepares a Matrix room for sending messages.
    /// Gets conversation participants, creates/gets room, and saves mapping.
    /// Returns None if any step fails (errors are logged).
    async fn prepare_matrix_room(
        db: &Pool,
        matrix: &super::matrix_client::MatrixClient,
        conversation_id: Uuid,
    ) -> Option<MatrixRoomContext> {
        // Get conversation participants for room creation
        let participants = match super::matrix_db::get_conversation_participants(db, conversation_id).await {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    conversation_id = %conversation_id,
                    "Failed to get conversation participants for Matrix room"
                );
                return None;
            }
        };

        // Get or create Matrix room
        let room_id = match matrix.get_or_create_room(conversation_id, &participants).await {
            Ok(r) => r,
            Err(e) => {
                tracing::error!(
                    error = %e,
                    conversation_id = %conversation_id,
                    "Failed to get/create Matrix room"
                );
                return None;
            }
        };

        // Save room mapping to DB
        if let Err(e) = super::matrix_db::save_room_mapping(db, conversation_id, &room_id).await {
            tracing::warn!(
                error = %e,
                conversation_id = %conversation_id,
                room_id = %room_id,
                "Failed to save room mapping to DB"
            );
        }

        Some(MatrixRoomContext { room_id })
    }

    async fn fetch_conversation_privacy(
        db: &Pool,
        conversation_id: Uuid,
    ) -> Result<PrivacyMode, AppError> {
        let client = Self::get_db_client(db, "fetch privacy mode").await?;

        let row = client
            .query_opt(
                "SELECT privacy_mode::text FROM conversations WHERE id = $1 AND deleted_at IS NULL",
                &[&conversation_id],
            )
            .await
            .map_err(|e| AppError::StartServer(format!("fetch privacy mode: {e}")))?;

        let mode: String = row.ok_or(AppError::NotFound)?.get(0);
        let privacy = match mode.as_str() {
            "strict_e2e" => PrivacyMode::StrictE2e,
            "search_enabled" => PrivacyMode::SearchEnabled,
            _ => PrivacyMode::StrictE2e,
        };

        Ok(privacy)
    }

    // NOTE (2025-10-26): Removed upsert_search_index and delete_search_index functions
    // These were maintaining a separate message_search_index table (dual-path indexing)
    // We now rely exclusively on PostgreSQL's native full-text search on messages.content
    // This simplifies the architecture and eliminates potential data inconsistencies

    pub async fn send_message_db(
        db: &Pool,
        _encryption: &EncryptionService, // Encryption handled by PostgreSQL TDE
        conversation_id: Uuid,
        sender_id: Uuid,
        _plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<MessageRow, AppError> {
        let id = Uuid::new_v4();

        // Matrix-first architecture: Nova DB stores metadata only.
        // Do NOT persist message plaintext in Nova DB.
        let content = "";

        let client = Self::get_db_client(db, "send message").await?;

        // Keep conversations.updated_at and conversations.last_message_id in sync with message writes.
        // Without this, conversation listings and "last message" previews drift from reality.
        let row = client
            .query_one(
                r#"
                WITH next AS (
                    INSERT INTO conversation_counters (conversation_id, last_seq)
                    VALUES ($2, 1)
                    ON CONFLICT (conversation_id)
                    DO UPDATE SET last_seq = conversation_counters.last_seq + 1
                    RETURNING last_seq
                ),
                ins AS (
                    INSERT INTO messages (
                        id,
                        conversation_id,
                        sender_id,
                        content,
                        idempotency_key,
                        sequence_number
                    )
                    SELECT
                        $1,
                        $2,
                        $3,
                        $4,
                        $5,
                        next.last_seq
                    FROM next
                    RETURNING id, conversation_id, sender_id, content, sequence_number, idempotency_key, created_at, matrix_event_id
                ),
                upd AS (
                    UPDATE conversations c
                    SET
                        updated_at = ins.created_at,
                        last_message_id = ins.id
                    FROM ins
                    WHERE c.id = ins.conversation_id
                      AND c.deleted_at IS NULL
                )
                SELECT id, conversation_id, sender_id, content, sequence_number, idempotency_key, created_at, matrix_event_id
                FROM ins
                "#,
                &[&id, &conversation_id, &sender_id, &content, &idempotency_key],
            )
            .await
            .map_err(|e| AppError::StartServer(format!("insert msg: {e}")))?;

        Ok(MessageRow {
            id: row.get(0),
            conversation_id: row.get(1),
            sender_id: row.get(2),
            content: row.get(3),
            sequence_number: row.get(4),
            idempotency_key: row.get(5),
            created_at: row.get(6),
            edited_at: None,
            deleted_at: None,
            reaction_count: 0,
            version_number: 1,
            recalled_at: None,
            matrix_event_id: row.get(7),
        })
    }

    /// Store an inbound Matrix event as a Nova DB metadata row.
    /// Returns Ok(None) if a row with the same matrix_event_id already exists.
    pub async fn store_matrix_message_metadata_db(
        db: &Pool,
        conversation_id: Uuid,
        sender_id: Uuid,
        matrix_event_id: &str,
    ) -> Result<Option<MessageRow>, AppError> {
        let id = Uuid::new_v4();
        let content = "";

        let client = Self::get_db_client(db, "store matrix message metadata").await?;

        let row = client
            .query_opt(
                r#"
                WITH next AS (
                    INSERT INTO conversation_counters (conversation_id, last_seq)
                    VALUES ($2, 1)
                    ON CONFLICT (conversation_id)
                    DO UPDATE SET last_seq = conversation_counters.last_seq + 1
                    RETURNING last_seq
                ),
                ins AS (
                    INSERT INTO messages (
                        id,
                        conversation_id,
                        sender_id,
                        content,
                        idempotency_key,
                        sequence_number,
                        matrix_event_id
                    )
                    SELECT
                        $1,
                        $2,
                        $3,
                        $4,
                        NULL,
                        next.last_seq,
                        $5
                    FROM next
                    ON CONFLICT (matrix_event_id) WHERE matrix_event_id IS NOT NULL DO NOTHING
                    RETURNING id, conversation_id, sender_id, content, sequence_number, created_at, matrix_event_id
                ),
                upd AS (
                    UPDATE conversations c
                    SET
                        updated_at = ins.created_at,
                        last_message_id = ins.id
                    FROM ins
                    WHERE c.id = ins.conversation_id
                      AND c.deleted_at IS NULL
                )
                SELECT id, conversation_id, sender_id, content, sequence_number, created_at, matrix_event_id
                FROM ins
                "#,
                &[&id, &conversation_id, &sender_id, &content, &matrix_event_id],
            )
            .await
            .map_err(|e| AppError::StartServer(format!("insert matrix msg: {e}")))?;

        let Some(row) = row else {
            return Ok(None);
        };

        Ok(Some(MessageRow {
            id: row.get(0),
            conversation_id: row.get(1),
            sender_id: row.get(2),
            content: row.get(3),
            sequence_number: row.get(4),
            idempotency_key: None,
            created_at: row.get(5),
            edited_at: None,
            deleted_at: None,
            reaction_count: 0,
            version_number: 1,
            recalled_at: None,
            matrix_event_id: row.get(6),
        }))
    }
    /// Send a message to a conversation (wrapper for send_message_db)
    /// Note: This is a simplified version. Use send_message_db directly for full control.
    /// Returns: message ID
    pub async fn send_message(
        db: &Pool,
        encryption: &EncryptionService,
        conversation_id: Uuid,
        sender_id: Uuid,
        plaintext: &[u8],
    ) -> Result<Uuid, AppError> {
        // Validate sender is a member of the conversation
        let is_member = super::conversation_service::ConversationService::is_member(
            db,
            conversation_id,
            sender_id,
        )
        .await?;

        if !is_member {
            return Err(AppError::Config(
                "Sender is not a member of this conversation".into(),
            ));
        }

        // Validate plaintext is not empty
        if plaintext.is_empty() {
            return Err(AppError::Config(
                "Message content cannot be empty".into(),
            ));
        }

        // Send message without idempotency key (for simple use cases)
        let message =
            Self::send_message_db(db, encryption, conversation_id, sender_id, plaintext, None)
                .await?;

        Ok(message.id)
    }

    /// Send an audio message to a conversation
    /// Stores audio metadata as JSON in content field for client parsing
    /// Returns: (message_id, sequence_number)
    #[allow(clippy::too_many_arguments)]
    pub async fn send_audio_message_db(
        db: &Pool,
        _encryption: &EncryptionService, // Encryption handled by PostgreSQL TDE
        conversation_id: Uuid,
        sender_id: Uuid,
        audio_url: &str,
        duration_ms: u32,
        audio_codec: &str,
        idempotency_key: Option<&str>,
    ) -> Result<(Uuid, i64), AppError> {
        let id = Uuid::new_v4();

        // Matrix-first architecture: Nova DB stores metadata only.
        // Do NOT persist audio URL or payload in Nova DB.
        let _ = (audio_url, duration_ms, audio_codec); // keep signature stable for now
        let content = "";

        let client = Self::get_db_client(db, "send audio message").await?;

        let row = client
            .query_one(
                r#"
                WITH next AS (
                    INSERT INTO conversation_counters (conversation_id, last_seq)
                    VALUES ($2, 1)
                    ON CONFLICT (conversation_id)
                    DO UPDATE SET last_seq = conversation_counters.last_seq + 1
                    RETURNING last_seq
                ),
                ins AS (
                    INSERT INTO messages (
                        id,
                        conversation_id,
                        sender_id,
                        content,
                        idempotency_key,
                        sequence_number
                    )
                    SELECT
                        $1,
                        $2,
                        $3,
                        $4,
                        $5,
                        next.last_seq
                    FROM next
                    RETURNING sequence_number, created_at
                ),
                upd AS (
                    UPDATE conversations c
                    SET
                        updated_at = ins.created_at,
                        last_message_id = $1
                    FROM ins
                    WHERE c.id = $2
                      AND c.deleted_at IS NULL
                )
                SELECT sequence_number, created_at FROM ins
                "#,
                &[&id, &conversation_id, &sender_id, &content, &idempotency_key],
            )
            .await
            .map_err(|e| AppError::StartServer(format!("insert audio msg: {e}")))?;

        let seq: i64 = row.get(0);

        Ok((id, seq))
    }

    /// Send a message with Matrix integration (dual-write pattern)
    /// Sends to Nova DB first, then optionally to Matrix homeserver
    /// Matrix failures are logged but do not block the message send
    pub async fn send_message_with_matrix(
        db: &Pool,
        encryption: &EncryptionService,
        matrix_client: Option<Arc<super::matrix_client::MatrixClient>>,
        conversation_id: Uuid,
        sender_id: Uuid,
        plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<MessageRow, AppError> {
        // 1. Insert into Nova DB first (primary storage)
        let mut message =
            Self::send_message_db(db, encryption, conversation_id, sender_id, plaintext, idempotency_key)
                .await?;

        // 2. Optionally send to Matrix (best-effort, non-blocking)
        if let Some(matrix) = matrix_client {
            if let Some(ctx) = Self::prepare_matrix_room(db, &matrix, conversation_id).await {
                // Send message to Matrix
                let content = String::from_utf8_lossy(plaintext).to_string();
                match matrix.send_message(conversation_id, ctx.room_id.as_ref(), &content).await {
                    Ok(event_id) => {
                        tracing::info!(
                            message_id = %message.id,
                            event_id = %event_id,
                            room_id = %ctx.room_id,
                            "Message sent to Matrix"
                        );
                        Self::save_matrix_event_id(db, message.id, &event_id).await;
                        message.matrix_event_id = Some(event_id);
                    }
                    Err(e) => {
                        tracing::error!(
                            error = %e,
                            message_id = %message.id,
                            room_id = %ctx.room_id,
                            "Failed to send message to Matrix, message saved to DB only"
                        );
                    }
                }
            }
        }

        Ok(message)
    }

    /// Send an audio message with Matrix integration (dual-write pattern)
    /// Sends to Nova DB first, then optionally to Matrix homeserver as media
    /// Matrix failures are logged but do not block the message send
    #[allow(clippy::too_many_arguments)]
    pub async fn send_audio_message_with_matrix(
        db: &Pool,
        encryption: &EncryptionService,
        matrix_client: Option<Arc<super::matrix_client::MatrixClient>>,
        conversation_id: Uuid,
        sender_id: Uuid,
        audio_url: &str,
        duration_ms: u32,
        audio_codec: &str,
        idempotency_key: Option<&str>,
    ) -> Result<(Uuid, i64), AppError> {
        // 1. Insert into Nova DB first (primary storage)
        let (message_id, seq) = Self::send_audio_message_db(
            db,
            encryption,
            conversation_id,
            sender_id,
            audio_url,
            duration_ms,
            audio_codec,
            idempotency_key,
        )
        .await?;

        // 2. Optionally send to Matrix (best-effort, non-blocking)
        if let Some(matrix) = matrix_client {
            if let Some(ctx) = Self::prepare_matrix_room(db, &matrix, conversation_id).await {
                // Send audio as media to Matrix
                let filename = Self::extract_filename_from_url(audio_url, "audio.opus");
                // Set upload_to_matrix to true to enable full Matrix media upload
                // This uploads the media to Matrix server and sends as proper media message
                match matrix
                    .send_media(conversation_id, ctx.room_id.as_ref(), audio_url, "audio", filename, true)
                    .await
                {
                    Ok(event_id) => {
                        tracing::info!(
                            message_id = %message_id,
                            event_id = %event_id,
                            room_id = %ctx.room_id,
                            "Audio message sent to Matrix"
                        );
                        Self::save_matrix_event_id(db, message_id, &event_id).await;
                    }
                    Err(e) => {
                        tracing::error!(
                            error = %e,
                            message_id = %message_id,
                            room_id = %ctx.room_id,
                            "Failed to send audio to Matrix, message saved to DB only"
                        );
                    }
                }
            }
        }

        Ok((message_id, seq))
    }

    /// Update a message with Matrix integration
    /// Updates Nova DB first, then sends edit event to Matrix
    /// Matrix failures are logged but do not block the update
    pub async fn update_message_with_matrix(
        db: &Pool,
        encryption: &EncryptionService,
        matrix_client: Option<Arc<super::matrix_client::MatrixClient>>,
        message_id: Uuid,
        plaintext: &[u8],
    ) -> Result<(), AppError> {
        // 1. Update Nova DB first (primary storage)
        Self::update_message_db(db, encryption, message_id, plaintext).await?;

        // 2. Optionally send edit to Matrix (best-effort, non-blocking)
        if let Some(matrix) = matrix_client {
            // Get Matrix event_id and room_id for this message
            match super::matrix_db::get_matrix_info(db, message_id).await {
                Ok((Some(event_id), Some(room_id))) => {
                    let new_content = String::from_utf8_lossy(plaintext).to_string();
                    if let Err(e) = matrix.edit_message(&room_id, &event_id, &new_content).await {
                        tracing::error!(
                            error = %e,
                            message_id = %message_id,
                            event_id = %event_id,
                            "Failed to edit message in Matrix, DB updated successfully"
                        );
                    } else {
                        tracing::info!(
                            message_id = %message_id,
                            event_id = %event_id,
                            "Message edited in Matrix"
                        );
                    }
                }
                Ok((None, _)) | Ok((Some(_), None)) => {
                    tracing::debug!(
                        message_id = %message_id,
                        "Message has no complete Matrix info, skipping Matrix edit"
                    );
                }
                Err(e) => {
                    tracing::warn!(
                        error = %e,
                        message_id = %message_id,
                        "Failed to get Matrix info for message, skipping Matrix edit"
                    );
                }
            }
        }

        Ok(())
    }

    /// Soft delete a message with Matrix integration
    /// Deletes from Nova DB first, then sends redaction to Matrix
    /// Matrix failures are logged but do not block the deletion
    pub async fn soft_delete_message_with_matrix(
        db: &Pool,
        matrix_client: Option<Arc<super::matrix_client::MatrixClient>>,
        message_id: Uuid,
        reason: Option<&str>,
    ) -> Result<(), AppError> {
        // 1. Soft delete in Nova DB first (primary storage)
        Self::soft_delete_message_db(db, message_id).await?;

        // 2. Optionally redact in Matrix (best-effort, non-blocking)
        if let Some(matrix) = matrix_client {
            // Get Matrix event_id and room_id for this message
            match super::matrix_db::get_matrix_info(db, message_id).await {
                Ok((Some(event_id), Some(room_id))) => {
                    if let Err(e) = matrix.delete_message(&room_id, &event_id, reason).await {
                        tracing::error!(
                            error = %e,
                            message_id = %message_id,
                            event_id = %event_id,
                            "Failed to redact message in Matrix, DB deleted successfully"
                        );
                    } else {
                        tracing::info!(
                            message_id = %message_id,
                            event_id = %event_id,
                            "Message redacted in Matrix"
                        );
                    }
                }
                Ok((None, _)) | Ok((Some(_), None)) => {
                    tracing::debug!(
                        message_id = %message_id,
                        "Message has no complete Matrix info, skipping Matrix redaction"
                    );
                }
                Err(e) => {
                    tracing::warn!(
                        error = %e,
                        message_id = %message_id,
                        "Failed to get Matrix info for message, skipping Matrix redaction"
                    );
                }
            }
        }

        Ok(())
    }

    pub async fn get_message_history_db(
        db: &Pool,
        conversation_id: Uuid,
    ) -> Result<Vec<MessageDto>, AppError> {
        let client = Self::get_db_client(db, "get message history").await?;

        // Note: E2E columns removed in migration 0009, message_type never existed
        let rows = client.query(
            r#"SELECT id,
                      sender_id,
                      sequence_number,
                      created_at,
                      recalled_at,
                      edited_at,
                      version_number,
                      content
               FROM messages
               WHERE conversation_id = $1 AND deleted_at IS NULL
               ORDER BY created_at ASC
               LIMIT 200"#,
            &[&conversation_id]
        )
        .await
        .map_err(|e| AppError::StartServer(format!("history: {e}")))?;

        let out = rows
            .iter()
            .map(|r| Self::row_to_message_dto(r, Vec::new(), Vec::new(), false))
            .collect();
        Ok(out)
    }

    /// Get message history with full details (reactions, attachments)
    pub async fn get_message_history_with_details(
        db: &Pool,
        _encryption: &EncryptionService,
        conversation_id: Uuid,
        user_id: Uuid,
        limit: i64,
        offset: i64,
        include_recalled: bool,
    ) -> Result<Vec<MessageDto>, AppError> {
        use std::collections::HashMap;

        let limit = limit.min(200); // Cap at 200
        let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;
        let use_encryption = matches!(privacy_mode, PrivacyMode::StrictE2e);

        // Build WHERE clause based on include_recalled
        let where_clause = if include_recalled {
            "WHERE conversation_id = $1 AND deleted_at IS NULL"
        } else {
            "WHERE conversation_id = $1 AND deleted_at IS NULL AND recalled_at IS NULL"
        };

        // 1. Fetch messages
        // Schema note: Use only columns from migrations 0004 (base) and 0005 (content)
        // E2E encryption handled by PostgreSQL TDE - no content_encrypted/content_nonce columns
        let query_sql = format!(
            r#"SELECT id,
                      sender_id,
                      sequence_number,
                      created_at,
                      recalled_at,
                      edited_at,
                      version_number,
                      content
               FROM messages
               {}
               ORDER BY created_at ASC
               LIMIT $2 OFFSET $3"#,
            where_clause
        );

        let client = Self::get_db_client(db, "get message history with details").await?;

        let messages = client.query(&query_sql, &[&conversation_id, &limit, &offset])
            .await
            .map_err(|e| AppError::StartServer(format!("fetch messages: {e}")))?;

        if messages.is_empty() {
            return Ok(vec![]);
        }

        let message_ids: Vec<Uuid> = messages.iter().map(|r| r.get("id")).collect();

        // 2. Fetch reactions for all messages (aggregated by emoji)
        let reactions_query = client.query(
            r#"
            SELECT
                message_id,
                emoji,
                COUNT(*) as count,
                BOOL_OR(user_id = $1) as user_reacted
            FROM message_reactions
            WHERE message_id = ANY($2)
            GROUP BY message_id, emoji
            "#,
            &[&user_id, &message_ids]
        )
        .await
        .map_err(|e| AppError::StartServer(format!("fetch reactions: {e}")))?;

        // Group reactions by message_id
        let mut reactions_map: HashMap<Uuid, Vec<MessageReaction>> = HashMap::new();
        for row in reactions_query {
            let message_id: Uuid = row.get("message_id");
            let emoji: String = row.get("emoji");
            let count: i64 = row.get("count");
            let user_reacted: bool = row.get("user_reacted");

            reactions_map
                .entry(message_id)
                .or_default()
                .push(MessageReaction {
                    emoji,
                    count,
                    user_reacted,
                });
        }

        // 3. Fetch attachments for all messages
        let attachments_query = client.query(
            "SELECT message_id, id, file_name, file_type, file_size, s3_key \
             FROM message_attachments \
             WHERE message_id = ANY($1)",
            &[&message_ids]
        )
        .await
        .map_err(|e| AppError::StartServer(format!("fetch attachments: {e}")))?;

        // Group attachments by message_id
        let mut attachments_map: HashMap<Uuid, Vec<MessageAttachment>> = HashMap::new();
        for row in attachments_query {
            let message_id: Uuid = row.get("message_id");
            let id: Uuid = row.get("id");
            let file_name: String = row.get("file_name");
            let file_type: Option<String> = row.get("file_type");
            let file_size: i32 = row.get("file_size");
            let s3_key: String = row.get("s3_key");

            attachments_map
                .entry(message_id)
                .or_default()
                .push(MessageAttachment {
                    id,
                    file_name,
                    file_type,
                    file_size,
                    s3_key,
                });
        }

        // 4. Build final DTOs using helper
        // Note: PostgreSQL TDE handles encryption transparently - no separate encrypted fields
        let result = messages
            .iter()
            .map(|r| {
                let id: Uuid = r.get("id");
                let reactions = reactions_map.remove(&id).unwrap_or_default();
                let attachments = attachments_map.remove(&id).unwrap_or_default();
                Self::row_to_message_dto(r, reactions, attachments, use_encryption)
            })
            .collect();

        Ok(result)
    }

    pub async fn update_message_db(
        db: &Pool,
        _encryption: &EncryptionService, // Encryption handled by PostgreSQL TDE
        message_id: Uuid,
        _plaintext: &[u8],
    ) -> Result<(), AppError> {
        let client = Self::get_db_client(db, "update message").await?;

        // Matrix-first architecture: message content lives in Matrix.
        // Keep only metadata (edited_at + version_number) in Nova DB.
        client.execute(
            "UPDATE messages SET version_number = version_number + 1, edited_at = NOW() WHERE id = $1",
            &[&message_id],
        )
        .await
        .map_err(|e| AppError::StartServer(format!("update msg: {e}")))?;

        Ok(())
    }

    pub async fn soft_delete_message_db(
        db: &Pool,
        message_id: Uuid,
    ) -> Result<(), AppError> {
        let client = Self::get_db_client(db, "soft delete message").await?;

        client.execute("UPDATE messages SET deleted_at=NOW() WHERE id=$1", &[&message_id])
            .await
            .map_err(|e| AppError::StartServer(format!("delete msg: {e}")))?;

        // No separate search index to maintain; FTS uses generated content_tsv

        Ok(())
    }

    /// Search messages in a conversation by query string using full-text search
    ///
    /// # Arguments
    /// * `conversation_id` - The conversation to search in
    /// * `query` - Search query string
    /// * `limit` - Maximum number of results to return
    /// * `offset` - Number of results to skip for pagination
    /// * `sort_by` - Sort order: 'recent' (default), 'oldest', 'relevance'
    pub async fn search_messages(
        _db: &Pool,
        conversation_id: Uuid,
        query: &str,
        limit: i64,
        offset: i64,
        sort_by: Option<&str>,
    ) -> Result<(Vec<MessageDto>, i64), AppError>
    {
        let _ = (conversation_id, query, limit, offset, sort_by);
        // Matrix-first architecture: Nova DB does not store plaintext content, so search is not supported.
        Ok((Vec::new(), 0))
    }
}
