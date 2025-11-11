/// Authentication handlers
use actix_web::{web, HttpRequest, HttpResponse};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;
use validator::Validate;

use crate::{
    error::AuthError,
    models::user::{
        ChangePasswordRequest, LoginRequest, RefreshTokenRequest, RegisterRequest,
        RequestPasswordResetRequest,
    },
    security::{jwt, password, token_revocation},
    AppState,
};
use actix_middleware::UserId;
use chrono::{Duration, TimeZone, Utc};
use sha2::{Digest, Sha256};
use sqlx::query;
use tracing::warn;

/// Register response with tokens
#[derive(Debug, Serialize, ToSchema)]
pub struct RegisterResponse {
    pub user_id: Uuid,
    pub email: String,
    pub username: String,
    pub access_token: String,
    pub refresh_token: String,
}

/// Login response with tokens
#[derive(Debug, Serialize, ToSchema)]
pub struct LoginResponse {
    pub user_id: Uuid,
    pub email: String,
    pub username: String,
    pub access_token: String,
    pub refresh_token: String,
}

/// Refresh token response
#[derive(Debug, Serialize, ToSchema)]
pub struct RefreshTokenResponse {
    pub access_token: String,
    pub refresh_token: String,
}

/// Logout response
#[derive(Debug, Serialize, ToSchema)]
pub struct LogoutResponse {
    pub message: String,
}

/// 通用錯誤回應（與 `AuthError` 對應）
#[derive(Debug, Serialize, ToSchema)]
pub struct ErrorResponse {
    pub error: String,
    pub code: u16,
}

/// Register endpoint handler
#[utoipa::path(
    post,
    path = "/api/v1/auth/register",
    tag = "Auth",
    request_body = RegisterRequest,
    responses(
        (status = 201, description = "User registered", body = RegisterResponse),
        (status = 400, description = "Invalid input", body = ErrorResponse)
    )
)]
pub async fn register(
    state: web::Data<AppState>,
    payload: web::Json<RegisterRequest>,
) -> Result<HttpResponse, AuthError> {
    // Trim inputs and validate with validator crate
    let req = RegisterRequest {
        email: payload.email.trim().to_string(),
        username: payload.username.trim().to_string(),
        password: payload.password.clone(),
    };
    if let Err(e) = req.validate() {
        let fields = e.field_errors();
        if fields.contains_key("email") {
            return Err(AuthError::InvalidEmailFormat);
        }
        if fields.contains_key("password") {
            return Err(AuthError::WeakPassword);
        }
        return Err(AuthError::InvalidCredentials);
    }

    if crate::db::users::email_exists(&state.db, &req.email).await? {
        return Err(AuthError::EmailAlreadyExists);
    }

    if crate::db::users::username_exists(&state.db, &req.username).await? {
        return Err(AuthError::UsernameAlreadyExists);
    }

    let password_hash = password::hash_password(&req.password)?;

    let user =
        crate::db::users::create_user(&state.db, &req.email, &req.username, &password_hash).await?;

    let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

    Ok(HttpResponse::Created().json(RegisterResponse {
        user_id: user.id,
        email: user.email,
        username: user.username,
        access_token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
    }))
}

/// Login endpoint handler
#[utoipa::path(
    post,
    path = "/api/v1/auth/login",
    tag = "Auth",
    request_body = LoginRequest,
    responses(
        (status = 200, description = "User logged in", body = LoginResponse),
        (status = 401, description = "Invalid credentials", body = ErrorResponse)
    )
)]
pub async fn login(
    state: web::Data<AppState>,
    payload: web::Json<LoginRequest>,
) -> Result<HttpResponse, AuthError> {
    let req = LoginRequest {
        email: payload.email.trim().to_string(),
        password: payload.password.clone(),
    };
    if let Err(e) = req.validate() {
        if e.field_errors().contains_key("email") {
            return Err(AuthError::InvalidEmailFormat);
        }
        return Err(AuthError::InvalidCredentials);
    }

    let user = match crate::db::users::find_by_email(&state.db, &req.email).await? {
        Some(user) => user,
        None => return Err(AuthError::InvalidCredentials),
    };

    if user.is_locked() {
        return Err(AuthError::InvalidCredentials);
    }

    if let Err(_) = password::verify_password(&req.password, &user.password_hash) {
        let _ = crate::db::users::record_failed_login(&state.db, user.id, 5, 900).await;
        return Err(AuthError::InvalidCredentials);
    }

    let _ = crate::db::users::record_successful_login(&state.db, user.id).await;

    let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

    Ok(HttpResponse::Ok().json(LoginResponse {
        user_id: user.id,
        email: user.email,
        username: user.username,
        access_token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
    }))
}

/// Logout endpoint handler
#[utoipa::path(
    post,
    path = "/api/v1/auth/logout",
    tag = "Auth",
    responses(
        (status = 200, description = "User logged out", body = LogoutResponse),
        (status = 401, description = "Unauthorized", body = ErrorResponse)
    )
)]
pub async fn logout(
    state: web::Data<AppState>,
    req: HttpRequest,
    user_id: UserId,
) -> Result<HttpResponse, AuthError> {
    // user_id is extracted by JwtAuthMiddleware
    let user_id = user_id.0;

    let token = extract_bearer_token(&req)?;
    let token_data = jwt::validate_token(&token)?;

    token_revocation::revoke_token(&state.redis, &token, Some(token_data.claims.exp)).await?;
    persist_revoked_token(&state.db, user_id, &token, &token_data.claims, "logout").await?;

    if let Some(header_value) = req
        .headers()
        .get("x-refresh-token")
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
    {
        if !header_value.is_empty() {
            match jwt::validate_token(header_value) {
                Ok(refresh_data) if refresh_data.claims.token_type == "refresh" => {
                    token_revocation::revoke_token(
                        &state.redis,
                        header_value,
                        Some(refresh_data.claims.exp),
                    )
                    .await?;

                    if let Err(err) = persist_revoked_token(
                        &state.db,
                        user_id,
                        header_value,
                        &refresh_data.claims,
                        "logout",
                    )
                    .await
                    {
                        warn!(error = %err, "failed to persist refresh token revocation");
                    }
                }
                Ok(_) => {
                    warn!("Provided X-Refresh-Token was not a refresh token; skipping revocation");
                }
                Err(err) => {
                    warn!(error = %err, "Failed to validate X-Refresh-Token during logout");
                }
            }
        }
    }

    Ok(HttpResponse::Ok().json(LogoutResponse {
        message: "Logged out successfully".to_string(),
    }))
}

/// Refresh token endpoint handler
#[utoipa::path(
    post,
    path = "/api/v1/auth/refresh",
    tag = "Auth",
    request_body = RefreshTokenRequest,
    responses(
        (status = 200, description = "Token refreshed", body = RefreshTokenResponse),
        (status = 400, description = "Invalid token", body = ErrorResponse)
    )
)]
pub async fn refresh_token(
    state: web::Data<AppState>,
    payload: web::Json<RefreshTokenRequest>,
) -> Result<HttpResponse, AuthError> {
    // Validate refresh token
    let token_data = jwt::validate_token(&payload.refresh_token)?;

    // Check token type
    if token_data.claims.token_type != "refresh" {
        return Err(AuthError::InvalidToken);
    }

    if token_revocation::is_token_revoked(&state.redis, &payload.refresh_token).await? {
        return Err(AuthError::InvalidToken);
    }

    let token_hash = token_revocation::hash_token(&payload.refresh_token);
    if crate::db::token_revocation::is_token_revoked(&state.db, &token_hash).await? {
        return Err(AuthError::InvalidToken);
    }

    let user_id = Uuid::parse_str(&token_data.claims.sub).map_err(|_| AuthError::InvalidToken)?;

    if token_revocation::check_user_token_revocation(&state.redis, user_id, token_data.claims.iat)
        .await?
    {
        return Err(AuthError::InvalidToken);
    }

    if let Some(jti) = &token_data.claims.jti {
        if crate::db::token_revocation::is_jti_revoked(&state.db, jti).await? {
            return Err(AuthError::InvalidToken);
        }
    }

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
#[utoipa::path(
    post,
    path = "/api/v1/auth/change-password",
    tag = "Auth",
    request_body = ChangePasswordRequest,
    responses(
        (status = 204, description = "Password changed"),
        (status = 401, description = "Unauthorized", body = ErrorResponse)
    )
)]
pub async fn change_password(
    state: web::Data<AppState>,
    user_id: UserId,
    payload: web::Json<ChangePasswordRequest>,
) -> Result<HttpResponse, AuthError> {
    let user = crate::db::users::find_by_id(&state.db, user_id.0)
        .await?
        .ok_or(AuthError::UserNotFound)?;

    password::verify_password(&payload.old_password, &user.password_hash)?;

    let new_hash = password::hash_password(&payload.new_password)?;
    crate::db::users::update_password(&state.db, user_id.0, &new_hash).await?;

    token_revocation::revoke_all_user_tokens(&state.redis, user_id.0).await?;

    Ok(HttpResponse::NoContent().finish())
}

/// Request password reset endpoint handler
#[utoipa::path(
    post,
    path = "/api/v1/auth/password-reset/request",
    tag = "Auth",
    request_body = RequestPasswordResetRequest,
    responses(
        (status = 202, description = "Password reset requested"),
        (status = 404, description = "User not found", body = ErrorResponse)
    )
)]
pub async fn request_password_reset(
    state: web::Data<AppState>,
    payload: web::Json<RequestPasswordResetRequest>,
) -> Result<HttpResponse, AuthError> {
    let email = payload.email.trim().to_lowercase();

    if email.is_empty() {
        return Err(AuthError::InvalidEmailFormat);
    }

    if let Some(user) = crate::db::users::find_by_email(&state.db, &email).await? {
        warn!(user_id = %user.id, "Password reset requested");

        let expires_at = Utc::now() + Duration::minutes(30);
        let token_seed = Uuid::new_v4().to_string();
        let token_hash = hex::encode(Sha256::digest(token_seed.as_bytes()));

        let _ = query(
            r#"
            INSERT INTO password_resets (user_id, token_hash, expires_at, is_used, created_at)
            VALUES ($1, $2, $3, FALSE, NOW())
            ON CONFLICT (token_hash) DO NOTHING
            "#,
        )
        .bind(user.id)
        .bind(token_hash)
        .bind(expires_at)
        .execute(&state.db)
        .await;

        if let Err(err) = state
            .email_service
            .send_password_reset_email(&user.email, &token_seed)
            .await
        {
            tracing::error!(user_id = %user.id, "Failed to send password reset email: {}", err);
        }
    }

    Ok(HttpResponse::Accepted().finish())
}

async fn persist_revoked_token(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    raw_token: &str,
    claims: &jwt::Claims,
    reason: &str,
) -> Result<(), AuthError> {
    let token_hash = token_revocation::hash_token(raw_token);
    let expires_at = Utc
        .timestamp_opt(claims.exp, 0)
        .single()
        .unwrap_or_else(|| Utc::now());

    crate::db::token_revocation::revoke_token(
        pool,
        user_id,
        &token_hash,
        &claims.token_type,
        claims.jti.as_deref(),
        Some(reason),
        expires_at,
    )
    .await
}

fn extract_bearer_token(req: &HttpRequest) -> Result<String, AuthError> {
    let header = req
        .headers()
        .get(actix_web::http::header::AUTHORIZATION)
        .ok_or(AuthError::InvalidToken)?;

    let value = header.to_str().map_err(|_| AuthError::InvalidToken)?;

    if let Some(token) = value.strip_prefix("Bearer ") {
        if token.is_empty() {
            return Err(AuthError::InvalidToken);
        }
        Ok(token.to_string())
    } else {
        Err(AuthError::InvalidToken)
    }
}
