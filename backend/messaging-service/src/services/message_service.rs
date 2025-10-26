use chrono::Utc;
use base64;
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

pub struct MessageService;

impl MessageService {
    // NOTE (2025-10-26): Removed upsert_search_index and delete_search_index functions
    // These were maintaining a separate message_search_index table (dual-path indexing)
    // We now rely exclusively on PostgreSQL's native full-text search on messages.content
    // This simplifies the architecture and eliminates potential data inconsistencies

    pub async fn send_message_db(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        sender_id: Uuid,
        plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<(Uuid, i64), crate::error::AppError> {
        let id = Uuid::new_v4();
        // ARCHITECTURE NOTE (2025-10-26):
        // Messages are now stored in plaintext in the `content` field.
        // Database-level encryption (PostgreSQL TDE) provides at-rest protection.
        // For details, see: backend/ENCRYPTION_ARCHITECTURE.md

        let content = String::from_utf8(plaintext.to_vec())
            .map_err(|e| crate::error::AppError::Config(format!("invalid utf8: {e}")))?;

        // Insert with compatibility to user-service schema (encrypted_content, nonce required; no sequence_number column)
        let enc_b64 = base64::encode(&content);
        let nonce = "dev-nonce";
        if idempotency_key.is_some() {
            // Basic insert (idempotency via external caller if needed)
            sqlx::query(
                "INSERT INTO messages (id, conversation_id, sender_id, content, encrypted_content, nonce) \
                 VALUES ($1, $2, $3, $4, $5, $6)",
            )
            .bind(id)
            .bind(conversation_id)
            .bind(sender_id)
            .bind(&content)
            .bind(&enc_b64)
            .bind(nonce)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("insert msg: {e}")))?;
        } else {
            sqlx::query(
                "INSERT INTO messages (id, conversation_id, sender_id, content, encrypted_content, nonce) \
                 VALUES ($1, $2, $3, $4, $5, $6)",
            )
            .bind(id)
            .bind(conversation_id)
            .bind(sender_id)
            .bind(&content)
            .bind(&enc_b64)
            .bind(nonce)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("insert msg: {e}")))?;
        }

        // Approximate sequence number as message count in conversation
        let seq: i64 = sqlx::query_scalar(
            "SELECT COUNT(*)::bigint FROM messages WHERE conversation_id = $1",
        )
        .bind(conversation_id)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("seq count: {e}")))?;

        Ok((id, seq))
    }
    /// Send a message to a conversation (wrapper for send_message_db)
    /// Note: This is a simplified version. Use send_message_db directly for full control.
    /// Returns: message ID
    pub async fn send_message(
        db: &Pool<Postgres>,
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
        let (message_id, _sequence_number) =
            Self::send_message_db(db, conversation_id, sender_id, plaintext, None).await?;

        Ok(message_id)
    }

    /// Send an audio message to a conversation
    /// Stores audio metadata (codec, duration) alongside message
    /// Returns: (message_id, sequence_number)
    pub async fn send_audio_message_db(
        db: &Pool<Postgres>,
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
        sqlx::query(
            "INSERT INTO messages (id, conversation_id, sender_id, content, message_type, duration_ms, audio_codec, encrypted_content, nonce) \
             VALUES ($1, $2, $3, $4, 'audio', $5, $6, $7, $8)",
        )
        .bind(id)
        .bind(conversation_id)
        .bind(sender_id)
        .bind(audio_url)
        .bind(duration_ms as i32)
        .bind(audio_codec)
        .bind(base64::encode(audio_url))
        .bind("dev-nonce")
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert audio msg: {e}")))?;

        let seq: i64 = sqlx::query_scalar(
            "SELECT COUNT(*)::bigint FROM messages WHERE conversation_id = $1",
        )
        .bind(conversation_id)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("seq count: {e}")))?;

        Ok((id, seq))
    }

    pub async fn get_message_history_db(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<Vec<super::super::routes::messages::MessageDto>, crate::error::AppError> {
        let rows = sqlx::query(
            r#"SELECT id,
                      sender_id,
                      ROW_NUMBER() OVER (ORDER BY created_at ASC) AS sequence_number,
                      created_at,
                      recalled_at,
                      updated_at,
                      version_number,
                      content,
                      message_type
               FROM messages
               WHERE conversation_id = $1 AND deleted_at IS NULL
               ORDER BY created_at ASC
               LIMIT 200"#
        )
        .bind(conversation_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("history: {e}")))?;
        let out = rows
            .into_iter()
            .map(|r| {
                let id: Uuid = r.get("id");
                let sender_id: Uuid = r.get("sender_id");
                let seq: i64 = r.get("sequence_number");
                let created_at: chrono::DateTime<Utc> = r.get("created_at");
                let recalled_at: Option<chrono::DateTime<Utc>> = r.get("recalled_at");
                let updated_at: Option<chrono::DateTime<Utc>> = r.get("updated_at");
                let version_number: i32 = r.get("version_number");
                let content: String = r.get("content");
                let message_type: Option<String> = r.get("message_type");
                super::super::routes::messages::MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content,
                    recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                    updated_at: updated_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type,
                    reactions: vec![], // Will be populated by get_message_history_with_details
                    attachments: vec![],
                }
            })
            .collect();
        Ok(out)
    }

    /// Get message history with full details (reactions, attachments)
    pub async fn get_message_history_with_details(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        user_id: Uuid,
        limit: i64,
        offset: i64,
        include_recalled: bool,
    ) -> Result<Vec<super::super::routes::messages::MessageDto>, crate::error::AppError> {
        use super::super::routes::messages::{MessageAttachment, MessageDto, MessageReaction};
        use std::collections::HashMap;

        let limit = limit.min(200); // Cap at 200

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
                      ROW_NUMBER() OVER (ORDER BY created_at ASC) AS sequence_number,
                      created_at,
                      recalled_at,
                      updated_at,
                      version_number,
                      content,
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
                let content: String = r.get("content");
                let message_type: Option<String> = r.get("message_type");

                MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content,
                    recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                    updated_at: updated_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type,
                    reactions: reactions_map.remove(&id).unwrap_or_default(),
                    attachments: attachments_map.remove(&id).unwrap_or_default(),
                }
            })
            .collect();

        Ok(result)
    }

    pub async fn update_message_db(
        db: &Pool<Postgres>,
        message_id: Uuid,
        plaintext: &[u8],
    ) -> Result<(), crate::error::AppError> {
        // ARCHITECTURE NOTE (2025-10-26):
        // Messages are now stored in plaintext in the `content` field.
        // Database-level encryption (PostgreSQL TDE) provides at-rest protection.

        let content = String::from_utf8(plaintext.to_vec())
            .map_err(|e| crate::error::AppError::Config(format!("invalid utf8: {e}")))?;

        // Get conversation_id and sender_id before updating
        let msg_info = sqlx::query("SELECT conversation_id, sender_id FROM messages WHERE id = $1")
            .bind(message_id)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get message info: {e}")))?;
        let conversation_id: Uuid = msg_info.get("conversation_id");
        let sender_id: Uuid = msg_info.get("sender_id");

        // Update the message
        sqlx::query("UPDATE messages SET content=$1, updated_at=NOW() WHERE id=$2")
            .bind(&content)
            .bind(message_id)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("update msg: {e}")))?;

        // Search index is automatically updated via PostgreSQL FTS on messages.content

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
            "recent" | _ => (
                "m.created_at DESC",
                "m.content IS NOT NULL AND m.content_tsv @@ plainto_tsquery('english', $2)",
            ),
        };

        // Build the query with proper sorting - include all message fields
        let query_sql = format!(
            "SELECT m.id, m.sender_id, \
                    ROW_NUMBER() OVER (ORDER BY m.created_at ASC) AS sequence_number, \
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
