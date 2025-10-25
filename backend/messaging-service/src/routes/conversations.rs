use axum::{extract::{Path, State}, Json, http::StatusCode};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::{services::conversation_service::ConversationService, state::AppState};
use crate::middleware::guards::User;

#[derive(Serialize)]
pub struct ConversationResponse {
    pub id: Uuid,
    pub member_count: i32,
    pub last_message_id: Option<Uuid>,
}

#[derive(Deserialize)]
pub struct CreateConversationRequest { pub user_a: Uuid, pub user_b: Uuid }

pub async fn create_conversation(
    State(state): State<AppState>,
    _user: User,  // Authenticated user from JWT
    Json(body): Json<CreateConversationRequest>,
) -> Result<Json<ConversationResponse>, crate::error::AppError> {
    // Security: Can only create conversations with yourself or another user
    // For now, we allow creation. In future, might want to verify user_a == authenticated user
    let id = ConversationService::create_direct_conversation(&state.db, body.user_a, body.user_b).await?;
    // fetch details for response
    let details = ConversationService::get_conversation_db(&state.db, id).await?;
    Ok(Json(ConversationResponse { id: details.id, member_count: details.member_count, last_message_id: details.last_message_id }))
}

pub async fn get_conversation(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
) -> Result<Json<ConversationResponse>, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member of conversation
    let _member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    let details = ConversationService::get_conversation_db(&state.db, conversation_id).await?;
    Ok(Json(ConversationResponse { id: details.id, member_count: details.member_count, last_message_id: details.last_message_id }))
}

#[derive(Deserialize)]
pub struct MarkAsReadRequest {
    // user_id is now obtained from JWT authentication
}

/// Mark conversation as read (update last_read_at timestamp)
pub async fn mark_as_read(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
    Json(_body): Json<MarkAsReadRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member of conversation
    let _member = crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    ).await?;

    ConversationService::mark_as_read(&state.db, conversation_id, user.id).await?;

    // Broadcast read receipt to conversation members via WebSocket/Redis
    let payload = serde_json::json!({
        "type": "read_receipt",
        "conversation_id": conversation_id,
        "user_id": user.id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = crate::websocket::pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}
