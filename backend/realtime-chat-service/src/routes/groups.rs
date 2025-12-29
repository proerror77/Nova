//! Group management endpoints
//!
//! All endpoints in this file require the conversation to be a group (not direct).
//! Permission checks are performed by ConversationMember guard.

use crate::{
    error::AppError,
    middleware::guards::{ConversationAdmin, ConversationMember, User},
    models::MemberRole,
    state::AppState,
    websocket::events::{broadcast_event, WebSocketEvent},
};
use actix_web::{delete, post, put, web, HttpResponse};
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
#[post("/conversations/{id}/members")]
pub async fn add_member(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    body: web::Json<AddMemberRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
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

    // Phase 1: Spec 007 - Check user via auth-service gRPC instead of shadow users table
    let user_exists = state
        .auth_client
        .user_exists(body.user_id)
        .await
        .map_err(|e| {
            tracing::error!(user_id = %body.user_id, error = %e, "auth-service check_user_exists failed");
            crate::error::AppError::StartServer(format!("check user exists: {e}"))
        })?;

    if !user_exists {
        return Err(crate::error::AppError::NotFound);
    }

    // Add member to conversation (ON CONFLICT DO NOTHING prevents duplicate errors)
    state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .execute(
            "INSERT INTO conversation_members (conversation_id, user_id, role)
             VALUES ($1, $2, $3)
             ON CONFLICT (conversation_id, user_id) DO NOTHING",
            &[&conversation_id, &body.user_id, &role.to_db()],
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("add member: {e}")))?;

    // Phase 1: Spec 007 - Fetch username via auth-service gRPC instead of shadow users table
    let username = state
        .auth_client
        .get_user(body.user_id)
        .await
        .map_err(|e| {
            tracing::error!(user_id = %body.user_id, error = %e, "auth-service get_user failed");
            crate::error::AppError::StartServer(format!("fetch username: {e}"))
        })?
        .ok_or(crate::error::AppError::NotFound)?;

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

    Ok(HttpResponse::Created().finish())
}

/// DELETE /conversations/{id}/members/{user_id}
/// Remove a member from a group conversation
///
/// Authorization:
/// - Requester must be admin (to remove others)
/// - OR requester is removing themselves (leaving the group)
#[delete("/conversations/{id}/members/{user_id}")]
pub async fn remove_member(
    state: web::Data<AppState>,
    requesting_user: User,
    path: web::Path<(Uuid, Uuid)>,
) -> Result<HttpResponse, AppError> {
    let (conversation_id, target_user_id) = path.into_inner();
    let is_self_remove = requesting_user.id == target_user_id;

    if is_self_remove {
        // User leaving group - only need to verify they're a member
        let member =
            ConversationMember::verify(&state.db, requesting_user.id, conversation_id).await?;
        member.require_group()?;

        // Prevent removing last owner (business rule)
        if member.role == MemberRole::Owner {
            let owner_count: i64 = state
                .db
                .get()
                .await
                .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
                .query_one(
                    "SELECT COUNT(*) FROM conversation_members
                     WHERE conversation_id = $1 AND role = 'owner'",
                    &[&conversation_id],
                )
                .await
                .map_err(|e| crate::error::AppError::StartServer(format!("count owners: {e}")))?
                .get(0);

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
        let target_role: Option<String> = state
            .db
            .get()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
            .query_opt(
                "SELECT role FROM conversation_members
                 WHERE conversation_id = $1 AND user_id = $2",
                &[&conversation_id, &target_user_id],
            )
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get target role: {e}")))?
            .map(|row| row.get(0));

        let target_role = target_role.ok_or(crate::error::AppError::NotFound)?;

        let target_role = MemberRole::from_db(&target_role).ok_or_else(|| {
            crate::error::AppError::StartServer("Invalid role in database".into())
        })?;

        // Can only remove members below your level
        if !admin.inner.can_manage_role(target_role) {
            return Err(crate::error::AppError::Forbidden);
        }
    }

    // Remove member from conversation
    state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .execute(
            "DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
            &[&conversation_id, &target_user_id],
        )
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

    Ok(HttpResponse::NoContent().finish())
}

/// PUT /conversations/{id}/members/{user_id}
/// Update a member's role in a group conversation
///
/// Authorization: Requires admin role
#[put("/conversations/{id}/members/{user_id}/role")]
pub async fn update_member_role(
    state: web::Data<AppState>,
    requesting_user: User,
    path: web::Path<(Uuid, Uuid)>,
    body: web::Json<UpdateMemberRequest>,
) -> Result<HttpResponse, AppError> {
    let (conversation_id, target_user_id) = path.into_inner();
    // Verify requester is admin
    let admin = ConversationAdmin::verify(&state.db, requesting_user.id, conversation_id).await?;
    admin.inner.require_group()?;

    // Parse and validate new role
    let new_role = MemberRole::from_db(&body.role)
        .ok_or_else(|| crate::error::AppError::BadRequest("Invalid role".into()))?;

    // Get target user's current role
    let current_role: Option<String> = state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .query_opt(
            "SELECT role FROM conversation_members
             WHERE conversation_id = $1 AND user_id = $2",
            &[&conversation_id, &target_user_id],
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get current role: {e}")))?
        .map(|row| row.get(0));

    let current_role = current_role.ok_or(crate::error::AppError::NotFound)?;

    let current_role = MemberRole::from_db(&current_role)
        .ok_or_else(|| crate::error::AppError::StartServer("Invalid role in database".into()))?;

    // Can only manage roles below your level (both current and new role)
    if !admin.inner.can_manage_role(current_role) || !admin.inner.can_manage_role(new_role) {
        return Err(crate::error::AppError::Forbidden);
    }

    // Update member role
    state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .execute(
            "UPDATE conversation_members SET role = $1
             WHERE conversation_id = $2 AND user_id = $3",
            &[&new_role.to_db(), &conversation_id, &target_user_id],
        )
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

    Ok(HttpResponse::NoContent().finish())
}

/// GET /conversations/{id}/members
/// List all members of a group conversation
///
/// Authorization: Requires membership in the conversation
pub async fn list_members(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    query: web::Query<ListMembersQuery>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
    // Verify user is a member
    let member = ConversationMember::verify(&state.db, user.id, conversation_id).await?;
    member.require_group()?;

    // Fetch members with user info
    let rows = state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .query(
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
            &[&conversation_id, &query.limit, &query.offset],
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch members: {e}")))?;

    let members: Vec<(Uuid, String, Option<String>, String, DateTime<Utc>)> = rows
        .iter()
        .map(|row| (row.get(0), row.get(1), row.get(2), row.get(3), row.get(4)))
        .collect();

    // Get total count
    let total: i64 = state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .query_one(
            "SELECT COUNT(*) FROM conversation_members WHERE conversation_id = $1",
            &[&conversation_id],
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("count members: {e}")))?
        .get(0);

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

    Ok(HttpResponse::Ok().json(MembersListResponse {
        members: member_list,
        total: total as usize,
    }))
}

/// PUT /conversations/{id}/settings
/// Update group settings (name, description, avatar)
///
/// Authorization: Requires admin role
pub async fn update_group_settings(
    state: web::Data<AppState>,
    user: User,
    conversation_id: web::Path<Uuid>,
    body: web::Json<UpdateGroupSettingsRequest>,
) -> Result<HttpResponse, AppError> {
    let conversation_id = conversation_id.into_inner();
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
    let mut bindings: Vec<&(dyn tokio_postgres::types::ToSql + Sync)> = vec![&conversation_id];

    if body.name.is_some() {
        bind_count += 1;
        query.push_str(&format!(", name = ${}", bind_count));
    }

    if body.description.is_some() {
        bind_count += 1;
        query.push_str(&format!(", description = ${}", bind_count));
    }

    if body.avatar_url.is_some() {
        bind_count += 1;
        query.push_str(&format!(", avatar_url = ${}", bind_count));
    }

    query.push_str(" WHERE id = $1 AND deleted_at IS NULL");

    // Build the bindings vector in the correct order
    if let Some(ref name) = body.name {
        bindings.push(name);
    }
    if let Some(ref description) = body.description {
        bindings.push(description);
    }
    if let Some(ref avatar_url) = body.avatar_url {
        bindings.push(avatar_url);
    }

    // Execute update
    state
        .db
        .get()
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get connection: {e}")))?
        .execute(&query, &bindings[..])
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

    Ok(HttpResponse::NoContent().finish())
}

// TODO: Implement create_group - create a new group conversation
#[post("/groups")]
pub async fn create_group(
    _state: web::Data<AppState>,
    _user: User,
    _body: web::Json<serde_json::Value>,
) -> Result<HttpResponse, AppError> {
    // TODO: Implement group creation
    // For now, redirect to create_group_conversation
    Ok(HttpResponse::Created().json(serde_json::json!({
        "message": "Use create_group_conversation endpoint"
    })))
}
