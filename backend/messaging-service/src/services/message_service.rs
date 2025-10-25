use uuid::Uuid;
use sqlx::{Pool, Postgres, Row};
use chrono::Utc;

pub struct MessageService;

impl MessageService {
    /// Create or update search index entry for a message
    /// This enables full-text search on message content
    pub async fn upsert_search_index(
        db: &Pool<Postgres>,
        message_id: Uuid,
        conversation_id: Uuid,
        sender_id: Uuid,
        search_text: &str,
    ) -> Result<(), crate::error::AppError> {
        sqlx::query(
            "INSERT INTO message_search_index (message_id, conversation_id, sender_id, search_text)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (message_id) DO UPDATE
             SET search_text = $4, created_at = NOW()"
        )
        .bind(message_id)
        .bind(conversation_id)
        .bind(sender_id)
        .bind(search_text)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("upsert search index: {e}")))?;
        Ok(())
    }

    /// Remove message from search index
    pub async fn delete_search_index(
        db: &Pool<Postgres>,
        message_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        sqlx::query("DELETE FROM message_search_index WHERE message_id = $1")
            .bind(message_id)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("delete from search index: {e}")))?;
        Ok(())
    }

    pub async fn send_message_db(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        sender_id: Uuid,
        plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<(Uuid, i64), crate::error::AppError> {
        let id = Uuid::new_v4();
        // Encrypt-at-rest using secretbox with server key
        let nonce = crypto_core::generate_nonce();
        let key = crate::security::keys::secretbox_key_from_env()?;
        let ciphertext = crypto_core::encrypt_at_rest(plaintext, &key, &nonce)
            .map_err(|_| crate::error::AppError::Config("encrypt failed".into()))?;
        // Insert with conflict on idempotency_key
        if let Some(key) = idempotency_key {
            let rec = sqlx::query(
                "INSERT INTO messages (id, conversation_id, sender_id, encryption_version, content_encrypted, content_nonce, idempotency_key) \
                 VALUES ($1, $2, $3, 1, $4, $5, $6) \
                 ON CONFLICT (idempotency_key) DO NOTHING \
                 RETURNING id, sequence_number"
            )
            .bind(id)
            .bind(conversation_id)
            .bind(sender_id)
            .bind(ciphertext)
            .bind(&nonce[..])
            .bind(key)
            .fetch_optional(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("insert msg: {e}")))?;
            if let Some(r) = rec {
                let msg_id: Uuid = r.get("id");
                let seq: i64 = r.get("sequence_number");
                // Index message for full-text search
                let search_text = String::from_utf8_lossy(plaintext);
                let _ = Self::upsert_search_index(db, msg_id, conversation_id, sender_id, &search_text).await;
                return Ok((msg_id, seq));
            }
            // If conflict happened, fetch existing by key
            let r = sqlx::query("SELECT id, sequence_number FROM messages WHERE idempotency_key = $1")
            .bind(key)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("select by key: {e}")))?;
            let msg_id: Uuid = r.get("id");
            let seq: i64 = r.get("sequence_number");
            return Ok((msg_id, seq));
        } else {
            let r = sqlx::query(
                "INSERT INTO messages (id, conversation_id, sender_id, encryption_version, content_encrypted, content_nonce) \
                 VALUES ($1, $2, $3, 1, $4, $5) \
                 RETURNING id, sequence_number"
            )
            .bind(id)
            .bind(conversation_id)
            .bind(sender_id)
            .bind(ciphertext)
            .bind(&nonce[..])
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("insert msg: {e}")))?;
            let msg_id: Uuid = r.get("id");
            let seq: i64 = r.get("sequence_number");
            // Index message for full-text search
            let search_text = String::from_utf8_lossy(plaintext);
            let _ = Self::upsert_search_index(db, msg_id, conversation_id, sender_id, &search_text).await;
            return Ok((msg_id, seq));
        }
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

    pub async fn get_message_history_db(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<Vec<super::super::routes::messages::MessageDto>, crate::error::AppError> {
        let rows = sqlx::query(
            "SELECT id, sender_id, sequence_number, created_at FROM messages \
             WHERE conversation_id = $1 AND deleted_at IS NULL ORDER BY sequence_number ASC LIMIT 200"
        )
        .bind(conversation_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("history: {e}")))?;
        let out = rows.into_iter().map(|r| {
            let id: Uuid = r.get("id");
            let sender_id: Uuid = r.get("sender_id");
            let seq: i64 = r.get("sequence_number");
            let created_at: chrono::DateTime<Utc> = r.get("created_at");
            super::super::routes::messages::MessageDto {
                id,
                sender_id,
                sequence_number: seq,
                created_at: created_at.to_rfc3339(),
            }
        }).collect();
        Ok(out)
    }

    pub async fn update_message_db(db: &Pool<Postgres>, message_id: Uuid, plaintext: &[u8]) -> Result<(), crate::error::AppError> {
        let nonce = crypto_core::generate_nonce();
        let key = crate::security::keys::secretbox_key_from_env()?;
        let ciphertext = crypto_core::encrypt_at_rest(plaintext, &key, &nonce)
            .map_err(|_| crate::error::AppError::Config("encrypt failed".into()))?;

        // Get conversation_id and sender_id before updating
        let msg_info = sqlx::query("SELECT conversation_id, sender_id FROM messages WHERE id = $1")
            .bind(message_id)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get message info: {e}")))?;
        let conversation_id: Uuid = msg_info.get("conversation_id");
        let sender_id: Uuid = msg_info.get("sender_id");

        // Update the message
        sqlx::query(
            "UPDATE messages SET content_encrypted=$1, content_nonce=$2, edited_at=NOW() WHERE id=$3"
        )
        .bind(ciphertext)
        .bind(&nonce[..])
        .bind(message_id)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update msg: {e}")))?;

        // Update search index with new content
        let search_text = String::from_utf8_lossy(plaintext);
        Self::upsert_search_index(db, message_id, conversation_id, sender_id, &search_text).await?;

        Ok(())
    }

    pub async fn soft_delete_message_db(db: &Pool<Postgres>, message_id: Uuid) -> Result<(), crate::error::AppError> {
        sqlx::query(
            "UPDATE messages SET deleted_at=NOW() WHERE id=$1"
        )
        .bind(message_id)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("delete msg: {e}")))?;

        // Remove from search index
        Self::delete_search_index(db, message_id).await?;

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
    ) -> Result<(Vec<super::super::routes::messages::MessageDto>, i64), crate::error::AppError> {
        let limit = limit.min(500); // Cap at 500 to prevent memory issues
        let sort_by = sort_by.unwrap_or("recent");

        // Get total count for pagination metadata
        let count_result = sqlx::query(
            "SELECT COUNT(*) as total FROM messages m
             WHERE m.conversation_id = $1
               AND m.deleted_at IS NULL
               AND EXISTS (
                   SELECT 1 FROM message_search_index
                   WHERE message_id = m.id
                     AND search_text @@ plainto_tsquery('simple', $2)
               )"
        )
        .bind(conversation_id)
        .bind(query)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("count search results: {e}")))?;
        let total: i64 = count_result.get("total");

        // Build sort clause based on sort_by parameter
        let (sort_clause, search_query) = match sort_by {
            "oldest" => ("m.created_at ASC", "plainto_tsquery('simple', $2)"),
            "relevance" => ("ts_rank(si.tsv, plainto_tsquery('simple', $2)) DESC, m.created_at DESC", "plainto_tsquery('simple', $2)"),
            "recent" | _ => ("m.created_at DESC", "plainto_tsquery('simple', $2)"),
        };

        // Build the query with proper sorting
        let query_sql = format!(
            "SELECT m.id, m.sender_id, m.sequence_number, m.created_at
             FROM messages m
             JOIN message_search_index si ON m.id = si.message_id
             WHERE m.conversation_id = $1
               AND m.deleted_at IS NULL
               AND si.search_text @@ {}
             ORDER BY {}
             LIMIT $3 OFFSET $4",
            search_query, sort_clause
        );

        let rows = sqlx::query(&query_sql)
            .bind(conversation_id)
            .bind(query)
            .bind(limit)
            .bind(offset)
            .fetch_all(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("search: {e}")))?;

        let out = rows.into_iter().map(|r| {
            let id: Uuid = r.get("id");
            let sender_id: Uuid = r.get("sender_id");
            let seq: i64 = r.get("sequence_number");
            let created_at: chrono::DateTime<Utc> = r.get("created_at");
            super::super::routes::messages::MessageDto {
                id,
                sender_id,
                sequence_number: seq,
                created_at: created_at.to_rfc3339(),
            }
        }).collect();
        Ok((out, total))
    }
}
