use axum::{extract::{Path, State, Query}, Json};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use sqlx::Row;

use crate::services::message_service::MessageService;
use crate::state::AppState;
use crate::middleware::guards::User;
use crate::websocket::pubsub;

#[derive(Deserialize)]
pub struct SendMessageRequest {
    pub plaintext: String,
    pub idempotency_key: Option<String>,
}

#[derive(Serialize)]
pub struct SendMessageResponse {
    pub id: Uuid,
    pub sequence_number: i64,
}

pub async fn send_message(
    State(state): State<AppState>,
    user: User,  // Authenticated user from JWT
    Path(id): Path<Uuid>,
    Json(body): Json<SendMessageRequest>,
) -> Result<Json<SendMessageResponse>, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member of conversation and has permission to send
    let member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    member.can_send()?;

    let (msg_id, seq) = MessageService::send_message_db(
        &state.db,
        conversation_id,
        user.id,
        body.plaintext.as_bytes(),
        body.idempotency_key.as_deref(),
    )
    .await?;
    let payload = serde_json::json!({
        "type": "message",
        "conversation_id": conversation_id,
        "message": {"id": msg_id, "sender_id": user.id, "sequence_number": seq}
    }).to_string();
    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;
    Ok(Json(SendMessageResponse { id: msg_id, sequence_number: seq }))
}

#[derive(Serialize)]
pub struct MessageDto {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub sequence_number: i64,
    pub created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recalled_at: Option<String>,
}

pub async fn get_message_history(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
) -> Result<Json<Vec<MessageDto>>, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member of conversation
    let _member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    let rows = MessageService::get_message_history_db(&state.db, conversation_id).await?;
    Ok(Json(rows))
}

#[derive(Deserialize)]
pub struct UpdateMessageRequest {
    pub plaintext: String,
    pub version_number: i32,  // Required for optimistic locking
    pub reason: Option<String>,  // Optional edit reason for audit trail
}

/// Update message with optimistic locking (version control)
///
/// Business rules:
/// - Only message sender can edit (admins cannot edit others' messages)
/// - Edit window: 15 minutes after creation
/// - Version number must match current version (prevents lost updates)
/// - On conflict: returns 409 with server version
/// - Edit history is automatically recorded via database trigger
pub async fn update_message(
    State(state): State<AppState>,
    user: User,
    Path(message_id): Path<Uuid>,
    Json(body): Json<UpdateMessageRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Edit window limit (15 minutes)
    const MAX_EDIT_MINUTES: i64 = 15;

    // Start transaction for atomic operation
    let mut tx = state.db.begin().await?;

    // 1. Get message with FOR UPDATE lock (prevents concurrent modifications)
    let msg_row = sqlx::query(
        "SELECT conversation_id, sender_id, version_number, created_at, content
         FROM messages
         WHERE id = $1
         FOR UPDATE"
    )
    .bind(message_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(crate::error::AppError::NotFound)?;

    let conversation_id: Uuid = msg_row.get("conversation_id");
    let sender_id: Uuid = msg_row.get("sender_id");
    let current_version: i32 = msg_row.get("version_number");
    let created_at: chrono::DateTime<chrono::Utc> = msg_row.get("created_at");
    let old_content: Vec<u8> = msg_row.get("content");

    // 2. Verify ownership (only sender can edit their own messages)
    if sender_id != user.id {
        return Err(crate::error::AppError::Forbidden);
    }

    // 3. Verify user is member of conversation
    let _member = crate::middleware::guards::ConversationMember::verify(
        &state.db,  // Use main DB pool for member check (outside transaction)
        user.id,
        conversation_id,
    ).await?;

    // 4. Check edit time window
    let elapsed_minutes = (chrono::Utc::now() - created_at).num_minutes();
    if elapsed_minutes > MAX_EDIT_MINUTES {
        return Err(crate::error::AppError::EditWindowExpired {
            max_edit_minutes: MAX_EDIT_MINUTES,
        });
    }

    // 5. Optimistic locking check: version number must match
    if body.version_number != current_version {
        // Conflict: client version is stale
        let server_content = String::from_utf8_lossy(&old_content).to_string();
        return Err(crate::error::AppError::VersionConflict {
            current_version,
            client_version: body.version_number,
            server_content,
        });
    }

    // 6. Update message with version increment (CAS - Compare-And-Swap)
    let update_result = sqlx::query(
        r#"
        UPDATE messages
        SET
            content = $1,
            version_number = version_number + 1,
            updated_at = NOW()
        WHERE id = $2 AND version_number = $3
        RETURNING id, conversation_id, version_number
        "#
    )
    .bind(body.plaintext.as_bytes())
    .bind(message_id)
    .bind(current_version)  // CAS: only update if version matches
    .fetch_optional(&mut *tx)
    .await?;

    // 7. Verify update succeeded (if None, version changed concurrently)
    let updated = update_result.ok_or_else(|| {
        // Concurrent update detected: re-fetch current state
        let server_content = String::from_utf8_lossy(&old_content).to_string();
        crate::error::AppError::VersionConflict {
            current_version: current_version + 1,  // Version was incremented by concurrent update
            client_version: body.version_number,
            server_content,
        }
    })?;

    let new_version: i32 = updated.get("version_number");

    // 8. Commit transaction (trigger will record version history)
    tx.commit().await?;

    // 9. Broadcast message edit event to conversation members
    let payload = serde_json::json!({
        "type": "message_edited",
        "conversation_id": conversation_id,
        "message_id": message_id,
        "version_number": new_version,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}

pub async fn delete_message(
    State(state): State<AppState>,
    user: User,
    Path(message_id): Path<Uuid>,
) -> Result<StatusCode, crate::error::AppError> {
    // TOCTOU fix: Use atomic transaction for permission check + delete
    let mut tx = state.db.begin().await?;

    // Get message details to verify permissions and find conversation
    let msg_row = sqlx::query("SELECT conversation_id, sender_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get message: {e}")))?
        .ok_or(crate::error::AppError::NotFound)?;

    let conversation_id: Uuid = msg_row.get("conversation_id");
    let sender_id: Uuid = msg_row.get("sender_id");

    // Verify user is member of conversation
    let member = crate::middleware::guards::ConversationMember::verify(
        &state.db,  // Use main DB pool for member check
        user.id,
        conversation_id,
    ).await?;

    // Verify user is the message sender or is an admin
    let is_own_message = sender_id == user.id;
    member.can_delete_message(is_own_message)?;

    // Delete message atomically with permission verification
    let deleted = sqlx::query(
        "UPDATE messages SET deleted_at = NOW()
         WHERE id = $1 AND sender_id = $2
         RETURNING id, conversation_id"
    )
        .bind(message_id)
        .bind(user.id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("delete message: {e}")))?
        .ok_or(crate::error::AppError::Forbidden)?;  // Fails if user is not the sender

    tx.commit().await?;

    let deleted_conversation_id: Uuid = deleted.get("conversation_id");

    // Broadcast message delete event to conversation members via WebSocket/Redis
    let payload = serde_json::json!({
        "type": "message_deleted",
        "conversation_id": deleted_conversation_id,
        "message_id": message_id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(deleted_conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, deleted_conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}

// Search endpoint removed for security compliance
// Message search functionality has been moved to client-side local indexing
// to maintain true end-to-end encryption.
//
// Previous endpoint: GET /conversations/:id/messages/search
// Replacement: Client apps should implement local search using decrypted message cache

#[derive(Serialize)]
pub struct RecallMessageResponse {
    pub message_id: Uuid,
    pub recalled_at: String,
    pub status: String,  // Always "recalled"
}

/// Recall (unsend) a message within 5 minutes of sending
///
/// Business rules:
/// - Only message sender or conversation admin can recall
/// - Message must be within 5 minutes of creation
/// - Already recalled messages cannot be recalled again
/// - Recall event is broadcast to all conversation members via WebSocket
/// - Audit log entry is created in message_recalls table
pub async fn recall_message(
    State(state): State<AppState>,
    user: User,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<RecallMessageResponse>, crate::error::AppError> {
    // 1. Verify user is member of conversation and get permissions
    let member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    // 2. Get message and verify it belongs to this conversation
    let msg_row = sqlx::query(
        "SELECT sender_id, created_at, recalled_at FROM messages WHERE id = $1 AND conversation_id = $2"
    )
    .bind(message_id)
    .bind(conversation_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("fetch message: {e}")))?
    .ok_or(crate::error::AppError::NotFound)?;

    let sender_id: Uuid = msg_row.get("sender_id");
    let created_at: chrono::DateTime<chrono::Utc> = msg_row.get("created_at");
    let recalled_at: Option<chrono::DateTime<chrono::Utc>> = msg_row.get("recalled_at");

    // 3. Verify user has permission to recall (sender or admin)
    let is_own_message = sender_id == user.id;
    if !is_own_message && !member.is_admin() {
        return Err(crate::error::AppError::Forbidden);
    }

    // 4. Check if message is already recalled
    if recalled_at.is_some() {
        return Err(crate::error::AppError::AlreadyRecalled);
    }

    // 5. Check 5-minute recall window
    const RECALL_WINDOW_MINUTES: i64 = 5;
    let now = chrono::Utc::now();
    let elapsed_minutes = (now - created_at).num_minutes();

    if elapsed_minutes > RECALL_WINDOW_MINUTES {
        return Err(crate::error::AppError::RecallWindowExpired {
            created_at,
            max_recall_minutes: RECALL_WINDOW_MINUTES,
        });
    }

    // 6. Execute recall in transaction (update message + insert audit log)
    let mut tx = state.db.begin().await?;

    // Update message to mark as recalled
    sqlx::query("UPDATE messages SET recalled_at = $1 WHERE id = $2")
        .bind(now)
        .bind(message_id)
        .execute(&mut *tx)
        .await?;

    // Insert audit log entry
    sqlx::query(
        "INSERT INTO message_recalls (message_id, recalled_by_user_id, recalled_at) VALUES ($1, $2, $3)"
    )
    .bind(message_id)
    .bind(user.id)
    .bind(now)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    // 7. Broadcast recall event to all conversation members
    let payload = serde_json::json!({
        "type": "message_recalled",
        "conversation_id": conversation_id,
        "message_id": message_id,
        "recalled_by": user.id,
        "recalled_at": now.to_rfc3339(),
    });

    // Broadcast via WebSocket registry (in-process connections)
    state.registry.broadcast(
        conversation_id,
        axum::extract::ws::Message::Text(payload.to_string())
    ).await;

    // Broadcast via Redis pub/sub (cross-instance)
    let _ = pubsub::publish(&state.redis, conversation_id, &payload.to_string()).await;

    // 8. Return success response
    Ok(Json(RecallMessageResponse {
        message_id,
        recalled_at: now.to_rfc3339(),
        status: "recalled".to_string(),
    }))
}
