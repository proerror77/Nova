use crate::middleware::guards::User;
use crate::services::call_service::CallService;
use crate::state::AppState;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

// ============================================================================
// Request/Response DTOs
// ============================================================================

#[derive(Deserialize)]
pub struct InitiateCallRequest {
    pub conversation_id: Uuid,
    pub initiator_sdp: String,
    #[serde(default)]
    pub idempotency_key: Option<String>,
}

#[derive(Serialize)]
pub struct CallResponse {
    pub id: Uuid,
    pub status: String,
    pub created_at: String,
}

#[derive(Deserialize)]
pub struct AnswerCallRequest {
    pub answer_sdp: String,
}

#[derive(Serialize)]
pub struct ParticipantInfo {
    pub id: Uuid,
    pub user_id: Uuid,
    pub answer_sdp: Option<String>,
    pub joined_at: String,
}

#[derive(Serialize)]
pub struct CallDetailsResponse {
    pub id: Uuid,
    pub status: String,
    pub initiator_sdp: String,
    pub participants: Vec<ParticipantInfo>,
}

#[derive(Serialize)]
pub struct CallHistoryItem {
    pub id: Uuid,
    pub status: String,
    pub duration_ms: i32,
    pub participant_count: i64,
}

// ============================================================================
// API Handlers
// ============================================================================

/// Initiate a new video call
/// POST /conversations/:id/calls
pub async fn initiate_call(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<InitiateCallRequest>,
) -> Result<(StatusCode, Json<CallResponse>), crate::error::AppError> {
    // Verify user is a member of the conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Verify conversation is a direct message or group
    let _conv = crate::services::conversation_service::ConversationService::get_conversation_db(
        &state.db,
        conversation_id,
    )
    .await?;

    // Create the call
    let call_id =
        CallService::initiate_call(&state.db, conversation_id, user.id, &body.initiator_sdp)
            .await?;

    // Broadcast call initiated event
    let payload = serde_json::json!({
        "type": "call.initiated",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "initiator_id": user.id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    state
        .registry
        .broadcast(
            conversation_id,
            axum::extract::ws::Message::Text(payload.clone()),
        )
        .await;
    let _ = crate::websocket::pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok((
        StatusCode::CREATED,
        Json(CallResponse {
            id: call_id,
            status: "ringing".to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        }),
    ))
}

/// Answer an incoming call
/// POST /calls/:id/answer
pub async fn answer_call(
    State(state): State<AppState>,
    user: User,
    Path(call_id): Path<Uuid>,
    Json(body): Json<AnswerCallRequest>,
) -> Result<(StatusCode, Json<CallResponse>), crate::error::AppError> {
    // Get the call to verify it exists and get conversation_id
    let call_row =
        sqlx::query("SELECT id, conversation_id, status FROM call_sessions WHERE id = $1")
            .bind(call_id)
            .fetch_optional(&state.db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

    let call_row =
        call_row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

    let conversation_id: Uuid = call_row.get("conversation_id");

    // Verify user is a member of the conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Answer the call
    let participant_id =
        CallService::answer_call(&state.db, call_id, user.id, &body.answer_sdp).await?;

    // Broadcast call answered event
    let payload = serde_json::json!({
        "type": "call.answered",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "answerer_id": user.id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    state
        .registry
        .broadcast(
            conversation_id,
            axum::extract::ws::Message::Text(payload.clone()),
        )
        .await;
    let _ = crate::websocket::pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok((
        StatusCode::OK,
        Json(CallResponse {
            id: call_id,
            status: "connected".to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        }),
    ))
}

/// Reject/decline an incoming call
/// POST /calls/:id/reject
pub async fn reject_call(
    State(state): State<AppState>,
    user: User,
    Path(call_id): Path<Uuid>,
) -> Result<StatusCode, crate::error::AppError> {
    // Get the call to verify it exists and get conversation_id
    let call_row = sqlx::query("SELECT conversation_id FROM call_sessions WHERE id = $1")
        .bind(call_id)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

    let call_row =
        call_row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

    let conversation_id: Uuid = call_row.get("conversation_id");

    // Verify user is a member of the conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Reject the call
    CallService::reject_call(&state.db, call_id).await?;

    // Broadcast call rejected event
    let payload = serde_json::json!({
        "type": "call.rejected",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "rejected_by": user.id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    state
        .registry
        .broadcast(
            conversation_id,
            axum::extract::ws::Message::Text(payload.clone()),
        )
        .await;
    let _ = crate::websocket::pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}

/// End an active call
/// POST /calls/:id/end
pub async fn end_call(
    State(state): State<AppState>,
    user: User,
    Path(call_id): Path<Uuid>,
) -> Result<StatusCode, crate::error::AppError> {
    // Get the call to verify it exists and get conversation_id
    let call_row = sqlx::query("SELECT conversation_id FROM call_sessions WHERE id = $1")
        .bind(call_id)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

    let call_row =
        call_row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

    let conversation_id: Uuid = call_row.get("conversation_id");

    // Verify user is a member of the conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // End the call
    CallService::end_call(&state.db, call_id).await?;

    // Broadcast call ended event
    let payload = serde_json::json!({
        "type": "call.ended",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "ended_by": user.id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    state
        .registry
        .broadcast(
            conversation_id,
            axum::extract::ws::Message::Text(payload.clone()),
        )
        .await;
    let _ = crate::websocket::pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}

/// Get call history for the current user
/// GET /calls/history
pub async fn get_call_history(
    State(state): State<AppState>,
    user: User,
) -> Result<Json<Vec<CallHistoryItem>>, crate::error::AppError> {
    let limit = 50i64;
    let offset = 0i64;

    let history = CallService::get_call_history(&state.db, user.id, limit, offset).await?;

    let items = history
        .into_iter()
        .map(
            |(id, status, duration_ms, participant_count)| CallHistoryItem {
                id,
                status,
                duration_ms,
                participant_count,
            },
        )
        .collect();

    Ok(Json(items))
}
