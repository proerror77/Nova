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

use crate::models::message::Message as MessageRow;
use crate::services::conversation_service::PrivacyMode;
#[allow(deprecated)]
use crate::services::encryption::EncryptionService;
use chrono::Utc;
use deadpool_postgres::Pool;
use std::sync::Arc;
use uuid::Uuid;

pub struct MessageService;

impl MessageService {
    async fn fetch_conversation_privacy(
        db: &Pool,
        conversation_id: Uuid,
    ) -> Result<PrivacyMode, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("fetch privacy mode: {e}"))
        })?;

        let row = client
            .query_opt("SELECT privacy_mode::text FROM conversations WHERE id = $1", &[&conversation_id])
            .await
            .map_err(|e| {
                crate::error::AppError::StartServer(format!("fetch privacy mode: {e}"))
            })?;

        let mode: String = row
            .ok_or(crate::error::AppError::NotFound)?
            .get(0);
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
        plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<MessageRow, crate::error::AppError> {
        let id = Uuid::new_v4();

        // Note: E2E encryption columns removed in migration 0009
        // Using PostgreSQL TDE for at-rest encryption instead
        let content = String::from_utf8(plaintext.to_vec())
            .map_err(|e| crate::error::AppError::Config(format!("invalid utf8: {e}")))?;

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let row = client.query_one(
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
            RETURNING id, conversation_id, sender_id, content, sequence_number, idempotency_key, created_at
            "#,
            &[&id, &conversation_id, &sender_id, &content, &idempotency_key]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert msg: {e}")))?;

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
        })
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
    ) -> Result<Uuid, crate::error::AppError> {
        // Validate sender is a member of the conversation
        let is_member = super::conversation_service::ConversationService::is_member(
            db,
            conversation_id,
            sender_id,
        )
        .await?;

        if !is_member {
            return Err(crate::error::AppError::Config(
                "Sender is not a member of this conversation".into(),
            ));
        }

        // Validate plaintext is not empty
        if plaintext.is_empty() {
            return Err(crate::error::AppError::Config(
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
    ) -> Result<(Uuid, i64), crate::error::AppError> {
        let id = Uuid::new_v4();

        // Store audio metadata as JSON for client parsing
        // Schema note: Using content field for structured audio data
        let content = serde_json::json!({
            "type": "audio",
            "url": audio_url,
            "duration_ms": duration_ms,
            "codec": audio_codec
        }).to_string();

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let seq: i64 = client.query_one(
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
            RETURNING sequence_number
            "#,
            &[&id, &conversation_id, &sender_id, &content, &idempotency_key]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert audio msg: {e}")))?
        .get(0);

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
    ) -> Result<MessageRow, crate::error::AppError> {
        // 1. Insert into Nova DB first (primary storage)
        let message =
            Self::send_message_db(db, encryption, conversation_id, sender_id, plaintext, idempotency_key)
                .await?;

        // 2. Optionally send to Matrix (best-effort, non-blocking)
        if let Some(matrix) = matrix_client {
            // Get conversation participants for room creation
            let participants = match super::matrix_db::get_conversation_participants(db, conversation_id).await {
                Ok(p) => p,
                Err(e) => {
                    tracing::warn!(
                        error = %e,
                        conversation_id = %conversation_id,
                        "Failed to get conversation participants for Matrix room, skipping Matrix send"
                    );
                    return Ok(message);
                }
            };

            // Get or create Matrix room
            let room_id = match matrix.get_or_create_room(conversation_id, &participants).await {
                Ok(r) => r,
                Err(e) => {
                    tracing::error!(
                        error = %e,
                        conversation_id = %conversation_id,
                        "Failed to get/create Matrix room, message saved to DB only"
                    );
                    return Ok(message);
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

            // Send message to Matrix
            let content = String::from_utf8_lossy(plaintext).to_string();
            match matrix.send_message(conversation_id, &room_id, &content).await {
                Ok(event_id) => {
                    tracing::info!(
                        message_id = %message.id,
                        event_id = %event_id,
                        room_id = %room_id,
                        "Message sent to Matrix"
                    );

                    // Update message with Matrix event_id
                    if let Err(e) = super::matrix_db::update_message_matrix_event_id(
                        db,
                        message.id,
                        &event_id,
                    )
                    .await
                    {
                        tracing::warn!(
                            error = %e,
                            message_id = %message.id,
                            "Failed to update message with matrix_event_id"
                        );
                    }
                }
                Err(e) => {
                    tracing::error!(
                        error = %e,
                        message_id = %message.id,
                        room_id = %room_id,
                        "Failed to send message to Matrix, message saved to DB only"
                    );
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
    ) -> Result<(Uuid, i64), crate::error::AppError> {
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
            // Get conversation participants for room creation
            let participants = match super::matrix_db::get_conversation_participants(db, conversation_id).await {
                Ok(p) => p,
                Err(e) => {
                    tracing::warn!(
                        error = %e,
                        conversation_id = %conversation_id,
                        "Failed to get conversation participants for Matrix room, skipping Matrix send"
                    );
                    return Ok((message_id, seq));
                }
            };

            // Get or create Matrix room
            let room_id = match matrix.get_or_create_room(conversation_id, &participants).await {
                Ok(r) => r,
                Err(e) => {
                    tracing::error!(
                        error = %e,
                        conversation_id = %conversation_id,
                        "Failed to get/create Matrix room, audio message saved to DB only"
                    );
                    return Ok((message_id, seq));
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

            // Send audio as media to Matrix
            // Use audio_url as the media URL, extract filename
            let filename = audio_url.split('/').next_back().unwrap_or("audio.opus");
            // Set upload_to_matrix to true to enable full Matrix media upload
            // This uploads the media to Matrix server and sends as proper media message
            match matrix
                .send_media(conversation_id, &room_id, audio_url, "audio", filename, true)
                .await
            {
                Ok(event_id) => {
                    tracing::info!(
                        message_id = %message_id,
                        event_id = %event_id,
                        room_id = %room_id,
                        "Audio message sent to Matrix"
                    );

                    // Update message with Matrix event_id
                    if let Err(e) = super::matrix_db::update_message_matrix_event_id(
                        db,
                        message_id,
                        &event_id,
                    )
                    .await
                    {
                        tracing::warn!(
                            error = %e,
                            message_id = %message_id,
                            "Failed to update audio message with matrix_event_id"
                        );
                    }
                }
                Err(e) => {
                    tracing::error!(
                        error = %e,
                        message_id = %message_id,
                        room_id = %room_id,
                        "Failed to send audio to Matrix, message saved to DB only"
                    );
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
    ) -> Result<(), crate::error::AppError> {
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
    ) -> Result<(), crate::error::AppError> {
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
    ) -> Result<Vec<super::super::routes::messages::MessageDto>, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

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
        .map_err(|e| crate::error::AppError::StartServer(format!("history: {e}")))?;

        let mut out = Vec::with_capacity(rows.len());
        for r in rows {
            let id: Uuid = r.get("id");
            let sender_id: Uuid = r.get("sender_id");
            let seq: i64 = r.get("sequence_number");
            let created_at: chrono::DateTime<Utc> = r.get("created_at");
            let recalled_at: Option<chrono::DateTime<Utc>> = r.get("recalled_at");
            let edited_at: Option<chrono::DateTime<Utc>> = r.get("edited_at");
            let version_number: i64 = r.get("version_number");
            let content: String = r.get("content");

            out.push(super::super::routes::messages::MessageDto {
                id,
                sender_id,
                sequence_number: seq,
                created_at: created_at.to_rfc3339(),
                content,
                encrypted: false,
                encrypted_payload: None,
                nonce: None,
                recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                updated_at: edited_at.map(|t| t.to_rfc3339()),
                version_number: version_number as i32,
                message_type: None, // Column doesn't exist in schema
                reactions: Vec::new(),
                attachments: Vec::new(),
            });
        }
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
    ) -> Result<Vec<super::super::routes::messages::MessageDto>, crate::error::AppError> {
        use super::super::routes::messages::{MessageAttachment, MessageDto, MessageReaction};
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

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let messages = client.query(&query_sql, &[&conversation_id, &limit, &offset])
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("fetch messages: {e}")))?;

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
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch reactions: {e}")))?;

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
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch attachments: {e}")))?;

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

        // 4. Build final DTOs
        // Note: PostgreSQL TDE handles encryption transparently - no separate encrypted fields
        let result = messages
            .into_iter()
            .map(|r| {
                let id: Uuid = r.get("id");
                let sender_id: Uuid = r.get("sender_id");
                let seq: i64 = r.get("sequence_number");
                let created_at: chrono::DateTime<Utc> = r.get("created_at");
                let recalled_at: Option<chrono::DateTime<Utc>> = r.get("recalled_at");
                let edited_at: Option<chrono::DateTime<Utc>> = r.get("edited_at");
                let version_number: i32 = r.get("version_number");
                let content: String = r.get("content");

                MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content,
                    encrypted: use_encryption, // Indicates PostgreSQL TDE encryption
                    encrypted_payload: None,
                    nonce: None,
                    recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                    updated_at: edited_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type: None, // Column removed in schema migration
                    reactions: reactions_map.remove(&id).unwrap_or_default(),
                    attachments: attachments_map.remove(&id).unwrap_or_default(),
                }
            })
            .collect();

        Ok(result)
    }

    pub async fn update_message_db(
        db: &Pool,
        _encryption: &EncryptionService, // Encryption handled by PostgreSQL TDE
        message_id: Uuid,
        plaintext: &[u8],
    ) -> Result<(), crate::error::AppError> {
        let content_plain = String::from_utf8(plaintext.to_vec())
            .map_err(|e| crate::error::AppError::Config(format!("invalid utf8: {e}")))?;

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Schema note: Use only columns from migrations 0004 (base) and 0005 (content)
        // E2E encryption handled by PostgreSQL TDE - no separate encrypted columns
        client.execute(
            "UPDATE messages SET content = $1, version_number = version_number + 1, edited_at = NOW() WHERE id = $2",
            &[&content_plain, &message_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update msg: {e}")))?;

        Ok(())
    }

    pub async fn soft_delete_message_db(
        db: &Pool,
        message_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        client.execute("UPDATE messages SET deleted_at=NOW() WHERE id=$1", &[&message_id])
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("delete msg: {e}")))?;

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
        db: &Pool,
        conversation_id: Uuid,
        query: &str,
        limit: i64,
        offset: i64,
        sort_by: Option<&str>,
    ) -> Result<(Vec<super::super::routes::messages::MessageDto>, i64), crate::error::AppError>
    {
        let limit = limit.min(500); // Cap at 500 to prevent memory issues
        let sort_by = sort_by.unwrap_or("recent");

        let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;
        if matches!(privacy_mode, PrivacyMode::StrictE2e) {
            // Strict E2E conversations are not searchable on plaintext content.
            return Ok((Vec::new(), 0));
        }

        // ARCHITECTURE NOTE (2025-10-26):
        // Using PostgreSQL's native full-text search directly on messages.content
        // Requires GIN index on content_tsv (generated column with to_tsvector)
        // See: backend/messaging-service/migrations/0011_add_search_index.sql

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Get total count for pagination metadata
        let count_result = client.query_one(
            "SELECT COUNT(*) as total FROM messages m
             WHERE m.conversation_id = $1
               AND m.deleted_at IS NULL
               AND m.content IS NOT NULL
               AND m.content_tsv @@ plainto_tsquery('english', $2)",
            &[&conversation_id, &query]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("count search results: {e}")))?;
        let total: i64 = count_result.get("total");

        // Build sort clause based on sort_by parameter
        let (sort_clause, search_condition) = match sort_by {
            "oldest" => (
                "m.created_at ASC",
                "m.content IS NOT NULL AND m.content_tsv @@ plainto_tsquery('english', $2)",
            ),
            "relevance" => (
                "ts_rank(m.content_tsv, plainto_tsquery('english', $2)) DESC, m.created_at DESC",
                "m.content IS NOT NULL AND m.content_tsv @@ plainto_tsquery('english', $2)",
            ),
            "recent" => (
                "m.created_at DESC",
                "m.content IS NOT NULL AND m.content_tsv @@ plainto_tsquery('english', $2)",
            ),
            _ => (
                "m.created_at DESC",
                "m.content IS NOT NULL AND m.content_tsv @@ plainto_tsquery('english', $2)",
            ),
        };

        // Build the query with proper sorting - include all message fields
        // Schema note: Use only columns from migrations 0004 (base) and 0005 (content)
        let query_sql = format!(
            "SELECT m.id, m.sender_id, \
                    m.sequence_number AS sequence_number, \
                    m.created_at, m.content, m.recalled_at, m.edited_at, m.version_number \
             FROM messages m \
             WHERE m.conversation_id = $1 \
               AND m.deleted_at IS NULL \
               AND {} \
             ORDER BY {} \
             LIMIT $3 OFFSET $4",
            search_condition, sort_clause
        );

        let rows = client.query(&query_sql, &[&conversation_id, &query, &limit, &offset])
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("search: {e}")))?;

        let out = rows
            .into_iter()
            .map(|r| {
                let id: Uuid = r.get("id");
                let sender_id: Uuid = r.get("sender_id");
                let seq: i64 = r.get("sequence_number");
                let created_at: chrono::DateTime<Utc> = r.get("created_at");
                let content: String = r.get("content");
                let recalled_at: Option<chrono::DateTime<Utc>> = r.get("recalled_at");
                let edited_at: Option<chrono::DateTime<Utc>> = r.get("edited_at");
                let version_number: i32 = r.get("version_number");

                super::super::routes::messages::MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content,
                    encrypted: false,
                    encrypted_payload: None,
                    nonce: None,
                    recalled_at: recalled_at.map(|dt| dt.to_rfc3339()),
                    updated_at: edited_at.map(|dt| dt.to_rfc3339()),
                    version_number,
                    message_type: None, // Column removed in schema migration
                    reactions: vec![],
                    attachments: vec![],
                }
            })
            .collect();
        Ok((out, total))
    }
}
