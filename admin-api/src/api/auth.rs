use axum::{
    extract::{ConnectInfo, State},
    http::HeaderMap,
    routing::post,
    Extension, Json, Router,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use validator::Validate;

use crate::error::{AppError, Result};
use crate::middleware::{Claims, CurrentAdmin};
use crate::models::{AuditAction, CreateAuditLog, ResourceType};
use crate::services::{AuditService, AuthService};
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/login", post(login))
        .route("/logout", post(logout))
        .route("/refresh", post(refresh_token))
        .route("/me", axum::routing::get(get_current_admin))
}

#[derive(Debug, Deserialize, Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 6))]
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct LoginResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub admin: AdminInfo,
}

#[derive(Debug, Serialize)]
pub struct AdminInfo {
    pub id: String,
    pub email: String,
    pub name: String,
    pub role: String,
    pub avatar: Option<String>,
}

async fn login(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>> {
    // Validate input
    payload.validate().map_err(|e| AppError::BadRequest(e.to_string()))?;

    // Authenticate using AuthService
    let auth_service = AuthService::new(state.db.clone(), state.config.clone());
    let (admin, access_token, refresh_token) = auth_service
        .authenticate(&payload.email, &payload.password)
        .await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let user_agent = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let _ = audit_service.log(CreateAuditLog {
        admin_id: admin.id,
        action: AuditAction::Login,
        resource_type: ResourceType::Session,
        resource_id: Some(admin.id.to_string()),
        details: Some(serde_json::json!({
            "email": admin.email,
            "login_time": chrono::Utc::now().to_rfc3339()
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent,
    }).await;

    Ok(Json(LoginResponse {
        access_token,
        refresh_token,
        admin: AdminInfo {
            id: admin.id.to_string(),
            email: admin.email,
            name: admin.name,
            role: admin.role,
            avatar: admin.avatar,
        },
    }))
}

async fn logout(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>> {
    // Get the token from Authorization header
    let token = headers
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "))
        .ok_or(AppError::Unauthorized)?;

    // Invalidate token in Redis
    let auth_service = AuthService::new(state.db.clone(), state.config.clone());
    auth_service.invalidate_token(token).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let user_agent = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let admin_id = current_admin.id.parse().unwrap_or_default();
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::Logout,
        resource_type: ResourceType::Session,
        resource_id: Some(current_admin.id.clone()),
        details: Some(serde_json::json!({
            "logout_time": chrono::Utc::now().to_rfc3339()
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent,
    }).await;

    Ok(Json(serde_json::json!({ "message": "Logged out successfully" })))
}

#[derive(Debug, Deserialize)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize)]
pub struct RefreshResponse {
    pub access_token: String,
}

async fn refresh_token(
    State(state): State<AppState>,
    Json(payload): Json<RefreshRequest>,
) -> Result<Json<RefreshResponse>> {
    // Decode and verify the refresh token
    let claims = decode::<Claims>(
        &payload.refresh_token,
        &DecodingKey::from_secret(state.config.jwt.secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|_| AppError::Unauthorized)?
    .claims;

    // Fetch admin from database to ensure still active
    let admin: crate::models::Admin = sqlx::query_as(
        "SELECT * FROM admins WHERE id = $1 AND is_active = true"
    )
    .bind(uuid::Uuid::parse_str(&claims.sub).map_err(|_| AppError::Unauthorized)?)
    .fetch_optional(&state.db.pg)
    .await?
    .ok_or(AppError::Unauthorized)?;

    // Generate new access token
    let auth_service = AuthService::new(state.db.clone(), state.config.clone());
    let access_token = auth_service.generate_access_token(&admin)?;

    Ok(Json(RefreshResponse { access_token }))
}

/// Get current authenticated admin info
async fn get_current_admin(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
) -> Result<Json<AdminInfo>> {
    // Fetch full admin details from database
    let admin: crate::models::Admin = sqlx::query_as(
        "SELECT * FROM admins WHERE id = $1"
    )
    .bind(uuid::Uuid::parse_str(&current_admin.id).map_err(|_| AppError::Unauthorized)?)
    .fetch_optional(&state.db.pg)
    .await?
    .ok_or(AppError::NotFound("Admin not found".to_string()))?;

    Ok(Json(AdminInfo {
        id: admin.id.to_string(),
        email: admin.email,
        name: admin.name,
        role: admin.role,
        avatar: admin.avatar,
    }))
}
