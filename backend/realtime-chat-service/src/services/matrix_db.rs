use crate::error::AppError;
use matrix_sdk::ruma::{OwnedRoomId, RoomId};
use sqlx::{Pool, Postgres};
use tracing::{debug, warn};
use uuid::Uuid;

/// Save conversation -> Matrix room mapping to database
pub async fn save_room_mapping(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
    room_id: &RoomId,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO matrix_room_mapping (conversation_id, matrix_room_id)
        VALUES ($1, $2)
        ON CONFLICT (conversation_id)
        DO UPDATE SET
            matrix_room_id = EXCLUDED.matrix_room_id,
            updated_at = CURRENT_TIMESTAMP
        "#,
    )
    .bind(conversation_id)
    .bind(room_id.as_str())
    .execute(db)
    .await
    .map_err(|e| AppError::StartServer(format!("save room mapping: {e}")))?;

    debug!(
        "Saved room mapping: conversation={} -> room={}",
        conversation_id,
        room_id
    );

    Ok(())
}

/// Load Matrix room ID for a conversation
pub async fn load_room_mapping(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
) -> Result<Option<OwnedRoomId>, AppError> {
    let room_id: Option<String> = sqlx::query_scalar(
        "SELECT matrix_room_id FROM matrix_room_mapping WHERE conversation_id = $1",
    )
    .bind(conversation_id)
    .fetch_optional(db)
    .await
    .map_err(|e| AppError::StartServer(format!("load room mapping: {e}")))?;

    match room_id {
        Some(id_str) => {
            let room_id = OwnedRoomId::try_from(id_str.clone()).map_err(|e| {
                AppError::Config(format!("Invalid room_id in DB: {}: {}", id_str, e))
            })?;
            Ok(Some(room_id))
        }
        None => Ok(None),
    }
}

/// Reverse lookup: Matrix room -> conversation
pub async fn lookup_conversation_by_room_id(
    db: &Pool<Postgres>,
    room_id: &str,
) -> Result<Option<Uuid>, AppError> {
    let conversation_id = sqlx::query_scalar(
        "SELECT conversation_id FROM matrix_room_mapping WHERE matrix_room_id = $1",
    )
    .bind(room_id)
    .fetch_optional(db)
    .await
    .map_err(|e| AppError::StartServer(format!("lookup conversation by room: {e}")))?;

    Ok(conversation_id)
}

/// Get Matrix event_id and room_id for a message
pub async fn get_matrix_info(
    db: &Pool<Postgres>,
    message_id: Uuid,
) -> Result<(Option<String>, Option<OwnedRoomId>), AppError> {
    let row: Option<(Option<String>, Uuid)> = sqlx::query_as(
        r#"
        SELECT m.matrix_event_id, m.conversation_id
        FROM messages m
        WHERE m.id = $1
        "#,
    )
    .bind(message_id)
    .fetch_optional(db)
    .await
    .map_err(|e| AppError::StartServer(format!("get matrix info: {e}")))?;

    if let Some((event_id, conversation_id)) = row {
        let room_id = load_room_mapping(db, conversation_id).await?;
        Ok((event_id, room_id))
    } else {
        Ok((None, None))
    }
}

/// Update message with Matrix event ID
pub async fn update_message_matrix_event_id(
    db: &Pool<Postgres>,
    message_id: Uuid,
    event_id: &str,
) -> Result<(), AppError> {
    sqlx::query("UPDATE messages SET matrix_event_id = $1 WHERE id = $2")
        .bind(event_id)
        .bind(message_id)
        .execute(db)
        .await
        .map_err(|e| AppError::StartServer(format!("update matrix event id: {e}")))?;

    debug!(
        "Updated message {} with matrix_event_id={}",
        message_id, event_id
    );

    Ok(())
}

/// Get conversation participants (for room creation)
pub async fn get_conversation_participants(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
) -> Result<Vec<Uuid>, AppError> {
    let participant_ids = sqlx::query_scalar(
        "SELECT user_id FROM conversation_members WHERE conversation_id = $1",
    )
    .bind(conversation_id)
    .fetch_all(db)
    .await
    .map_err(|e| AppError::StartServer(format!("get conversation participants: {e}")))?;

    Ok(participant_ids)
}

/// Load all room mappings into memory (for startup cache warming)
pub async fn load_all_room_mappings(
    db: &Pool<Postgres>,
) -> Result<Vec<(Uuid, OwnedRoomId)>, AppError> {
    let rows: Vec<(Uuid, String)> =
        sqlx::query_as("SELECT conversation_id, matrix_room_id FROM matrix_room_mapping")
            .fetch_all(db)
            .await
            .map_err(|e| AppError::StartServer(format!("load all room mappings: {e}")))?;

    let mut mappings = Vec::new();
    for (conversation_id, room_id_str) in rows {
        match OwnedRoomId::try_from(room_id_str.clone()) {
            Ok(room_id) => {
                mappings.push((conversation_id, room_id));
            }
            Err(e) => {
                warn!(
                    "Invalid room_id in DB for conversation {}: {} ({})",
                    conversation_id, room_id_str, e
                );
            }
        }
    }

    Ok(mappings)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_room_id_parsing() {
        // Valid Matrix room ID format
        let valid_room_id = "!abc123:staging.nova.internal";
        let parsed = OwnedRoomId::try_from(valid_room_id.to_string());
        assert!(parsed.is_ok());

        // Invalid format
        let invalid = "not-a-room-id";
        let parsed = OwnedRoomId::try_from(invalid.to_string());
        assert!(parsed.is_err());
    }
}
