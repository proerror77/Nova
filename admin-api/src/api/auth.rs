use axum::{
    extract::State,
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use validator::Validate;

use crate::error::{AppError, Result};
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/login", post(login))
        .route("/logout", post(logout))
        .route("/refresh", post(refresh_token))
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
    State(_state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>> {
    payload.validate().map_err(|e| AppError::BadRequest(e.to_string()))?;

    // TODO: Implement actual authentication
    // 1. Query admin from database
    // 2. Verify password with argon2
    // 3. Generate JWT tokens
    // 4. Log audit event

    // Placeholder response
    Ok(Json(LoginResponse {
        access_token: "placeholder_access_token".to_string(),
        refresh_token: "placeholder_refresh_token".to_string(),
        admin: AdminInfo {
            id: "1".to_string(),
            email: payload.email,
            name: "Admin".to_string(),
            role: "super_admin".to_string(),
            avatar: None,
        },
    }))
}

async fn logout(
    State(_state): State<AppState>,
) -> Result<Json<serde_json::Value>> {
    // TODO: Implement token invalidation
    // 1. Add token to blacklist in Redis
    // 2. Log audit event

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
    State(_state): State<AppState>,
    Json(payload): Json<RefreshRequest>,
) -> Result<Json<RefreshResponse>> {
    let _token = &payload.refresh_token;

    // TODO: Implement token refresh
    // 1. Verify refresh token
    // 2. Check if not blacklisted
    // 3. Generate new access token

    Ok(Json(RefreshResponse {
        access_token: "new_placeholder_access_token".to_string(),
    }))
}
