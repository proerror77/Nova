/// JWT authentication middleware
use axum::http::request::Parts;
use uuid::Uuid;

use crate::error::AuthError;
use crate::security::jwt;

/// User ID extracted from JWT token
#[derive(Debug, Clone)]
pub struct UserId(pub Uuid);

impl UserId {
    /// Extract user ID from authorization header
    pub fn from_parts(parts: &Parts) -> Result<Self, AuthError> {
        let auth_header = parts
            .headers
            .get("Authorization")
            .and_then(|h| h.to_str().ok())
            .ok_or(AuthError::InvalidToken)?;

        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or(AuthError::InvalidToken)?;

        let token_data = jwt::validate_token(token)?;
        let user_id = Uuid::parse_str(&token_data.claims.sub)
            .map_err(|_| AuthError::InvalidToken)?;

        Ok(UserId(user_id))
    }
}
