use axum::{extract::{Path, State}, Json, http::StatusCode};
use serde::Deserialize;
use uuid::Uuid;
use crate::{state::AppState, websocket::pubsub, middleware::guards::User};

#[derive(Deserialize)]
pub struct AddMemberRequest {
    pub user_id: Uuid,
    pub role: Option<String>,  // 'admin', 'member' (default)
}

#[derive(Deserialize)]
pub struct UpdateMemberRequest {
    pub role: String,  // 'admin', 'member'
}

/// POST /conversations/{id}/members
/// Add a member to a group conversation
pub async fn add_member(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<AddMemberRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Verify requester is admin of conversation
    let _admin = crate::middleware::guards::ConversationAdmin::verify(&state.db, user.id, conversation_id).await?;

    // Check if conversation is a group (not direct)
    let conv_type: String = sqlx::query_scalar::<_, String>(
        "SELECT conversation_type FROM conversations WHERE id = $1"
    )
    .bind(conversation_id)
    .fetch_one(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("get conversation type: {e}")))?;

    if conv_type == "direct" {
        return Err(crate::error::AppError::Forbidden);
    }

    let role = body.role.unwrap_or_else(|| "member".to_string());

    // Add member to conversation
    sqlx::query(
        "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT (conversation_id, user_id) DO NOTHING"
    )
    .bind(conversation_id)
    .bind(body.user_id)
    .bind(&role)
    .execute(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("add member: {e}")))?;

    // Broadcast member joined event
    let payload = serde_json::json!({
        "type": "member_joined",
        "conversation_id": conversation_id,
        "user_id": body.user_id,
        "role": role,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::CREATED)
}

/// DELETE /conversations/{id}/members/{user_id}
/// Remove a member from a group conversation
pub async fn remove_member(
    State(state): State<AppState>,
    Path((conversation_id, user_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, crate::error::AppError> {
    // Check if conversation is a group
    let conv_type: String = sqlx::query_scalar::<_, String>(
        "SELECT conversation_type FROM conversations WHERE id = $1"
    )
    .bind(conversation_id)
    .fetch_one(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("get conversation type: {e}")))?;

    if conv_type == "direct" {
        return Err(crate::error::AppError::Forbidden);
    }

    // Remove member from conversation
    sqlx::query(
        "DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2"
    )
    .bind(conversation_id)
    .bind(user_id)
    .execute(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("remove member: {e}")))?;

    // Broadcast member left event
    let payload = serde_json::json!({
        "type": "member_left",
        "conversation_id": conversation_id,
        "user_id": user_id,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}

/// PATCH /conversations/{id}/members/{user_id}
/// Update a member's role in a group conversation
pub async fn update_member_role(
    State(state): State<AppState>,
    Path((conversation_id, user_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateMemberRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Check if conversation is a group
    let conv_type: String = sqlx::query_scalar::<_, String>(
        "SELECT conversation_type FROM conversations WHERE id = $1"
    )
    .bind(conversation_id)
    .fetch_one(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("get conversation type: {e}")))?;

    if conv_type == "direct" {
        return Err(crate::error::AppError::Forbidden);
    }

    // Validate role
    if body.role != "admin" && body.role != "member" {
        return Err(crate::error::AppError::BadRequest("Invalid role".into()));
    }

    // Update member role
    sqlx::query(
        "UPDATE conversation_members SET role = $1 WHERE conversation_id = $2 AND user_id = $3"
    )
    .bind(&body.role)
    .bind(conversation_id)
    .bind(user_id)
    .execute(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("update member: {e}")))?;

    // Broadcast member role changed event
    let payload = serde_json::json!({
        "type": "member_role_changed",
        "conversation_id": conversation_id,
        "user_id": user_id,
        "role": body.role,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }).to_string();

    state.registry.broadcast(conversation_id, axum::extract::ws::Message::Text(payload.clone())).await;
    let _ = pubsub::publish(&state.redis, conversation_id, &payload).await;

    Ok(StatusCode::NO_CONTENT)
}
