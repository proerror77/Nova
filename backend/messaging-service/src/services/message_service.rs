use uuid::Uuid;
use sqlx::{Pool, Postgres, Row};
use serde::Serialize;
use chrono::{DateTime, Utc};

pub struct MessageService;

impl MessageService {
    pub async fn send_message_db(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        sender_id: Uuid,
        plaintext: &[u8],
        idempotency_key: Option<&str>,
    ) -> Result<(Uuid, i64), crate::error::AppError> {
        let id = Uuid::new_v4();
        // Stub encryption using crypto-core
        let nonce = crypto_core::generate_nonce();
        let ciphertext = crypto_core::encrypt(plaintext, b"pub", b"sec", &nonce)
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
                let id: Uuid = r.get("id");
                let seq: i64 = r.get("sequence_number");
                return Ok((id, seq)); 
            }
            // If conflict happened, fetch existing by key
            let r = sqlx::query("SELECT id, sequence_number FROM messages WHERE idempotency_key = $1")
            .bind(key)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("select by key: {e}")))?;
            let id: Uuid = r.get("id");
            let seq: i64 = r.get("sequence_number");
            return Ok((id, seq));
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
            let id: Uuid = r.get("id");
            let seq: i64 = r.get("sequence_number");
            return Ok((id, seq));
        }
    }
    pub async fn send_message(
        _conversation_id: Uuid,
        _sender_id: Uuid,
        _plaintext: &[u8],
    ) -> Result<Uuid, crate::error::AppError> {
        Err(crate::error::AppError::Config("not implemented".into()))
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
        let ciphertext = crypto_core::encrypt(plaintext, b"pub", b"sec", &nonce)
            .map_err(|_| crate::error::AppError::Config("encrypt failed".into()))?;
        sqlx::query(
            "UPDATE messages SET content_encrypted=$1, content_nonce=$2, edited_at=NOW() WHERE id=$3"
        )
        .bind(ciphertext)
        .bind(&nonce[..])
        .bind(message_id)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update msg: {e}")))?;
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
        Ok(())
    }
}
