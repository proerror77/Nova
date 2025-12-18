use crate::error::AppError;
use crate::redis_client::RedisClient;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use crate::websocket::ConnectionRegistry;
use deadpool_postgres::Pool;
use matrix_sdk::ruma::events::room::message::{
    MessageType, RoomMessageEventContent, SyncRoomMessageEvent,
};
use matrix_sdk::ruma::{OwnedEventId, OwnedUserId};
use matrix_sdk::Room;
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Handle incoming Matrix room message events
/// This function is called by the Matrix sync loop for each new message
pub async fn handle_matrix_message_event(
    db: &Pool,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    matrix_first: bool,
    room: Room,
    event: SyncRoomMessageEvent,
) -> Result<(), AppError> {
    // Extract Original event (skip Redacted events)
    let original_event = match event {
        SyncRoomMessageEvent::Original(ev) => ev,
        SyncRoomMessageEvent::Redacted(_) => {
            // Redacted events are handled separately
            return Ok(());
        }
    };

    let room_id = room.room_id();
    let sender = &original_event.sender;
    let event_id = &original_event.event_id;

    debug!(
        room_id = %room_id,
        sender = %sender,
        event_id = %event_id,
        "Received Matrix message event"
    );

    if matrix_first {
        debug!(
            room_id = %room_id,
            sender = %sender,
            event_id = %event_id,
            "Matrix-first mode enabled; skipping Nova DB persistence and WebSocket broadcast"
        );
        return Ok(());
    }

    // 1. Look up conversation_id from Matrix room_id
    let conversation_id =
        match super::matrix_db::lookup_conversation_by_room_id(db, room_id.as_str()).await? {
            Some(id) => id,
            None => {
                warn!(
                    room_id = %room_id,
                    "Received message for unknown Matrix room, ignoring"
                );
                return Ok(());
            }
        };

    // 2. Extract Nova user_id from Matrix user_id
    // Matrix user format: @nova-<uuid>:staging.nova.internal
    // We need to extract the UUID part
    let user_id = match extract_user_id_from_matrix(sender) {
        Some(id) => id,
        None => {
            warn!(
                sender = %sender,
                "Failed to extract Nova user_id from Matrix sender, ignoring"
            );
            return Ok(());
        }
    };

    // 3. Check if this message already exists in our DB (by matrix_event_id)
    // This prevents duplicate processing
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("handle matrix message pool: {e}")))?;
    let existing: Option<Uuid> = client.query_opt(
        "SELECT id FROM messages WHERE matrix_event_id = $1",
        &[&event_id.as_str()],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("check existing message: {e}")))?
    .map(|row| row.get(0));

    if existing.is_some() {
        debug!(
            event_id = %event_id,
            "Message already exists in DB, skipping"
        );
        return Ok(());
    }

    // 4. Extract message content based on message type
    let content_text = match original_event.content.msgtype {
        MessageType::Text(text_content) => text_content.body,
        MessageType::Audio(audio_content) => {
            // For audio messages, we'd need to download from Matrix and upload to our storage
            // For now, just store the Matrix URL/reference
            format!("[Audio message: {}]", audio_content.body)
        }
        MessageType::Image(image_content) => {
            format!("[Image: {}]", image_content.body)
        }
        MessageType::File(file_content) => {
            format!("[File: {}]", file_content.body)
        }
        MessageType::Video(video_content) => {
            format!("[Video: {}]", video_content.body)
        }
        _ => {
            debug!(
                event_id = %event_id,
                "Unsupported Matrix message type, ignoring"
            );
            return Ok(());
        }
    };

    // 5. Insert message into our DB
    // Use send_message_db to maintain consistency, but skip Matrix send
    let message = crate::services::message_service::MessageService::send_message_db(
        db,
        &crate::services::encryption::EncryptionService::new([0u8; 32]), // Placeholder - won't encrypt
        conversation_id,
        user_id,
        content_text.as_bytes(),
        None, // No idempotency key
    )
    .await?;

    // 6. Update message with Matrix event_id to link them
    super::matrix_db::update_message_matrix_event_id(db, message.id, event_id.as_str()).await?;

    info!(
        message_id = %message.id,
        conversation_id = %conversation_id,
        event_id = %event_id,
        "Matrix message saved to DB"
    );

    // 7. Broadcast to WebSocket clients (same as normal message flow)
    let ws_event = WebSocketEvent::MessageNew {
        id: message.id,
        sender_id: user_id,
        sequence_number: message.sequence_number,
        conversation_id,
    };

    if let Err(e) = broadcast_event(registry, redis, conversation_id, user_id, ws_event).await {
        error!(
            error = %e,
            message_id = %message.id,
            "Failed to broadcast Matrix message via WebSocket"
        );
    }

    Ok(())
}

/// Extract Nova user UUID from Matrix user_id
/// Matrix user format: @nova-<uuid>:staging.nova.internal
/// Returns Some(uuid) if valid, None otherwise
fn extract_user_id_from_matrix(matrix_user: &OwnedUserId) -> Option<Uuid> {
    let user_str = matrix_user.as_str();

    // Expected format: @nova-<uuid>:staging.nova.internal
    // Extract the part between @nova- and :
    if !user_str.starts_with("@nova-") {
        return None;
    }

    let without_prefix = user_str.strip_prefix("@nova-")?;
    let uuid_part = without_prefix.split(':').next()?;

    Uuid::parse_str(uuid_part).ok()
}

/// Handle Matrix room redaction events (message deletion)
pub async fn handle_matrix_redaction_event(
    db: &Pool,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    _room: Room,
    redacted_event_id: &OwnedEventId,
) -> Result<(), AppError> {
    debug!(
        redacted_event_id = %redacted_event_id,
        "Received Matrix redaction event"
    );

    // 1. Find message by Matrix event_id
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("handle redaction pool: {e}")))?;
    let message = client.query_opt(
        "SELECT id, conversation_id FROM messages WHERE matrix_event_id = $1",
        &[&redacted_event_id.as_str()],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("find redacted message: {e}")))?;

    let (message_id, conversation_id) = match message {
        Some(row) => {
            let message_id: Uuid = row.get(0);
            let conversation_id: Uuid = row.get(1);
            (message_id, conversation_id)
        }
        None => {
            warn!(
                redacted_event_id = %redacted_event_id,
                "Redaction for unknown message, ignoring"
            );
            return Ok(());
        }
    };

    // 2. Soft delete the message in our DB
    crate::services::message_service::MessageService::soft_delete_message_db(db, message_id)
        .await?;

    info!(
        message_id = %message_id,
        conversation_id = %conversation_id,
        redacted_event_id = %redacted_event_id,
        "Message deleted via Matrix redaction"
    );

    // 3. Broadcast deletion to WebSocket clients
    let ws_event = WebSocketEvent::MessageDeleted {
        conversation_id,
        message_id,
    };

    // Get sender_id from DB (we need it for broadcast)
    let sender_id: Uuid = client.query_one(
        "SELECT sender_id FROM messages WHERE id = $1",
        &[&message_id],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("get sender_id: {e}")))?
    .get(0);

    if let Err(e) = broadcast_event(registry, redis, conversation_id, sender_id, ws_event).await {
        error!(
            error = %e,
            message_id = %message_id,
            "Failed to broadcast Matrix redaction via WebSocket"
        );
    }

    Ok(())
}

/// Handle Matrix room message edit/replacement events
pub async fn handle_matrix_replacement_event(
    db: &Pool,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    _room: Room,
    original_event_id: &OwnedEventId,
    new_content: &RoomMessageEventContent,
) -> Result<(), AppError> {
    debug!(
        original_event_id = %original_event_id,
        "Received Matrix replacement event"
    );

    // 1. Find message by original Matrix event_id
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("handle replacement pool: {e}")))?;
    let message = client.query_opt(
        "SELECT id, conversation_id, sender_id FROM messages WHERE matrix_event_id = $1",
        &[&original_event_id.as_str()],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("find edited message: {e}")))?;

    let (message_id, conversation_id, sender_id) = match message {
        Some(row) => {
            let message_id: Uuid = row.get(0);
            let conversation_id: Uuid = row.get(1);
            let sender_id: Uuid = row.get(2);
            (message_id, conversation_id, sender_id)
        }
        None => {
            warn!(
                original_event_id = %original_event_id,
                "Edit for unknown message, ignoring"
            );
            return Ok(());
        }
    };

    // 2. Extract new content text
    let new_text = match &new_content.msgtype {
        MessageType::Text(text_content) => &text_content.body,
        _ => {
            warn!(
                original_event_id = %original_event_id,
                "Unsupported edit content type, ignoring"
            );
            return Ok(());
        }
    };

    // 3. Update message in our DB
    crate::services::message_service::MessageService::update_message_db(
        db,
        &crate::services::encryption::EncryptionService::new([0u8; 32]), // Placeholder
        message_id,
        new_text.as_bytes(),
    )
    .await?;

    info!(
        message_id = %message_id,
        conversation_id = %conversation_id,
        original_event_id = %original_event_id,
        "Message edited via Matrix replacement"
    );

    // 4. Get new version number
    let version_number: i32 = client.query_one(
        "SELECT version_number FROM messages WHERE id = $1",
        &[&message_id],
    )
    .await
    .map_err(|e| AppError::StartServer(format!("get version: {e}")))?
    .get(0);

    // 5. Broadcast edit to WebSocket clients
    let ws_event = WebSocketEvent::MessageEdited {
        conversation_id,
        message_id,
        version_number,
    };

    if let Err(e) = broadcast_event(registry, redis, conversation_id, sender_id, ws_event).await {
        error!(
            error = %e,
            message_id = %message_id,
            "Failed to broadcast Matrix edit via WebSocket"
        );
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_user_id_from_matrix() {
        use matrix_sdk::ruma::UserId;

        // Valid format
        let user_id = UserId::parse("@nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.internal")
            .unwrap();
        let extracted = extract_user_id_from_matrix(&user_id);
        assert!(extracted.is_some());
        assert_eq!(
            extracted.unwrap(),
            Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap()
        );

        // Invalid format (no nova- prefix)
        let user_id = UserId::parse("@user:staging.nova.internal").unwrap();
        let extracted = extract_user_id_from_matrix(&user_id);
        assert!(extracted.is_none());

        // Invalid UUID
        let user_id = UserId::parse("@nova-invalid-uuid:staging.nova.internal").unwrap();
        let extracted = extract_user_id_from_matrix(&user_id);
        assert!(extracted.is_none());
    }
}
