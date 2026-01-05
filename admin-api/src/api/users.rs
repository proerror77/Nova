use axum::{
    extract::{ConnectInfo, Path, Query, State},
    http::HeaderMap,
    routing::{get, post},
    Extension, Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::CurrentAdmin;
use crate::models::{AuditAction, CreateAuditLog, ResourceType};
use crate::services::{AuditService, ListUsersParams, UserService};
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_users))
        .route("/:id", get(get_user))
        .route("/:id/ban", post(ban_user))
        .route("/:id/unban", post(unban_user))
        .route("/:id/warn", post(warn_user))
        .route("/:id/history", get(get_user_history))
}

#[derive(Debug, Deserialize)]
pub struct ListUsersQuery {
    pub page: Option<u32>,
    pub limit: Option<u32>,
    pub status: Option<String>,
    pub search: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UserListResponse {
    pub users: Vec<UserSummaryResponse>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct UserSummaryResponse {
    pub id: String,
    pub nickname: String,
    pub email: String,
    pub avatar: Option<String>,
    pub status: String,
    pub created_at: String,
    pub last_active_at: Option<String>,
}

async fn list_users(
    State(state): State<AppState>,
    Query(query): Query<ListUsersQuery>,
) -> Result<Json<UserListResponse>> {
    let page = query.page.unwrap_or(1).max(1);
    let limit = query.limit.unwrap_or(20).min(100);

    let user_service = UserService::new(state.db.clone());
    let (users, total) = user_service.list_users(ListUsersParams {
        page,
        limit,
        status: query.status,
        search: query.search,
    }).await?;

    let users_response: Vec<UserSummaryResponse> = users.into_iter().map(|u| UserSummaryResponse {
        id: u.id.to_string(),
        nickname: u.nickname,
        email: u.email,
        avatar: u.avatar,
        status: u.status,
        created_at: u.created_at.to_rfc3339(),
        last_active_at: u.last_active_at.map(|t| t.to_rfc3339()),
    }).collect();

    Ok(Json(UserListResponse {
        users: users_response,
        total,
        page,
        limit,
    }))
}

#[derive(Debug, Serialize)]
pub struct UserDetailResponse {
    pub id: String,
    pub nickname: String,
    pub email: String,
    pub phone: Option<String>,
    pub avatar: Option<String>,
    pub bio: Option<String>,
    pub status: String,
    pub is_banned: bool,
    pub warnings_count: i64,
    pub created_at: String,
    pub updated_at: String,
}

async fn get_user(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<Json<UserDetailResponse>> {
    let user_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;

    let user_service = UserService::new(state.db.clone());
    let user = user_service.get_user(user_id).await?;
    let is_banned = user_service.is_user_banned(user_id).await?;
    let warnings_count = user_service.get_warning_count(user_id).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let admin_id = current_admin.id.parse().unwrap_or_default();
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::ViewUser,
        resource_type: ResourceType::User,
        resource_id: Some(id.clone()),
        details: None,
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(UserDetailResponse {
        id: user.id.to_string(),
        nickname: user.nickname,
        email: user.email,
        phone: user.phone,
        avatar: user.avatar,
        bio: user.bio,
        status: user.status,
        is_banned,
        warnings_count,
        created_at: user.created_at.to_rfc3339(),
        updated_at: user.updated_at.to_rfc3339(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct BanRequest {
    pub reason: String,
    #[serde(default)]
    pub duration_days: Option<i32>,
}

async fn ban_user(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<BanRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.trim().is_empty() {
        return Err(AppError::BadRequest("Reason is required".to_string()));
    }

    let user_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    // Check permission
    if !current_admin.role.can_ban_users() {
        return Err(AppError::Forbidden);
    }

    let user_service = UserService::new(state.db.clone());
    let ban = user_service.ban_user(user_id, admin_id, &payload.reason, payload.duration_days).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::BanUser,
        resource_type: ResourceType::User,
        resource_id: Some(id.clone()),
        details: Some(serde_json::json!({
            "reason": payload.reason,
            "duration_days": payload.duration_days,
            "ban_id": ban.id.to_string(),
            "expires_at": ban.expires_at.map(|t| t.to_rfc3339())
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("User {} has been banned", id),
        "ban_id": ban.id.to_string(),
        "expires_at": ban.expires_at.map(|t| t.to_rfc3339()),
    })))
}

async fn unban_user(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>> {
    let user_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    // Check permission
    if !current_admin.role.can_ban_users() {
        return Err(AppError::Forbidden);
    }

    let user_service = UserService::new(state.db.clone());
    user_service.unban_user(user_id, admin_id).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::UnbanUser,
        resource_type: ResourceType::User,
        resource_id: Some(id.clone()),
        details: None,
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("User {} has been unbanned", id),
    })))
}

#[derive(Debug, Deserialize)]
pub struct WarnRequest {
    pub reason: String,
    #[serde(default = "default_severity")]
    pub severity: String,
}

fn default_severity() -> String {
    "low".to_string()
}

async fn warn_user(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<WarnRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.trim().is_empty() {
        return Err(AppError::BadRequest("Reason is required".to_string()));
    }

    let user_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    let user_service = UserService::new(state.db.clone());
    let warning = user_service.warn_user(user_id, admin_id, &payload.reason, &payload.severity).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::WarnUser,
        resource_type: ResourceType::User,
        resource_id: Some(id.clone()),
        details: Some(serde_json::json!({
            "reason": payload.reason,
            "severity": payload.severity,
            "warning_id": warning.id.to_string()
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Warning sent to user {}", id),
        "warning_id": warning.id.to_string(),
    })))
}

#[derive(Debug, Serialize)]
pub struct UserHistoryResponse {
    pub bans: Vec<BanHistoryItem>,
    pub warnings: Vec<WarningHistoryItem>,
}

#[derive(Debug, Serialize)]
pub struct BanHistoryItem {
    pub id: String,
    pub reason: String,
    pub duration_days: Option<i32>,
    pub banned_at: String,
    pub expires_at: Option<String>,
    pub is_active: bool,
}

#[derive(Debug, Serialize)]
pub struct WarningHistoryItem {
    pub id: String,
    pub reason: String,
    pub severity: String,
    pub created_at: String,
}

async fn get_user_history(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<UserHistoryResponse>> {
    let user_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid user ID".to_string()))?;

    let user_service = UserService::new(state.db.clone());
    let bans = user_service.get_user_bans(user_id).await?;
    let warnings = user_service.get_user_warnings(user_id).await?;

    Ok(Json(UserHistoryResponse {
        bans: bans.into_iter().map(|b| BanHistoryItem {
            id: b.id.to_string(),
            reason: b.reason,
            duration_days: b.duration_days,
            banned_at: b.banned_at.to_rfc3339(),
            expires_at: b.expires_at.map(|t| t.to_rfc3339()),
            is_active: b.is_active,
        }).collect(),
        warnings: warnings.into_iter().map(|w| WarningHistoryItem {
            id: w.id.to_string(),
            reason: w.reason,
            severity: w.severity,
            created_at: w.created_at.to_rfc3339(),
        }).collect(),
    }))
}
