// Allow deprecated EncryptionService - used as placeholder for API compatibility
#![allow(deprecated)]

use crate::error::AppError;
use crate::redis_client::RedisClient;
use crate::services::matrix_user::extract_nova_user_id_from_matrix;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use crate::websocket::ConnectionRegistry;
use chrono::{DateTime, TimeZone, Utc};
use deadpool_postgres::Pool;
use matrix_sdk::ruma::events::room::encrypted::Relation as EncryptedRelation;
use matrix_sdk::ruma::events::room::encrypted::SyncRoomEncryptedEvent;
use matrix_sdk::ruma::events::room::message::{
    MessageType, Relation as MessageRelation, RoomMessageEventContent, SyncRoomMessageEvent,
};
use matrix_sdk::ruma::{MilliSecondsSinceUnixEpoch, OwnedEventId};
use matrix_sdk::Room;
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

fn ts_to_utc(ts: Option<MilliSecondsSinceUnixEpoch>) -> DateTime<Utc> {
    let Some(ts) = ts else {
        return Utc::now();
    };

    let ms: i64 = ts.get().into();
    Utc.timestamp_millis_opt(ms).single().unwrap_or_else(Utc::now)
}

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
    let user_id = match extract_nova_user_id_from_matrix(sender) {
        Some(id) => id,
        None => {
            warn!(
                sender = %sender,
                "Failed to extract Nova user_id from Matrix sender, ignoring"
            );
            return Ok(());
        }
    };

    // Ignore replacements (edits). Clients render edits via Matrix relations; Nova stores only canonical messages.
    if matches!(
        original_event.content.relates_to,
        Some(MessageRelation::Replacement(_))
    ) {
        debug!(event_id = %event_id, "Replacement (edit) event; skipping metadata insert");
        return Ok(());
    }

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

    // 4. Validate message type (we still persist metadata-only for supported message types)
    match original_event.content.msgtype {
        MessageType::Text(_)
        | MessageType::Audio(_)
        | MessageType::Image(_)
        | MessageType::File(_)
        | MessageType::Video(_) => {}
        _ => {
            debug!(
                event_id = %event_id,
                "Unsupported Matrix message type, ignoring"
            );
            return Ok(());
        }
    }

    let created_at = ts_to_utc(Some(original_event.origin_server_ts));

    // 5. Persist metadata-only row in Nova DB with matrix_event_id (atomic)
    let message = crate::services::message_service::MessageService::store_matrix_message_metadata_db(
        db,
        conversation_id,
        user_id,
        event_id.as_str(),
        created_at,
    )
    .await?;

    let Some(message) = message else {
        debug!(event_id = %event_id, "Message already exists (by matrix_event_id), skipping");
        return Ok(());
    };

    info!(
        message_id = %message.id,
        conversation_id = %conversation_id,
        event_id = %event_id,
        "Matrix message saved to DB"
    );

    if matrix_first {
        return Ok(());
    }

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

/// Handle incoming Matrix encrypted events (m.room.encrypted)
///
/// This persists **metadata-only** using `matrix_event_id` even when the service user cannot
/// decrypt the message content (E2EE rooms).
pub async fn handle_matrix_encrypted_event(
    db: &Pool,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    matrix_first: bool,
    room: Room,
    event: SyncRoomEncryptedEvent,
) -> Result<(), AppError> {
    let original_event = match event {
        SyncRoomEncryptedEvent::Original(ev) => ev,
        SyncRoomEncryptedEvent::Redacted(_) => return Ok(()),
    };

    let room_id = room.room_id();
    let sender = &original_event.sender;
    let event_id = &original_event.event_id;

    debug!(
        room_id = %room_id,
        sender = %sender,
        event_id = %event_id,
        "Received Matrix encrypted event"
    );

    // 1. Look up conversation_id from Matrix room_id
    let conversation_id =
        match super::matrix_db::lookup_conversation_by_room_id(db, room_id.as_str()).await? {
            Some(id) => id,
            None => {
                warn!(
                    room_id = %room_id,
                    "Received encrypted event for unknown Matrix room, ignoring"
                );
                return Ok(());
            }
        };

    // 2. Extract Nova user_id from Matrix user_id
    let user_id = match extract_nova_user_id_from_matrix(sender) {
        Some(id) => id,
        None => {
            warn!(
                sender = %sender,
                "Failed to extract Nova user_id from Matrix sender (encrypted), ignoring"
            );
            return Ok(());
        }
    };

    // Skip encrypted replacements (edits).
    if matches!(
        original_event.content.relates_to,
        Some(EncryptedRelation::Replacement(_))
    ) {
        debug!(event_id = %event_id, "Encrypted replacement (edit) event; skipping metadata insert");
        return Ok(());
    }

    // 3. Check if this event already exists in our DB (by matrix_event_id)
    // This prevents duplicate processing and avoids bumping conversation_counters on conflicts.
    let client = db.get().await.map_err(|e| AppError::StartServer(format!("handle encrypted pool: {e}")))?;
    let existing: Option<Uuid> = client
        .query_opt(
            "SELECT id FROM messages WHERE matrix_event_id = $1",
            &[&event_id.as_str()],
        )
        .await
        .map_err(|e| AppError::StartServer(format!("check existing encrypted message: {e}")))?
        .map(|row| row.get(0));

    if existing.is_some() {
        debug!(
            event_id = %event_id,
            "Encrypted event already exists in DB, skipping"
        );
        return Ok(());
    }

    let created_at = ts_to_utc(Some(original_event.origin_server_ts));

    // 4. Persist metadata-only row in Nova DB with matrix_event_id (atomic + dedup via unique index)
    let message = crate::services::message_service::MessageService::store_matrix_message_metadata_db(
        db,
        conversation_id,
        user_id,
        event_id.as_str(),
        created_at,
    )
    .await?;

    let Some(message) = message else {
        debug!(event_id = %event_id, "Encrypted event already exists (by matrix_event_id), skipping");
        return Ok(());
    };

    info!(
        message_id = %message.id,
        conversation_id = %conversation_id,
        event_id = %event_id,
        "Matrix encrypted event saved to DB (metadata-only)"
    );

    if matrix_first {
        return Ok(());
    }

    // 5. Broadcast to WebSocket clients (no content; clients fetch from Matrix)
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
            "Failed to broadcast Matrix encrypted event via WebSocket"
        );
    }

    Ok(())
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
    fn test_ts_to_utc() {
        use matrix_sdk::ruma::UInt;

        let ts = MilliSecondsSinceUnixEpoch(UInt::new(1_700_000_000_123u64).unwrap());
        let dt = ts_to_utc(Some(ts));
        assert_eq!(
            dt,
            chrono::Utc
                .timestamp_millis_opt(1_700_000_000_123i64)
                .single()
                .unwrap()
        );
    }
}
