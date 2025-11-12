use crate::error::AppError;
use crate::middleware::guards::User;
use crate::services::call_service::CallService;
use crate::state::AppState;
use actix_web::{get, post, web, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

// ============================================================================
// Request/Response DTOs
// ============================================================================

/// Initiate a new call (1:1 or group)
#[derive(Deserialize)]
pub struct InitiateCallRequest {
    pub conversation_id: Uuid,
    pub initiator_sdp: String,
    /// Call type: "direct" (1:1) or "group"
    /// Default: "direct" for backward compatibility
    #[serde(default = "default_call_type")]
    pub call_type: String,
    /// Maximum number of participants
    /// Default: 2 for direct calls, must be >= 2 for group calls
    #[serde(default = "default_max_participants")]
    pub max_participants: i32,
    #[serde(default)]
    pub idempotency_key: Option<String>,
}

fn default_call_type() -> String {
    "direct".to_string()
}

fn default_max_participants() -> i32 {
    2
}

#[derive(Serialize)]
pub struct CallResponse {
    pub id: Uuid,
    pub status: String,
    pub created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_participants: Option<i32>,
}

/// Answer a 1:1 call (backward compatible)
#[derive(Deserialize)]
pub struct AnswerCallRequest {
    pub answer_sdp: String,
}

/// Join a group call
#[derive(Deserialize)]
pub struct JoinCallRequest {
    pub sdp: String,
}

/// Participant SDP information for P2P mesh connection
#[derive(Serialize)]
pub struct ParticipantSdpInfo {
    pub participant_id: Uuid,
    pub user_id: Uuid,
    /// SDP offer (for initiator) or answer (for other participants)
    pub sdp: String,
    pub joined_at: String,
    pub connection_state: String,
}

/// Response when joining a group call
#[derive(Serialize)]
pub struct JoinCallResponse {
    pub call_id: Uuid,
    pub conversation_id: Uuid,
    pub participant_id: Uuid,
    /// All existing participants with their SDPs for establishing P2P connections
    pub participants: Vec<ParticipantSdpInfo>,
    pub max_participants: i32,
    pub current_participant_count: usize,
}

/// Participant information (without SDP)
#[derive(Serialize)]
pub struct ParticipantInfo {
    pub id: Uuid,
    pub user_id: Uuid,
    pub joined_at: String,
    pub left_at: Option<String>,
    pub connection_state: String,
    pub has_audio: bool,
    pub has_video: bool,
}

/// Response for get participants endpoint
#[derive(Serialize)]
pub struct ParticipantsResponse {
    pub call_id: Uuid,
    pub participants: Vec<ParticipantInfo>,
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

/// Initiate a new video call (1:1 or group)
/// POST /conversations/:id/calls
#[post("/conversations/{conversation_id}/calls")]
pub async fn initiate_call(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    body: web::Json<InitiateCallRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
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

    // Validate call parameters
    let call_type = body.call_type.as_str();
    let max_participants = body.max_participants;

    if call_type != "direct" && call_type != "group" {
        return Err(crate::error::AppError::Config(
            "call_type must be 'direct' or 'group'".into(),
        ));
    }

    if call_type == "group" && max_participants < 2 {
        return Err(crate::error::AppError::Config(
            "max_participants must be >= 2 for group calls".into(),
        ));
    }

    if max_participants > 50 {
        return Err(crate::error::AppError::Config(
            "max_participants cannot exceed 50".into(),
        ));
    }

    // Create the call
    let call_id = CallService::initiate_call(
        &state.db,
        conversation_id,
        user.id,
        &body.initiator_sdp,
        call_type,
        max_participants,
    )
    .await?;

    // Broadcast call initiated event
    let payload = serde_json::json!({
        "type": "call.initiated",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "initiator_id": user.id,
        "call_type": call_type,
        "max_participants": max_participants,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    crate::websocket::events::broadcast_payload_str(
        &state.registry,
        &state.redis,
        conversation_id,
        payload,
    )
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "failed to broadcast call event");
        crate::error::AppError::Internal
    })?;

    Ok(HttpResponse::Created().json(CallResponse {
        id: call_id,
        status: "ringing".to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
        call_type: Some(call_type.to_string()),
        max_participants: Some(max_participants),
    }))
}

/// Answer an incoming call
/// POST /calls/:id/answer
#[post("/calls/{call_id}/answer")]
pub async fn answer_call(
    state: web::Data<AppState>,
    user: User,
    call_id: web::Path<Uuid>,
    body: web::Json<AnswerCallRequest>,
) -> Result<HttpResponse, AppError> {
    let call_id = call_id.into_inner();
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
    let _participant_id =
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

    crate::websocket::events::broadcast_payload_str(
        &state.registry,
        &state.redis,
        conversation_id,
        payload,
    )
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "failed to broadcast call event");
        crate::error::AppError::Internal
    })?;

    Ok(HttpResponse::Ok().json(CallResponse {
        id: call_id,
        status: "connected".to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
        call_type: None,
        max_participants: None,
    }))
}

/// Reject/decline an incoming call
/// POST /calls/:id/reject
#[post("/calls/{call_id}/reject")]
pub async fn reject_call(
    state: web::Data<AppState>,
    user: User,
    call_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let call_id = call_id.into_inner();
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

    crate::websocket::events::broadcast_payload_str(
        &state.registry,
        &state.redis,
        conversation_id,
        payload,
    )
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "failed to broadcast call event");
        crate::error::AppError::Internal
    })?;

    Ok(HttpResponse::NoContent().finish())
}

/// End an active call
/// POST /calls/:id/end
#[post("/calls/{call_id}/end")]
pub async fn end_call(
    state: web::Data<AppState>,
    user: User,
    call_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let call_id = call_id.into_inner();
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

    crate::websocket::events::broadcast_payload_str(
        &state.registry,
        &state.redis,
        conversation_id,
        payload,
    )
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "failed to broadcast call event");
        crate::error::AppError::Internal
    })?;

    Ok(HttpResponse::NoContent().finish())
}

/// Join a group call (or answer a 1:1 call)
/// POST /calls/:id/join
pub async fn join_call(
    state: web::Data<AppState>,
    user: User,
    call_id: web::Path<Uuid>,
    body: web::Json<JoinCallRequest>,
) -> Result<HttpResponse, AppError> {
    let call_id = call_id.into_inner();
    // Get call details
    let call_row = sqlx::query(
        "SELECT conversation_id, status, max_participants, call_type FROM call_sessions WHERE id = $1",
    )
    .bind(call_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

    let call_row =
        call_row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

    let conversation_id: Uuid = call_row.get("conversation_id");
    let status: String = call_row.get("status");
    let max_participants: i32 = call_row.get("max_participants");
    let call_type: String = call_row.get("call_type");

    // Verify user is a member of the conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Verify call is in valid state
    if status != "ringing" && status != "connected" {
        return Err(crate::error::AppError::Config("Call is not active".into()));
    }

    // Join the call (this checks for duplicate joins and capacity)
    let (participant_id, existing_participants) =
        CallService::join_call(&state.db, call_id, user.id, &body.sdp, max_participants).await?;

    let participant_count = existing_participants.len() + 1; // +1 for the joining user

    // Broadcast participant joined event
    let payload = serde_json::json!({
        "type": "call.participant_joined",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "participant_id": participant_id,
        "user_id": user.id,
        "sdp": body.sdp,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    crate::websocket::events::broadcast_payload_str(
        &state.registry,
        &state.redis,
        conversation_id,
        payload,
    )
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "failed to broadcast call event");
        crate::error::AppError::Internal
    })?;

    // For backward compatibility: emit call.answered if this is a 1:1 call
    if call_type == "direct" && participant_count == 2 {
        let payload = serde_json::json!({
            "type": "call.answered",
            "conversation_id": conversation_id,
            "call_id": call_id,
            "answerer_id": user.id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        })
        .to_string();

        let _ = crate::websocket::events::broadcast_payload_str(
            &state.registry,
            &state.redis,
            conversation_id,
            payload,
        )
        .await;
    }

    Ok(HttpResponse::Ok().json(JoinCallResponse {
        call_id,
        conversation_id,
        participant_id,
        participants: existing_participants,
        max_participants,
        current_participant_count: participant_count,
    }))
}

/// Leave a group call
/// POST /calls/:id/leave
pub async fn leave_call(
    state: web::Data<AppState>,
    user: User,
    call_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let call_id = call_id.into_inner();
    // Get call details
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

    // Leave the call
    let participant_id = CallService::leave_call(&state.db, call_id, user.id).await?;

    // Broadcast participant left event
    let payload = serde_json::json!({
        "type": "call.participant_left",
        "conversation_id": conversation_id,
        "call_id": call_id,
        "participant_id": participant_id,
        "user_id": user.id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    })
    .to_string();

    crate::websocket::events::broadcast_payload_str(
        &state.registry,
        &state.redis,
        conversation_id,
        payload,
    )
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "failed to broadcast call event");
        crate::error::AppError::Internal
    })?;

    Ok(HttpResponse::NoContent().finish())
}

/// Get participants of a call
/// GET /calls/:id/participants
pub async fn get_participants(
    state: web::Data<AppState>,
    user: User,
    call_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let call_id = call_id.into_inner();
    // Get call details to verify conversation membership
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

    // Get participants
    let participants = CallService::get_participants(&state.db, call_id).await?;

    Ok(HttpResponse::Ok().json(ParticipantsResponse {
        call_id,
        participants,
    }))
}

/// Get call history for the current user
/// GET /calls/history
pub async fn get_call_history(
    state: web::Data<AppState>,
    user: User,
) -> Result<HttpResponse, AppError> {
    let limit = 50i64;
    let offset = 0i64;

    let history = CallService::get_call_history(&state.db, user.id, limit, offset).await?;

    let items: Vec<CallHistoryItem> = history
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

    Ok(HttpResponse::Ok().json(items))
}

// TODO: Implement ice_candidate - handle ICE candidate exchange
#[post("/calls/ice-candidate")]
pub async fn ice_candidate(
    _state: web::Data<AppState>,
    _user: User,
    _body: web::Json<serde_json::Value>,
) -> Result<HttpResponse, AppError> {
    // TODO: Implement ICE candidate exchange
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "received"
    })))
}

// TODO: Implement get_ice_servers - get STUN/TURN server configuration
#[get("/calls/ice-servers")]
pub async fn get_ice_servers(
    _state: web::Data<AppState>,
    _user: User,
) -> Result<HttpResponse, AppError> {
    // TODO: Implement ICE server configuration
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "iceServers": []
    })))
}
