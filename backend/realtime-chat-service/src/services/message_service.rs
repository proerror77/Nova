use crate::models::message::Message as MessageRow;
use crate::services::conversation_service::PrivacyMode;
use crate::services::encryption::EncryptionService;
use base64::{engine::general_purpose, Engine as _};
use chrono::Utc;
use sqlx::{Pool, Postgres, Row};
use std::sync::Arc;
use uuid::Uuid;

pub struct MessageService;

impl MessageService {
    async fn fetch_conversation_privacy(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<PrivacyMode, crate::error::AppError> {
        let mode: Option<String> =
            sqlx::query_scalar("SELECT privacy_mode::text FROM conversations WHERE id = $1")
                .bind(conversation_id)
                .fetch_optional(db)
                .await
                .map_err(|e| {
                    crate::error::AppError::StartServer(format!("fetch privacy mode: {e}"))
                })?;

        let mode = mode.ok_or(crate::error::AppError::NotFound)?;
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
        db: &Pool<Postgres>,
        encryption: &EncryptionService,
        conversation_id: Uuid,
        sender_id: Uuid,
        plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<MessageRow, crate::error::AppError> {
        let id = Uuid::new_v4();
        let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;

        let content_string = String::from_utf8(plaintext.to_vec())
            .map_err(|e| crate::error::AppError::Config(format!("invalid utf8: {e}")))?;

        let (content, content_encrypted, content_nonce, encryption_version) =
            if matches!(privacy_mode, PrivacyMode::StrictE2e) {
                let (ciphertext, nonce) = encryption.encrypt(conversation_id, plaintext)?;
                (String::new(), Some(ciphertext), Some(nonce.to_vec()), 1)
            } else {
                (content_string.clone(), None, None, 0)
            };

        let encrypted_slice = content_encrypted.as_deref();
        let nonce_slice = content_nonce.as_deref();

        let row = sqlx::query_as::<_, (Uuid, Uuid, Uuid, String, Option<Vec<u8>>, Option<Vec<u8>>, i32, i64, Option<String>, chrono::DateTime<Utc>)>(
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
                content_encrypted,
                content_nonce,
                encryption_version,
                idempotency_key,
                sequence_number
            )
            SELECT
                $1,
                $2,
                $3,
                $4,
                $5,
                $6,
                $7,
                $8,
                next.last_seq
            FROM next
            RETURNING id, conversation_id, sender_id, content, content_encrypted, content_nonce, encryption_version, sequence_number, idempotency_key, created_at
            "#,
        )
        .bind(id)
        .bind(conversation_id)
        .bind(sender_id)
        .bind(&content)
        .bind(encrypted_slice)
        .bind(nonce_slice)
        .bind(encryption_version)
        .bind(idempotency_key)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert msg: {e}")))?;

        Ok(MessageRow {
            id: row.0,
            conversation_id: row.1,
            sender_id: row.2,
            content: row.3,
            content_encrypted: row.4,
            content_nonce: row.5,
            encryption_version: row.6,
            sequence_number: row.7,
            idempotency_key: row.8,
            created_at: row.9,
            updated_at: None,
            edited_at: None,
            deleted_at: None,
            reaction_count: 0,
        })
    }
    /// Send a message to a conversation (wrapper for send_message_db)
    /// Note: This is a simplified version. Use send_message_db directly for full control.
    /// Returns: message ID
    pub async fn send_message(
        db: &Pool<Postgres>,
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
    /// Stores audio metadata (codec, duration) alongside message
    /// Returns: (message_id, sequence_number)
    #[allow(clippy::too_many_arguments)]
    pub async fn send_audio_message_db(
        db: &Pool<Postgres>,
        encryption: &EncryptionService,
        conversation_id: Uuid,
        sender_id: Uuid,
        audio_url: &str,
        duration_ms: u32,
        audio_codec: &str,
        idempotency_key: Option<&str>,
    ) -> Result<(Uuid, i64), crate::error::AppError> {
        let id = Uuid::new_v4();

        // For compatibility: store audio URL in `content` and add metadata columns when present
        let _ = idempotency_key; // not enforced at DB layer in current schema
        let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;

        let (content, content_encrypted, content_nonce, encryption_version) =
            if matches!(privacy_mode, PrivacyMode::StrictE2e) {
                let (ciphertext, nonce) =
                    encryption.encrypt(conversation_id, audio_url.as_bytes())?;
                (String::new(), Some(ciphertext), Some(nonce.to_vec()), 1)
            } else {
                (audio_url.to_string(), None, None, 0)
            };

        let seq: i64 = sqlx::query_scalar(
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
                duration_ms,
                audio_codec,
                content_encrypted,
                content_nonce,
                encryption_version,
                idempotency_key,
                sequence_number
            )
            SELECT
                $1,
                $2,
                $3,
                $4,
                'audio',
                $5,
                $6,
                $7,
                $8,
                $9,
                $10,
                next.last_seq
            FROM next
            RETURNING sequence_number
            "#,
        )
        .bind(id)
        .bind(conversation_id)
        .bind(sender_id)
        .bind(&content)
        .bind(duration_ms as i32)
        .bind(audio_codec)
        .bind(content_encrypted.as_deref())
        .bind(content_nonce.as_deref())
        .bind(encryption_version)
        .bind(idempotency_key)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert audio msg: {e}")))?;

        Ok((id, seq))
    }

    /// Send a message with Matrix integration (dual-write pattern)
    /// Sends to Nova DB first, then optionally to Matrix homeserver
    /// Matrix failures are logged but do not block the message send
    pub async fn send_message_with_matrix(
        db: &Pool<Postgres>,
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
        db: &Pool<Postgres>,
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
            match matrix
                .send_media(conversation_id, &room_id, audio_url, "audio", filename)
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
        db: &Pool<Postgres>,
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
        db: &Pool<Postgres>,
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
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<Vec<super::super::routes::messages::MessageDto>, crate::error::AppError> {
        let rows = sqlx::query(
            r#"SELECT id,
                      sender_id,
                      m.sequence_number AS sequence_number,
                      created_at,
                      recalled_at,
                      updated_at,
                      version_number,
                      content,
                      content_encrypted,
                      content_nonce,
                      message_type
               FROM messages
               WHERE conversation_id = $1 AND deleted_at IS NULL
               ORDER BY created_at ASC
               LIMIT 200"#,
        )
        .bind(conversation_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("history: {e}")))?;
        let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;
        let use_encryption = matches!(privacy_mode, PrivacyMode::StrictE2e);

        let mut out = Vec::with_capacity(rows.len());
        for r in rows {
            let id: Uuid = r.get("id");
            let sender_id: Uuid = r.get("sender_id");
            let seq: i64 = r.get("sequence_number");
            let created_at: chrono::DateTime<Utc> = r.get("created_at");
            let recalled_at: Option<chrono::DateTime<Utc>> = r.get("recalled_at");
            let updated_at: Option<chrono::DateTime<Utc>> = r.get("updated_at");
            let version_number: i32 = r.get("version_number");
            let message_type: Option<String> = r.get("message_type");

            if use_encryption {
                let ciphertext: Option<Vec<u8>> = r
                    .try_get::<Option<Vec<u8>>, _>("content_encrypted")
                    .unwrap_or(None);
                let nonce: Option<Vec<u8>> = r
                    .try_get::<Option<Vec<u8>>, _>("content_nonce")
                    .unwrap_or(None);
                out.push(super::super::routes::messages::MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content: String::new(),
                    encrypted: true,
                    encrypted_payload: ciphertext
                        .as_ref()
                        .map(|c| general_purpose::STANDARD.encode(c)),
                    nonce: nonce.as_ref().map(|n| general_purpose::STANDARD.encode(n)),
                    recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                    updated_at: updated_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type,
                    reactions: Vec::new(),
                    attachments: Vec::new(),
                });
            } else {
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
                    updated_at: updated_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type,
                    reactions: Vec::new(),
                    attachments: Vec::new(),
                });
            }
        }
        Ok(out)
    }

    /// Get message history with full details (reactions, attachments)
    pub async fn get_message_history_with_details(
        db: &Pool<Postgres>,
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
        let query_sql = format!(
            r#"SELECT id,
                      sender_id,
                      m.sequence_number AS sequence_number,
                      created_at,
                      recalled_at,
                      updated_at,
                      version_number,
                      content,
                      content_encrypted,
                      content_nonce,
                      message_type
               FROM messages
               {}
               ORDER BY created_at ASC
               LIMIT $2 OFFSET $3"#,
            where_clause
        );

        let messages = sqlx::query(&query_sql)
            .bind(conversation_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("fetch messages: {e}")))?;

        if messages.is_empty() {
            return Ok(vec![]);
        }

        let message_ids: Vec<Uuid> = messages.iter().map(|r| r.get("id")).collect();

        // 2. Fetch reactions for all messages (aggregated by emoji)
        let reactions_query = sqlx::query(
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
        )
        .bind(user_id)
        .bind(&message_ids)
        .fetch_all(db)
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
        let attachments_query = sqlx::query(
            "SELECT message_id, id, file_name, file_type, file_size, s3_key \
             FROM message_attachments \
             WHERE message_id = ANY($1)",
        )
        .bind(&message_ids)
        .fetch_all(db)
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
        let result = messages
            .into_iter()
            .map(|r| {
                let id: Uuid = r.get("id");
                let sender_id: Uuid = r.get("sender_id");
                let seq: i64 = r.get("sequence_number");
                let created_at: chrono::DateTime<Utc> = r.get("created_at");
                let recalled_at: Option<chrono::DateTime<Utc>> = r.get("recalled_at");
                let updated_at: Option<chrono::DateTime<Utc>> = r.get("updated_at");
                let version_number: i32 = r.get("version_number");
                let message_type: Option<String> = r.get("message_type");

                if use_encryption {
                    let ciphertext: Option<Vec<u8>> = r
                        .try_get::<Option<Vec<u8>>, _>("content_encrypted")
                        .unwrap_or(None);
                    let nonce: Option<Vec<u8>> = r
                        .try_get::<Option<Vec<u8>>, _>("content_nonce")
                        .unwrap_or(None);
                    MessageDto {
                        id,
                        sender_id,
                        sequence_number: seq,
                        created_at: created_at.to_rfc3339(),
                        content: String::new(),
                        encrypted: true,
                        encrypted_payload: ciphertext
                            .as_ref()
                            .map(|c| general_purpose::STANDARD.encode(c)),
                        nonce: nonce.as_ref().map(|n| general_purpose::STANDARD.encode(n)),
                        recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                        updated_at: updated_at.map(|t| t.to_rfc3339()),
                        version_number,
                        message_type,
                        reactions: reactions_map.remove(&id).unwrap_or_default(),
                        attachments: attachments_map.remove(&id).unwrap_or_default(),
                    }
                } else {
                    let content: String = r.get("content");
                    MessageDto {
                        id,
                        sender_id,
                        sequence_number: seq,
                        created_at: created_at.to_rfc3339(),
                        content,
                        encrypted: false,
                        encrypted_payload: None,
                        nonce: None,
                        recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                        updated_at: updated_at.map(|t| t.to_rfc3339()),
                        version_number,
                        message_type,
                        reactions: reactions_map.remove(&id).unwrap_or_default(),
                        attachments: attachments_map.remove(&id).unwrap_or_default(),
                    }
                }
            })
            .collect();

        Ok(result)
    }

    pub async fn update_message_db(
        db: &Pool<Postgres>,
        encryption: &EncryptionService,
        message_id: Uuid,
        plaintext: &[u8],
    ) -> Result<(), crate::error::AppError> {
        let content_plain = String::from_utf8(plaintext.to_vec())
            .map_err(|e| crate::error::AppError::Config(format!("invalid utf8: {e}")))?;

        // Get conversation_id and sender_id before updating
        let msg_info = sqlx::query("SELECT conversation_id FROM messages WHERE id = $1")
            .bind(message_id)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get message info: {e}")))?;
        let conversation_id: Uuid = msg_info.get("conversation_id");

        let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;

        if matches!(privacy_mode, PrivacyMode::StrictE2e) {
            let (ciphertext, nonce) = encryption.encrypt(conversation_id, plaintext)?;
            sqlx::query(
                "UPDATE messages SET content = $1, content_encrypted = $2, content_nonce = $3, encryption_version = 1, version_number = version_number + 1, updated_at = NOW() WHERE id = $4",
            )
            .bind("")
            .bind(ciphertext)
            .bind(nonce.to_vec())
            .bind(message_id)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("update msg: {e}")))?;
        } else {
            sqlx::query(
                "UPDATE messages SET content = $1, content_encrypted = NULL, content_nonce = NULL, encryption_version = 0, version_number = version_number + 1, updated_at = NOW() WHERE id = $2",
            )
                .bind(&content_plain)
                .bind(message_id)
                .execute(db)
                .await
                .map_err(|e| crate::error::AppError::StartServer(format!("update msg: {e}")))?;
        }

        Ok(())
    }

    pub async fn soft_delete_message_db(
        db: &Pool<Postgres>,
        message_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        sqlx::query("UPDATE messages SET deleted_at=NOW() WHERE id=$1")
            .bind(message_id)
            .execute(db)
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
        db: &Pool<Postgres>,
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

        // Get total count for pagination metadata
        let count_result = sqlx::query(
            "SELECT COUNT(*) as total FROM messages m
             WHERE m.conversation_id = $1
               AND m.deleted_at IS NULL
               AND m.content IS NOT NULL
               AND m.content_tsv @@ plainto_tsquery('english', $2)",
        )
        .bind(conversation_id)
        .bind(query)
        .fetch_one(db)
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
        let query_sql = format!(
            "SELECT m.id, m.sender_id, \
                    m.sequence_number AS sequence_number, \
                    m.created_at, m.content, m.recalled_at, m.edited_at, m.version_number, m.message_type \
             FROM messages m \
             WHERE m.conversation_id = $1 \
               AND m.deleted_at IS NULL \
               AND {} \
             ORDER BY {} \
             LIMIT $3 OFFSET $4",
            search_condition, sort_clause
        );

        let rows = sqlx::query(&query_sql)
            .bind(conversation_id)
            .bind(query)
            .bind(limit)
            .bind(offset)
            .fetch_all(db)
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
                let recalled_at: Option<chrono::DateTime<Utc>> = r.try_get("recalled_at").ok();
                let edited_at: Option<chrono::DateTime<Utc>> = r.try_get("edited_at").ok();
                let version_number: i32 = r.try_get("version_number").unwrap_or(1);
                let message_type: Option<String> = r.try_get("message_type").ok();

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
                    message_type,
                    reactions: vec![], // Could be fetched separately if needed for search results
                    attachments: vec![], // Could be fetched separately if needed for search results
                }
            })
            .collect();
        Ok((out, total))
    }
}
