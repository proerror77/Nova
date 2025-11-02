/// Authentication handlers
use actix_web::{web, HttpResponse};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    error::AuthError,
    models::user::{ChangePasswordRequest, LoginRequest, RegisterRequest},
    security::{jwt, password},
    AppState,
};
use actix_middleware::UserId;

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
    _state: web::Data<AppState>,
    payload: web::Json<RegisterRequest>,
) -> Result<HttpResponse, AuthError> {
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
    let token_pair = jwt::generate_token_pair(user_id, &payload.email, &payload.username)?;

    Ok(HttpResponse::Created().json(RegisterResponse {
        user_id,
        email: payload.email.clone(),
        username: payload.username.clone(),
        access_token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
    }))
}

/// Login endpoint handler
pub async fn login(
    _state: web::Data<AppState>,
    payload: web::Json<LoginRequest>,
) -> Result<HttpResponse, AuthError> {
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
    _state: web::Data<AppState>,
    user_id: UserId,
) -> Result<HttpResponse, AuthError> {
    // user_id is extracted by JwtAuthMiddleware
    let _user_id = user_id.0;

    // Revoke token (optional - can be stateless)
    // In a stateless JWT system, logout is handled client-side by discarding the token
    // But we can add to blacklist for extra security

    Ok(HttpResponse::Ok().json(LogoutResponse {
        message: "Logged out successfully".to_string(),
    }))
}

/// Refresh token endpoint handler
pub async fn refresh_token(
    _state: web::Data<AppState>,
    payload: web::Json<RefreshTokenRequest>,
) -> Result<HttpResponse, AuthError> {
    // Validate refresh token
    let token_data = jwt::validate_token(&payload.refresh_token)?;

    // Check token type
    if token_data.claims.token_type != "refresh" {
        return Err(AuthError::InvalidToken);
    }

    // Generate new token pair
    let user_id = Uuid::parse_str(&token_data.claims.sub).map_err(|_| AuthError::InvalidToken)?;

    let new_pair = jwt::generate_token_pair(
        user_id,
        &token_data.claims.email,
        &token_data.claims.username,
    )?;

    Ok(HttpResponse::Ok().json(RefreshTokenResponse {
        access_token: new_pair.access_token,
        refresh_token: new_pair.refresh_token,
    }))
}

/// Change password endpoint handler
pub async fn change_password(
    _state: web::Data<AppState>,
    user_id: UserId,
    _payload: web::Json<ChangePasswordRequest>,
) -> Result<HttpResponse, AuthError> {
    // user_id is extracted by JwtAuthMiddleware
    let _user_id = user_id.0;

    // Verify old password (will need database implementation)
    // Update password (will need database implementation)
    // Revoke all existing tokens for security

    Ok(HttpResponse::NoContent().finish())
}

/// Request password reset endpoint handler
pub async fn request_password_reset(
    _state: web::Data<AppState>,
    _payload: web::Json<RequestPasswordResetRequest>,
) -> Result<HttpResponse, AuthError> {
    // Find user by email
    // Generate password reset token
    // Send email with reset link
    // Return 202 Accepted

    Ok(HttpResponse::Accepted().finish())
}

/// Request password reset payload
#[derive(Debug, Deserialize)]
pub struct RequestPasswordResetRequest {
    pub email: String,
}
