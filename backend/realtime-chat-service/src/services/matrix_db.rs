use crate::error::AppError;
use deadpool_postgres::Pool;
use matrix_sdk::ruma::{OwnedRoomId, RoomId};
use tracing::{debug, warn};
use uuid::Uuid;

/// Save conversation -> Matrix room mapping to database
pub async fn save_room_mapping(
    db: &Pool,
    conversation_id: Uuid,
    room_id: &RoomId,
) -> Result<(), AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("save room mapping pool: {e}")))?;
    client.execute(
        r#"
        INSERT INTO matrix_room_mapping (conversation_id, matrix_room_id)
        VALUES ($1, $2)
        ON CONFLICT (conversation_id)
        DO UPDATE SET
            matrix_room_id = EXCLUDED.matrix_room_id,
            updated_at = CURRENT_TIMESTAMP
        "#,
        &[&conversation_id, &room_id.as_str()],
    )
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
    db: &Pool,
    conversation_id: Uuid,
) -> Result<Option<OwnedRoomId>, AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("load room mapping pool: {e}")))?;
    let room_id: Option<String> = client.query_opt(
        "SELECT matrix_room_id FROM matrix_room_mapping WHERE conversation_id = $1",
        &[&conversation_id],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("load room mapping: {e}")))?
    .map(|row| row.get(0));

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
    db: &Pool,
    room_id: &str,
) -> Result<Option<Uuid>, AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("lookup conversation pool: {e}")))?;
    let conversation_id = client.query_opt(
        "SELECT conversation_id FROM matrix_room_mapping WHERE matrix_room_id = $1",
        &[&room_id],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("lookup conversation by room: {e}")))?
    .map(|row| row.get(0));

    Ok(conversation_id)
}

/// Get Matrix event_id and room_id for a message
pub async fn get_matrix_info(
    db: &Pool,
    message_id: Uuid,
) -> Result<(Option<String>, Option<OwnedRoomId>), AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("get matrix info pool: {e}")))?;
    let row = client.query_opt(
        r#"
        SELECT m.matrix_event_id, m.conversation_id
        FROM messages m
        WHERE m.id = $1
        "#,
        &[&message_id],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("get matrix info: {e}")))?;

    if let Some(row) = row {
        let event_id: Option<String> = row.get(0);
        let conversation_id: Uuid = row.get(1);
        let room_id = load_room_mapping(db, conversation_id).await?;
        Ok((event_id, room_id))
    } else {
        Ok((None, None))
    }
}

/// Update message with Matrix event ID
pub async fn update_message_matrix_event_id(
    db: &Pool,
    message_id: Uuid,
    event_id: &str,
) -> Result<(), AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("update matrix event id pool: {e}")))?;
    client.execute(
        "UPDATE messages SET matrix_event_id = $1 WHERE id = $2",
        &[&event_id, &message_id],
    )
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
    db: &Pool,
    conversation_id: Uuid,
) -> Result<Vec<Uuid>, AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("get conversation participants pool: {e}")))?;
    let rows = client.query(
        "SELECT user_id FROM conversation_members WHERE conversation_id = $1",
        &[&conversation_id],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("get conversation participants: {e}")))?;

    let participant_ids: Vec<Uuid> = rows.iter().map(|row| row.get(0)).collect();

    Ok(participant_ids)
}

/// Get E2EE conversations that don't have Matrix rooms yet
/// This is used during startup to ensure all strict_e2e conversations have Matrix rooms
pub async fn get_e2ee_conversations_without_rooms(
    db: &Pool,
) -> Result<Vec<(Uuid, Vec<Uuid>)>, AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("get e2ee conversations pool: {e}")))?;

    // Find conversations with strict_e2e privacy that don't have Matrix room mappings
    let rows = client.query(
        r#"
        SELECT c.id, ARRAY_AGG(cm.user_id) as participants
        FROM conversations c
        JOIN conversation_members cm ON c.id = cm.conversation_id
        LEFT JOIN matrix_room_mapping mrm ON c.id = mrm.conversation_id
        WHERE c.privacy_mode = 'strict_e2e'
          AND c.deleted_at IS NULL
          AND mrm.conversation_id IS NULL
        GROUP BY c.id
        "#,
        &[],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("get e2ee conversations: {e}")))?;

    let mut results = Vec::new();
    for row in rows {
        let conversation_id: Uuid = row.get(0);
        let participants: Vec<Uuid> = row.get(1);
        results.push((conversation_id, participants));
    }

    Ok(results)
}

/// Load all room mappings into memory (for startup cache warming)
pub async fn load_all_room_mappings(
    db: &Pool,
) -> Result<Vec<(Uuid, OwnedRoomId)>, AppError> {
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("load all room mappings pool: {e}")))?;
    let rows = client.query(
        "SELECT conversation_id, matrix_room_id FROM matrix_room_mapping",
        &[],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("load all room mappings: {e}")))?;

    let mut mappings = Vec::new();
    for row in rows {
        let conversation_id: Uuid = row.get(0);
        let room_id_str: String = row.get(1);
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
