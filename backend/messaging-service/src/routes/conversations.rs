use crate::middleware::guards::User;
use crate::{
    services::conversation_service::{ConversationService, PrivacyMode},
    state::AppState,
};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Serialize)]
pub struct ConversationResponse {
    pub id: Uuid,
    pub member_count: i32,
    pub last_message_id: Option<Uuid>,
}

#[derive(Serialize)]
pub struct GroupConversationResponse {
    pub id: Uuid,
    pub kind: String,
    pub name: String,
    pub description: Option<String>,
    pub avatar_url: Option<String>,
    pub member_count: i32,
    pub privacy_mode: String,
}

#[derive(Serialize)]
pub struct ConversationKeyResponse {
    pub conversation_id: Uuid,
    pub key_base64: String,
    pub key_version: i32,
    pub cipher: &'static str,
    pub nonce_size: usize,
}

#[derive(Deserialize)]
pub struct CreateConversationRequest {
    pub user_a: Uuid,
    pub user_b: Uuid,
}

#[derive(Deserialize)]
pub struct CreateGroupConversationRequest {
    pub name: String,
    pub description: Option<String>,
    pub avatar_url: Option<String>,
    pub member_ids: Vec<Uuid>,
    pub privacy_mode: Option<String>, // "strict_e2e" or "search_enabled"
}

pub async fn create_conversation(
    State(state): State<AppState>,
    _user: User, // Authenticated user from JWT
    Json(body): Json<CreateConversationRequest>,
) -> Result<Json<ConversationResponse>, crate::error::AppError> {
    // Security: Can only create conversations with yourself or another user
    // For now, we allow creation. In future, might want to verify user_a == authenticated user
    let id = ConversationService::create_direct_conversation(&state.db, body.user_a, body.user_b)
        .await?;
    // fetch details for response
    let details = ConversationService::get_conversation_db(&state.db, id).await?;
    Ok(Json(ConversationResponse {
        id: details.id,
        member_count: details.member_count,
        last_message_id: details.last_message_id,
    }))
}

pub async fn get_conversation(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
) -> Result<Json<ConversationResponse>, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member of conversation
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    let details = ConversationService::get_conversation_db(&state.db, conversation_id).await?;
    Ok(Json(ConversationResponse {
        id: details.id,
        member_count: details.member_count,
        last_message_id: details.last_message_id,
    }))
}

#[derive(Deserialize)]
pub struct MarkAsReadRequest {
    // user_id is now obtained from JWT authentication
}

/// Create a group conversation
/// POST /conversations/groups
/// Authenticated users can create groups with specified members
pub async fn create_group_conversation(
    State(state): State<AppState>,
    user: User, // Creator of the group (becomes owner)
    Json(body): Json<CreateGroupConversationRequest>,
) -> Result<(StatusCode, Json<GroupConversationResponse>), crate::error::AppError> {
    // Save values before they are moved
    let name = body.name.clone();
    let description = body.description.clone();
    let avatar_url = body.avatar_url.clone();
    let privacy_mode_str = body.privacy_mode.clone();

    // Parse privacy mode from string
    let privacy_mode = if let Some(ref mode_str) = privacy_mode_str {
        match mode_str.as_str() {
            "search_enabled" => Some(PrivacyMode::SearchEnabled),
            _ => Some(PrivacyMode::StrictE2e),
        }
    } else {
        None
    };

    // Create the group conversation with the authenticated user as creator
    let conversation_id = ConversationService::create_group_conversation(
        &state.db,
        user.id,
        name.clone(),
        description.clone(),
        avatar_url.clone(),
        body.member_ids,
        privacy_mode,
    )
    .await?;

    // Fetch the created conversation details
    let details = ConversationService::get_conversation_db(&state.db, conversation_id).await?;

    let response = GroupConversationResponse {
        id: details.id,
        kind: "group".to_string(),
        name,
        description,
        avatar_url,
        member_count: details.member_count,
        privacy_mode: match privacy_mode_str.as_deref() {
            Some("search_enabled") => "search_enabled".to_string(),
            _ => "strict_e2e".to_string(),
        },
    };

    Ok((StatusCode::CREATED, Json(response)))
}

/// GET /conversations/{id}/encryption-key
/// Returns the symmetric conversation key for Strict E2E conversations.
pub async fn get_conversation_key(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
) -> Result<Json<ConversationKeyResponse>, crate::error::AppError> {
    let conversation_id = id;

    crate::middleware::guards::ConversationMember::verify(
        &state.db,
        user.id,
        conversation_id,
    )
    .await?;

    let privacy_mode =
        ConversationService::get_privacy_mode(&state.db, conversation_id).await?;

    if !matches!(privacy_mode, PrivacyMode::StrictE2e) {
        return Err(crate::error::AppError::BadRequest(
            "Conversation does not use strict_e2e privacy mode".into(),
        ));
    }

    let key = state.encryption.conversation_key(conversation_id);
    let key_b64 = general_purpose::STANDARD.encode(key);

    Ok(Json(ConversationKeyResponse {
        conversation_id,
        key_base64: key_b64,
        key_version: 1,
        cipher: "xsalsa20poly1305",
        nonce_size: 24,
    }))
}

/// Delete/dissolve a group conversation (owner only)
/// DELETE /conversations/{id}
pub async fn delete_group(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, crate::error::AppError> {
    let conversation_id = id;

    // Delete the group (ConversationService will check permissions)
    ConversationService::delete_group_conversation(&state.db, conversation_id, user.id).await?;

    // Broadcast group deleted event to all members
    let payload = serde_json::json!({
        "type": "group_deleted",
        "conversation_id": conversation_id,
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
        tracing::error!(error = %e, "failed to broadcast conversation event");
        crate::error::AppError::Internal
    })?;

    Ok(StatusCode::NO_CONTENT)
}

/// Leave a group conversation
/// POST /conversations/{id}/leave
pub async fn leave_group(
    State(state): State<AppState>,
    user: User,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, crate::error::AppError> {
    let conversation_id = id;

    // Verify user is member
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    // Remove user from the group
    ConversationService::remove_member(&state.db, conversation_id, user.id, user.id).await?;

    // Broadcast member left event
    let payload = serde_json::json!({
        "type": "member_left",
        "conversation_id": conversation_id,
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
        tracing::error!(error = %e, "failed to broadcast conversation event");
        crate::error::AppError::Internal
    })?;

    Ok(StatusCode::NO_CONTENT)
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
    let _member =
        crate::middleware::guards::ConversationMember::verify(&state.db, user.id, conversation_id)
            .await?;

    ConversationService::mark_as_read(&state.db, conversation_id, user.id).await?;

    // Broadcast read receipt to conversation members via WebSocket/Redis
    let payload = serde_json::json!({
        "type": "read_receipt",
        "conversation_id": conversation_id,
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
        tracing::error!(error = %e, "failed to broadcast conversation event");
        crate::error::AppError::Internal
    })?;

    Ok(StatusCode::NO_CONTENT)
}
