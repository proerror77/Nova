// Auth middleware - will be applied to protected routes when implementing real auth
#![allow(dead_code)]

use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::{Deserialize, Serialize};

use crate::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,       // Admin ID
    pub email: String,
    pub role: AdminRole,
    pub exp: usize,        // Expiration time
    pub iat: usize,        // Issued at
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum AdminRole {
    SuperAdmin,
    Admin,
    Moderator,
}

impl AdminRole {
    pub fn can_manage_admins(&self) -> bool {
        matches!(self, AdminRole::SuperAdmin)
    }

    pub fn can_ban_users(&self) -> bool {
        matches!(self, AdminRole::SuperAdmin | AdminRole::Admin)
    }

    pub fn can_moderate_content(&self) -> bool {
        true // All roles can moderate content
    }
}

#[derive(Debug, Clone)]
pub struct CurrentAdmin {
    pub id: String,
    pub email: String,
    pub role: AdminRole,
}

pub async fn require_auth(
    State(state): State<AppState>,
    mut request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let auth_header = request
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let claims = decode::<Claims>(
        token,
        &DecodingKey::from_secret(state.config.jwt.secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)?
    .claims;

    let current_admin = CurrentAdmin {
        id: claims.sub,
        email: claims.email,
        role: claims.role,
    };

    request.extensions_mut().insert(current_admin);

    Ok(next.run(request).await)
}

pub async fn require_admin_role(
    State(_state): State<AppState>,
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let current_admin = request
        .extensions()
        .get::<CurrentAdmin>()
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if !current_admin.role.can_ban_users() {
        return Err(StatusCode::FORBIDDEN);
    }

    Ok(next.run(request).await)
}

pub async fn require_super_admin(
    State(_state): State<AppState>,
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let current_admin = request
        .extensions()
        .get::<CurrentAdmin>()
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if !current_admin.role.can_manage_admins() {
        return Err(StatusCode::FORBIDDEN);
    }

    Ok(next.run(request).await)
}
