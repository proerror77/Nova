/// Authentication handlers
use axum::{
    extract::{State, Json},
    http::StatusCode,
};
use axum::http::request::Parts;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    error::AuthError,
    middleware::jwt_auth::UserId,
    models::user::{RegisterRequest, LoginRequest, ChangePasswordRequest},
    security::{password, jwt},
    AppState,
};

/// Register response with tokens
#[derive(Debug, Serialize)]
pub struct RegisterResponse {
    pub user_id: Uuid,
    pub email: String,
    pub username: String,
    pub access_token: String,
    pub refresh_token: String,
}

/// Login response with tokens
#[derive(Debug, Serialize)]
pub struct LoginResponse {
    pub user_id: Uuid,
    pub email: String,
    pub username: String,
    pub access_token: String,
    pub refresh_token: String,
}

/// Refresh token request
#[derive(Debug, Deserialize)]
pub struct RefreshTokenRequest {
    pub refresh_token: String,
}

/// Refresh token response
#[derive(Debug, Serialize)]
pub struct RefreshTokenResponse {
    pub access_token: String,
    pub refresh_token: String,
}

/// Logout response
#[derive(Debug, Serialize)]
pub struct LogoutResponse {
    pub message: String,
}

/// Register endpoint handler
pub async fn register(
    State(_state): State<AppState>,
    Json(payload): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<RegisterResponse>), AuthError> {
    // Validate input
    if payload.email.is_empty() || payload.username.is_empty() || payload.password.is_empty() {
        return Err(AuthError::InvalidCredentials);
    }

    // Hash password
    let _password_hash = password::hash_password(&payload.password)?;

    // Create user (will need database implementation)
    // For now, return a stub response
    let user_id = Uuid::new_v4();

    // Generate token pair
    let token_pair = jwt::generate_token_pair(
        user_id,
        &payload.email,
        &payload.username,
    )?;

    Ok((
        StatusCode::CREATED,
        Json(RegisterResponse {
            user_id,
            email: payload.email,
            username: payload.username,
            access_token: token_pair.access_token,
            refresh_token: token_pair.refresh_token,
        }),
    ))
}

/// Login endpoint handler
pub async fn login(
    State(_state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, AuthError> {
    // Validate input
    if payload.email.is_empty() || payload.password.is_empty() {
        return Err(AuthError::InvalidCredentials);
    }

    // Find user by email (will need database implementation)
    // For now, return an error
    Err(AuthError::UserNotFound)
}

/// Logout endpoint handler
pub async fn logout(
    State(_state): State<AppState>,
    parts: Parts,
) -> Result<Json<LogoutResponse>, AuthError> {
    // Extract user ID from JWT
    let UserId(_user_id) = UserId::from_parts(&parts)?;

    // Revoke token (optional - can be stateless)
    // In a stateless JWT system, logout is handled client-side by discarding the token
    // But we can add to blacklist for extra security

    Ok(Json(LogoutResponse {
        message: "Logged out successfully".to_string(),
    }))
}

/// Refresh token endpoint handler
pub async fn refresh_token(
    State(_state): State<AppState>,
    Json(payload): Json<RefreshTokenRequest>,
) -> Result<Json<RefreshTokenResponse>, AuthError> {
    // Validate refresh token
    let token_data = jwt::validate_token(&payload.refresh_token)?;

    // Check token type
    if token_data.claims.token_type != "refresh" {
        return Err(AuthError::InvalidToken);
    }

    // Generate new token pair
    let user_id = Uuid::parse_str(&token_data.claims.sub)
        .map_err(|_| AuthError::InvalidToken)?;

    let new_pair = jwt::generate_token_pair(
        user_id,
        &token_data.claims.email,
        &token_data.claims.username,
    )?;

    Ok(Json(RefreshTokenResponse {
        access_token: new_pair.access_token,
        refresh_token: new_pair.refresh_token,
    }))
}

/// Change password endpoint handler
pub async fn change_password(
    State(_state): State<AppState>,
    parts: Parts,
    Json(_payload): Json<ChangePasswordRequest>,
) -> Result<StatusCode, AuthError> {
    // Extract user ID from JWT
    let UserId(_user_id) = UserId::from_parts(&parts)?;

    // Verify old password (will need database implementation)
    // Update password (will need database implementation)
    // Revoke all existing tokens for security

    Ok(StatusCode::NO_CONTENT)
}

/// Request password reset endpoint handler
pub async fn request_password_reset(
    State(_state): State<AppState>,
    Json(_payload): Json<RequestPasswordResetRequest>,
) -> Result<StatusCode, AuthError> {
    // Find user by email
    // Generate password reset token
    // Send email with reset link
    // Return 202 Accepted

    Ok(StatusCode::ACCEPTED)
}

/// Request password reset payload
#[derive(Debug, Deserialize)]
pub struct RequestPasswordResetRequest {
    pub email: String,
}
