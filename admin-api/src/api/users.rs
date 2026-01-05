use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_users))
        .route("/:id", get(get_user))
        .route("/:id/ban", post(ban_user))
        .route("/:id/unban", post(unban_user))
        .route("/:id/warn", post(warn_user))
}

#[derive(Debug, Deserialize)]
pub struct ListUsersQuery {
    pub page: Option<u32>,
    pub limit: Option<u32>,
    pub status: Option<String>,
    pub search: Option<String>,
    pub risk_level: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UserListResponse {
    pub users: Vec<UserSummary>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct UserSummary {
    pub id: String,
    pub nickname: String,
    pub email: String,
    pub avatar: Option<String>,
    pub status: String,
    pub risk_level: String,
    pub created_at: String,
    pub last_active_at: Option<String>,
}

async fn list_users(
    State(_state): State<AppState>,
    Query(query): Query<ListUsersQuery>,
) -> Result<Json<UserListResponse>> {
    let page = query.page.unwrap_or(1);
    let limit = query.limit.unwrap_or(20).min(100);
    let _status = query.status;
    let _search = query.search;
    let _risk_level = query.risk_level;

    // TODO: Query real users from database with filters

    Ok(Json(UserListResponse {
        users: vec![
            UserSummary {
                id: Uuid::new_v4().to_string(),
                nickname: "测试用户".to_string(),
                email: "user@example.com".to_string(),
                avatar: None,
                status: "active".to_string(),
                risk_level: "low".to_string(),
                created_at: "2024-01-01T00:00:00Z".to_string(),
                last_active_at: Some("2024-01-15T10:30:00Z".to_string()),
            },
        ],
        total: 1,
        page,
        limit,
    }))
}

#[derive(Debug, Serialize)]
pub struct UserDetail {
    pub id: String,
    pub nickname: String,
    pub email: String,
    pub phone: Option<String>,
    pub avatar: Option<String>,
    pub bio: Option<String>,
    pub status: String,
    pub risk_level: String,
    pub risk_score: f64,
    pub verification: VerificationStatus,
    pub stats: UserStats,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize)]
pub struct VerificationStatus {
    pub identity_verified: bool,
    pub profession_verified: bool,
}

#[derive(Debug, Serialize)]
pub struct UserStats {
    pub posts_count: i64,
    pub comments_count: i64,
    pub followers_count: i64,
    pub following_count: i64,
    pub reports_received: i64,
    pub warnings_count: i64,
}

async fn get_user(
    State(_state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<UserDetail>> {
    // TODO: Query real user from database

    Ok(Json(UserDetail {
        id,
        nickname: "测试用户".to_string(),
        email: "user@example.com".to_string(),
        phone: Some("+86 138****8888".to_string()),
        avatar: None,
        bio: Some("这是一段个人简介".to_string()),
        status: "active".to_string(),
        risk_level: "low".to_string(),
        risk_score: 15.5,
        verification: VerificationStatus {
            identity_verified: true,
            profession_verified: false,
        },
        stats: UserStats {
            posts_count: 42,
            comments_count: 156,
            followers_count: 1200,
            following_count: 350,
            reports_received: 2,
            warnings_count: 0,
        },
        created_at: "2024-01-01T00:00:00Z".to_string(),
        updated_at: "2024-01-15T10:30:00Z".to_string(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct BanRequest {
    pub reason: String,
    pub duration_days: Option<i32>,
}

async fn ban_user(
    State(_state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<BanRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.is_empty() {
        return Err(AppError::BadRequest("Reason is required".to_string()));
    }

    // TODO: Implement user ban
    // 1. Update user status in database
    // 2. Invalidate user sessions
    // 3. Log audit event

    Ok(Json(serde_json::json!({
        "message": format!("User {} has been banned", id),
        "reason": payload.reason,
        "duration_days": payload.duration_days,
    })))
}

async fn unban_user(
    State(_state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>> {
    // TODO: Implement user unban

    Ok(Json(serde_json::json!({
        "message": format!("User {} has been unbanned", id),
    })))
}

#[derive(Debug, Deserialize)]
pub struct WarnRequest {
    pub reason: String,
}

async fn warn_user(
    State(_state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<WarnRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.is_empty() {
        return Err(AppError::BadRequest("Reason is required".to_string()));
    }

    // TODO: Implement user warning
    // 1. Create warning record
    // 2. Send notification to user
    // 3. Log audit event

    Ok(Json(serde_json::json!({
        "message": format!("Warning sent to user {}", id),
        "reason": payload.reason,
    })))
}
