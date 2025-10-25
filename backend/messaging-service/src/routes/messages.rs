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
}

pub async fn update_message(
    State(state): State<AppState>,
    user: User,
    Path(message_id): Path<Uuid>,
    Json(body): Json<UpdateMessageRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Get message details to verify ownership and find conversation
    let msg_row = sqlx::query("SELECT conversation_id, sender_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get message: {e}")))?;
    let conversation_id: Uuid = msg_row.get("conversation_id");
    let sender_id: Uuid = msg_row.get("sender_id");

    // Verify user is member of conversation
    let member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    // Verify user is the message sender or is an admin
    let is_own_message = sender_id == user.id;
    member.can_delete_message(is_own_message)?;

    MessageService::update_message_db(&state.db, message_id, body.plaintext.as_bytes()).await?;

    // Broadcast message edit event to conversation members via WebSocket/Redis
    let payload = serde_json::json!({
        "type": "message_edited",
        "conversation_id": conversation_id,
        "message_id": message_id,
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
    // Get message details to verify permissions and find conversation
    let msg_row = sqlx::query("SELECT conversation_id, sender_id FROM messages WHERE id = $1")
        .bind(message_id)
        .fetch_one(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get message: {e}")))?;
    let conversation_id: Uuid = msg_row.get("conversation_id");
    let sender_id: Uuid = msg_row.get("sender_id");

    // Verify user is member of conversation
    let member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    // Verify user is the message sender or is an admin
    let is_own_message = sender_id == user.id;
    member.can_delete_message(is_own_message)?;

    MessageService::soft_delete_message_db(&state.db, message_id).await?;

    // Broadcast message delete event to conversation members via WebSocket/Redis
    let payload = serde_json::json!({
        "type": "message_deleted",
        "conversation_id": conversation_id,
        "message_id": message_id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct SearchMessagesRequest {
    pub q: String,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub sort_by: Option<String>,
}

#[derive(Serialize)]
pub struct SearchMessagesResponse {
    pub data: Vec<MessageDto>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
    pub has_more: bool,
}

pub async fn search_messages(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
    Query(query_params): Query<SearchMessagesRequest>,
) -> Result<Json<SearchMessagesResponse>, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member of conversation
    let _member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    let limit = query_params.limit.unwrap_or(20).min(100);
    let offset = query_params.offset.unwrap_or(0).max(0);

    let (results, total) = MessageService::search_messages(
        &state.db,
        conversation_id,
        &query_params.q,
        limit,
        offset,
        query_params.sort_by.as_deref(),
    ).await?;

    let has_more = (offset + limit) < total;

    Ok(Json(SearchMessagesResponse {
        data: results,
        total,
        limit,
        offset,
        has_more,
    }))
}
