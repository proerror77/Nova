use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Token revocation model for blacklisted tokens
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct TokenRevocation {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: String,
    pub token_type: String,     // 'access' or 'refresh'
    pub jti: Option<String>,    // JWT ID for correlation
    pub reason: Option<String>, // 'logout', 'password_change', 'manual', '2fa_enabled'
    pub revoked_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>, // When token would naturally expire
    pub created_at: DateTime<Utc>,
}

impl TokenRevocation {
    /// Check if the revocation record itself has expired (token's natural expiration)
    pub fn is_expired(&self) -> bool {
        self.expires_at < Utc::now()
    }
}

/// Request to revoke a token
#[derive(Debug, Deserialize)]
pub struct RevokeTokenRequest {
    pub user_id: Uuid,
    pub token: String,
    pub token_type: String, // 'access' or 'refresh'
    pub reason: Option<String>,
}
