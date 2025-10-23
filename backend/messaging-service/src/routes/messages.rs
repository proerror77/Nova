use axum::{extract::{Path, State}, Json};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{services::{message_service::MessageService, conversation_service::ConversationService}, state::AppState};
use crate::websocket::pubsub;

#[derive(Deserialize)]
pub struct SendMessageRequest {
    pub sender_id: Uuid,
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
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<SendMessageRequest>,
) -> Result<Json<SendMessageResponse>, crate::error::AppError> {
    // Permission: sender must be member of conversation
    if !ConversationService::is_member(&state.db, conversation_id, body.sender_id).await? {
        return Err(crate::error::AppError::Forbidden("not a member".into()));
    }
    let (id, seq) = MessageService::send_message_db(
        &state.db,
        conversation_id,
        body.sender_id,
        body.plaintext.as_bytes(),
        body.idempotency_key.as_deref(),
    )
    .await?;
    let payload = serde_json::json!({
        "type": "message",
        "conversation_id": conversation_id,
        "message": {"id": id, "sender_id": body.sender_id, "sequence_number": seq}
    }).to_string();
    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;
    Ok(Json(SendMessageResponse { id, sequence_number: seq }))
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
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<Vec<MessageDto>>, crate::error::AppError> {
    let rows = MessageService::get_message_history_db(&state.db, conversation_id).await?;
    Ok(Json(rows))
}

#[derive(Deserialize)]
pub struct UpdateMessageRequest {
    pub plaintext: String,
}

pub async fn update_message(
    State(state): State<AppState>,
    Path(message_id): Path<Uuid>,
    Json(body): Json<UpdateMessageRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    MessageService::update_message_db(&state.db, message_id, body.plaintext.as_bytes()).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn delete_message(
    State(state): State<AppState>,
    Path(message_id): Path<Uuid>,
) -> Result<StatusCode, crate::error::AppError> {
    MessageService::soft_delete_message_db(&state.db, message_id).await?;
    Ok(StatusCode::NO_CONTENT)
}
