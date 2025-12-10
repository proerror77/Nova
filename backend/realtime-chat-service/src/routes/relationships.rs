use crate::error::AppError;
use crate::middleware::guards::User;
use crate::services::relationship_service::{RelationshipService, RelationshipServiceV2};
use crate::state::AppState;
use actix_web::{delete, get, post, put, web, HttpResponse};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ==================== Request/Response Types ====================

#[derive(Debug, Deserialize)]
pub struct BlockUserRequest {
    pub user_id: Uuid,
    pub reason: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateDmPermissionRequest {
    pub dm_permission: String,
}

#[derive(Debug, Serialize)]
pub struct BlockedUserResponse {
    pub user_id: Uuid,
    pub reason: Option<String>,
    pub blocked_at: String,
}

#[derive(Debug, Serialize)]
pub struct RelationshipResponse {
    pub is_following: bool,
    pub is_followed_by: bool,
    pub is_mutual: bool,
    pub is_blocked: bool,
    pub is_blocking: bool,
}

#[derive(Debug, Serialize)]
pub struct DmSettingsResponse {
    pub dm_permission: String,
}

#[derive(Debug, Serialize)]
pub struct MessageRequestResponse {
    pub id: Uuid,
    pub requester_id: Uuid,
    pub message_preview: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct PaginationQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ==================== Block Endpoints ====================

/// Block a user
/// POST /api/v1/blocks
#[post("/blocks")]
pub async fn block_user(
    state: web::Data<AppState>,
    user: User,
    body: web::Json<BlockUserRequest>,
) -> Result<HttpResponse, AppError> {
    // Create GraphClient and RelationshipServiceV2
    let graph_client = state
        .graph_client
        .as_ref()
        .ok_or_else(|| AppError::StartServer("graph_client not initialized".to_string()))?;
    let service = RelationshipServiceV2::new((**graph_client).clone(), state.db.clone());

    let blocked = service.block_user(user.id, body.user_id).await?;

    if blocked {
        Ok(HttpResponse::Created().json(serde_json::json!({
            "success": true,
            "message": "User blocked successfully"
        })))
    } else {
        Ok(HttpResponse::Ok().json(serde_json::json!({
            "success": true,
            "message": "User was already blocked"
        })))
    }
}

/// Unblock a user
/// DELETE /api/v1/blocks/{user_id}
#[delete("/blocks/{user_id}")]
pub async fn unblock_user(
    state: web::Data<AppState>,
    user: User,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let blocked_id = path.into_inner();

    // Create GraphClient and RelationshipServiceV2
    let graph_client = state
        .graph_client
        .as_ref()
        .ok_or_else(|| AppError::StartServer("graph_client not initialized".to_string()))?;
    let service = RelationshipServiceV2::new((**graph_client).clone(), state.db.clone());

    let unblocked = service.unblock_user(user.id, blocked_id).await?;

    if unblocked {
        Ok(HttpResponse::Ok().json(serde_json::json!({
            "success": true,
            "message": "User unblocked successfully"
        })))
    } else {
        Ok(HttpResponse::NotFound().json(serde_json::json!({
            "success": false,
            "message": "User was not blocked"
        })))
    }
}

/// Get list of blocked users
/// GET /api/v1/blocks
#[get("/blocks")]
pub async fn get_blocked_users(
    state: web::Data<AppState>,
    user: User,
    query: web::Query<PaginationQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    // Create GraphClient and RelationshipServiceV2
    let graph_client = state
        .graph_client
        .as_ref()
        .ok_or_else(|| AppError::StartServer("graph_client not initialized".to_string()))?;
    let service = RelationshipServiceV2::new((**graph_client).clone(), state.db.clone());

    let blocked_user_ids = service.get_blocked_users(user.id, limit, offset).await?;

    // Convert to response format (note: we no longer have reason and created_at from graph-service)
    let response: Vec<BlockedUserResponse> = blocked_user_ids
        .into_iter()
        .map(|blocked_id| BlockedUserResponse {
            user_id: blocked_id,
            reason: None, // graph-service doesn't store block reasons
            blocked_at: chrono::Utc::now().to_rfc3339(), // graph-service doesn't return timestamps
        })
        .collect();

    Ok(HttpResponse::Ok().json(response))
}

// ==================== Relationship Endpoints ====================

/// Get relationship status with another user
/// GET /api/v1/relationships/{user_id}
#[get("/relationships/{user_id}")]
pub async fn get_relationship(
    state: web::Data<AppState>,
    user: User,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let target_id = path.into_inner();
    let status =
        RelationshipService::get_relationship_status(&state.db, user.id, target_id).await?;

    Ok(HttpResponse::Ok().json(RelationshipResponse {
        is_following: status.is_following,
        is_followed_by: status.is_followed_by,
        is_mutual: status.is_mutual,
        is_blocked: status.is_blocked,
        is_blocking: status.is_blocking,
    }))
}

// ==================== Privacy Settings Endpoints ====================

/// Get DM privacy settings
/// GET /api/v1/settings/privacy
#[get("/settings/privacy")]
pub async fn get_privacy_settings(
    state: web::Data<AppState>,
    user: User,
) -> Result<HttpResponse, AppError> {
    let settings = RelationshipService::get_dm_settings(&state.db, user.id).await?;

    Ok(HttpResponse::Ok().json(DmSettingsResponse {
        dm_permission: settings.dm_permission,
    }))
}

/// Update DM privacy settings
/// PUT /api/v1/settings/privacy
#[put("/settings/privacy")]
pub async fn update_privacy_settings(
    state: web::Data<AppState>,
    user: User,
    body: web::Json<UpdateDmPermissionRequest>,
) -> Result<HttpResponse, AppError> {
    RelationshipService::update_dm_settings(&state.db, user.id, &body.dm_permission).await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "dm_permission": body.dm_permission
    })))
}

// ==================== Message Request Endpoints ====================

/// Get pending message requests
/// GET /api/v1/message-requests
#[get("/message-requests")]
pub async fn get_message_requests(
    state: web::Data<AppState>,
    user: User,
    query: web::Query<PaginationQuery>,
) -> Result<HttpResponse, AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let requests =
        RelationshipService::get_pending_message_requests(&state.db, user.id, limit, offset)
            .await?;

    let response: Vec<MessageRequestResponse> = requests
        .into_iter()
        .map(|r| MessageRequestResponse {
            id: r.id,
            requester_id: r.requester_id,
            message_preview: r.message_preview,
            created_at: r.created_at.to_rfc3339(),
        })
        .collect();

    Ok(HttpResponse::Ok().json(response))
}

/// Accept a message request
/// POST /api/v1/message-requests/{id}/accept
#[post("/message-requests/{id}/accept")]
pub async fn accept_message_request(
    state: web::Data<AppState>,
    user: User,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let request_id = path.into_inner();
    let request =
        RelationshipService::accept_message_request(&state.db, request_id, user.id).await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "requester_id": request.requester_id,
        "conversation_id": request.conversation_id
    })))
}

/// Reject a message request
/// POST /api/v1/message-requests/{id}/reject
#[post("/message-requests/{id}/reject")]
pub async fn reject_message_request(
    state: web::Data<AppState>,
    user: User,
    path: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let request_id = path.into_inner();
    RelationshipService::reject_message_request(&state.db, request_id, user.id).await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "message": "Message request rejected"
    })))
}

/// Configure relationship routes
pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(block_user)
        .service(unblock_user)
        .service(get_blocked_users)
        .service(get_relationship)
        .service(get_privacy_settings)
        .service(update_privacy_settings)
        .service(get_message_requests)
        .service(accept_message_request)
        .service(reject_message_request);
}
