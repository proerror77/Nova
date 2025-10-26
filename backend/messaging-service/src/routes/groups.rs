//! Group management endpoints
//!
//! All endpoints in this file require the conversation to be a group (not direct).
//! Permission checks are performed by ConversationMember guard.

use crate::{
    middleware::guards::{ConversationAdmin, ConversationMember, User},
    models::MemberRole,
    state::AppState,
    websocket::events::{broadcast_event, WebSocketEvent},
};
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ============================================
// Request/Response DTOs
// ============================================

#[derive(Deserialize)]
pub struct AddMemberRequest {
    pub user_id: Uuid,
    #[serde(default = "default_member_role")]
    pub role: String, // "member", "moderator", "admin"
}

fn default_member_role() -> String {
    "member".to_string()
}

#[derive(Deserialize)]
pub struct UpdateMemberRequest {
    pub role: String, // "member", "moderator", "admin", "owner"
}

#[derive(Serialize)]
pub struct MemberInfo {
    pub user_id: Uuid,
    pub username: String,
    pub avatar: Option<String>,
    pub role: String,
    pub joined_at: DateTime<Utc>,
}

#[derive(Serialize)]
pub struct MembersListResponse {
    pub members: Vec<MemberInfo>,
    pub total: usize,
}

#[derive(Deserialize)]
pub struct ListMembersQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
    #[serde(default)]
    pub offset: i64,
}

fn default_limit() -> i64 {
    50
}

#[derive(Deserialize)]
pub struct UpdateGroupSettingsRequest {
    pub name: Option<String>,
    pub description: Option<String>,
    pub avatar_url: Option<String>,
}

// ============================================
// Endpoints
// ============================================

/// POST /conversations/{id}/members
/// Add a member to a group conversation
///
/// Authorization: Requires admin role
pub async fn add_member(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<AddMemberRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Verify requester is admin and conversation is group
    let admin = ConversationAdmin::verify(&state.db, user.id, conversation_id).await?;
    admin.inner.require_group()?;

    // Validate and parse role
    let role = MemberRole::from_db(&body.role)
        .ok_or_else(|| crate::error::AppError::BadRequest("Invalid role".into()))?;

    // Admins can only add members below their level
    if !admin.inner.can_manage_role(role) {
        return Err(crate::error::AppError::Forbidden);
    }

    // Check if user being added exists
    let user_exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
        .bind(body.user_id)
        .fetch_one(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("check user exists: {e}")))?;

    if !user_exists {
        return Err(crate::error::AppError::NotFound);
    }

    // Add member to conversation (ON CONFLICT DO NOTHING prevents duplicate errors)
    sqlx::query(
        "INSERT INTO conversation_members (conversation_id, user_id, role)
         VALUES ($1, $2, $3)
         ON CONFLICT (conversation_id, user_id) DO NOTHING",
    )
    .bind(conversation_id)
    .bind(body.user_id)
    .bind(role.to_db())
    .execute(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("add member: {e}")))?;

    // Fetch username for event broadcast
    let username: String = sqlx::query_scalar("SELECT username FROM users WHERE id = $1")
        .bind(body.user_id)
        .fetch_one(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch username: {e}")))?;

    // Broadcast member.joined event using unified event system
    let event = WebSocketEvent::MemberJoined {
        user_id: body.user_id,
        username,
        role: role.to_db().to_string(),
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(StatusCode::CREATED)
}

/// DELETE /conversations/{id}/members/{user_id}
/// Remove a member from a group conversation
///
/// Authorization:
/// - Requester must be admin (to remove others)
/// - OR requester is removing themselves (leaving the group)
pub async fn remove_member(
    State(state): State<AppState>,
    requesting_user: User,
    Path((conversation_id, target_user_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, crate::error::AppError> {
    let is_self_remove = requesting_user.id == target_user_id;

    if is_self_remove {
        // User leaving group - only need to verify they're a member
        let member =
            ConversationMember::verify(&state.db, requesting_user.id, conversation_id).await?;
        member.require_group()?;

        // Prevent removing last owner (business rule)
        if member.role == MemberRole::Owner {
            let owner_count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM conversation_members
                 WHERE conversation_id = $1 AND role = 'owner'",
            )
            .bind(conversation_id)
            .fetch_one(&state.db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("count owners: {e}")))?;

            if owner_count <= 1 {
                return Err(crate::error::AppError::BadRequest(
                    "Cannot remove the last owner. Transfer ownership first.".into(),
                ));
            }
        }
    } else {
        // Admin removing another member
        let admin =
            ConversationAdmin::verify(&state.db, requesting_user.id, conversation_id).await?;
        admin.inner.require_group()?;

        // Get target user's role
        let target_role: String = sqlx::query_scalar(
            "SELECT role FROM conversation_members
             WHERE conversation_id = $1 AND user_id = $2",
        )
        .bind(conversation_id)
        .bind(target_user_id)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get target role: {e}")))?
        .ok_or(crate::error::AppError::NotFound)?;

        let target_role = MemberRole::from_db(&target_role).ok_or_else(|| {
            crate::error::AppError::StartServer("Invalid role in database".into())
        })?;

        // Can only remove members below your level
        if !admin.inner.can_manage_role(target_role) {
            return Err(crate::error::AppError::Forbidden);
        }
    }

    // Remove member from conversation
    sqlx::query("DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2")
        .bind(conversation_id)
        .bind(target_user_id)
        .execute(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("remove member: {e}")))?;

    // Broadcast member.left event using unified event system
    let event = WebSocketEvent::MemberLeft {
        user_id: target_user_id,
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        requesting_user.id,
        event,
    )
    .await;

    Ok(StatusCode::NO_CONTENT)
}

/// PUT /conversations/{id}/members/{user_id}
/// Update a member's role in a group conversation
///
/// Authorization: Requires admin role
pub async fn update_member_role(
    State(state): State<AppState>,
    requesting_user: User,
    Path((conversation_id, target_user_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateMemberRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Verify requester is admin
    let admin = ConversationAdmin::verify(&state.db, requesting_user.id, conversation_id).await?;
    admin.inner.require_group()?;

    // Parse and validate new role
    let new_role = MemberRole::from_db(&body.role)
        .ok_or_else(|| crate::error::AppError::BadRequest("Invalid role".into()))?;

    // Get target user's current role
    let current_role: String = sqlx::query_scalar(
        "SELECT role FROM conversation_members
         WHERE conversation_id = $1 AND user_id = $2",
    )
    .bind(conversation_id)
    .bind(target_user_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("get current role: {e}")))?
    .ok_or(crate::error::AppError::NotFound)?;

    let current_role = MemberRole::from_db(&current_role)
        .ok_or_else(|| crate::error::AppError::StartServer("Invalid role in database".into()))?;

    // Can only manage roles below your level (both current and new role)
    if !admin.inner.can_manage_role(current_role) || !admin.inner.can_manage_role(new_role) {
        return Err(crate::error::AppError::Forbidden);
    }

    // Update member role
    sqlx::query(
        "UPDATE conversation_members SET role = $1
         WHERE conversation_id = $2 AND user_id = $3",
    )
    .bind(new_role.to_db())
    .bind(conversation_id)
    .bind(target_user_id)
    .execute(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("update member role: {e}")))?;

    // Broadcast member.role_changed event using unified event system
    let event = WebSocketEvent::MemberRoleChanged {
        user_id: target_user_id,
        old_role: current_role.to_db().to_string(),
        new_role: new_role.to_db().to_string(),
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        requesting_user.id,
        event,
    )
    .await;

    Ok(StatusCode::NO_CONTENT)
}

/// GET /conversations/{id}/members
/// List all members of a group conversation
///
/// Authorization: Requires membership in the conversation
pub async fn list_members(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Query(query): Query<ListMembersQuery>,
) -> Result<Json<MembersListResponse>, crate::error::AppError> {
    // Verify user is a member
    let member = ConversationMember::verify(&state.db, user.id, conversation_id).await?;
    member.require_group()?;

    // Fetch members with user info
    let members = sqlx::query_as::<_, (Uuid, String, Option<String>, String, DateTime<Utc>)>(
        r#"
        SELECT
            cm.user_id,
            u.username,
            u.avatar_url,
            cm.role,
            cm.joined_at
        FROM conversation_members cm
        INNER JOIN users u ON u.id = cm.user_id
        WHERE cm.conversation_id = $1
        ORDER BY
            CASE cm.role
                WHEN 'owner' THEN 0
                WHEN 'admin' THEN 1
                WHEN 'moderator' THEN 2
                ELSE 3
            END,
            cm.joined_at ASC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(conversation_id)
    .bind(query.limit)
    .bind(query.offset)
    .fetch_all(&state.db)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("fetch members: {e}")))?;

    // Get total count
    let total: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .fetch_one(&state.db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("count members: {e}")))?;

    let member_list: Vec<MemberInfo> = members
        .into_iter()
        .map(|(user_id, username, avatar, role, joined_at)| MemberInfo {
            user_id,
            username,
            avatar,
            role,
            joined_at,
        })
        .collect();

    Ok(Json(MembersListResponse {
        members: member_list,
        total: total as usize,
    }))
}

/// PUT /conversations/{id}/settings
/// Update group settings (name, description, avatar)
///
/// Authorization: Requires admin role
pub async fn update_group_settings(
    State(state): State<AppState>,
    user: User,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<UpdateGroupSettingsRequest>,
) -> Result<StatusCode, crate::error::AppError> {
    // Verify requester is admin
    let admin = ConversationAdmin::verify(&state.db, user.id, conversation_id).await?;
    admin.inner.require_group()?;

    // Validate name if provided
    if let Some(ref name) = body.name {
        if name.is_empty() || name.len() > 255 {
            return Err(crate::error::AppError::BadRequest(
                "Invalid group name".into(),
            ));
        }
    }

    // Build dynamic UPDATE query
    let mut query = String::from("UPDATE conversations SET updated_at = NOW()");
    let mut bind_count = 1;
    let mut bindings: Vec<String> = vec![];

    if let Some(name) = &body.name {
        bind_count += 1;
        query.push_str(&format!(", name = ${}", bind_count));
        bindings.push(name.clone());
    }

    if let Some(description) = &body.description {
        bind_count += 1;
        query.push_str(&format!(", description = ${}", bind_count));
        bindings.push(description.clone());
    }

    if let Some(avatar_url) = &body.avatar_url {
        bind_count += 1;
        query.push_str(&format!(", avatar_url = ${}", bind_count));
        bindings.push(avatar_url.clone());
    }

    query.push_str(" WHERE id = $1");

    // Execute update
    let mut q = sqlx::query(&query).bind(conversation_id);
    for binding in &bindings {
        q = q.bind(binding);
    }

    q.execute(&state.db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update settings: {e}")))?;

    // Determine which fields were updated
    let mut updated_fields = Vec::new();
    if body.name.is_some() {
        updated_fields.push("name".to_string());
    }
    if body.description.is_some() {
        updated_fields.push("description".to_string());
    }
    if body.avatar_url.is_some() {
        updated_fields.push("avatar_url".to_string());
    }

    // Broadcast conversation.updated event
    let event = WebSocketEvent::ConversationUpdated {
        conversation_id,
        updated_fields,
    };

    let _ = broadcast_event(
        &state.registry,
        &state.redis,
        conversation_id,
        user.id,
        event,
    )
    .await;

    Ok(StatusCode::NO_CONTENT)
}
