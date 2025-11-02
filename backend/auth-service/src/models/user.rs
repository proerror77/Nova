use chrono::{DateTime, Utc};
/// User model
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    pub email: String,
    pub password_hash: String,
    pub email_verified: bool,
    pub email_verified_at: Option<DateTime<Utc>>,
    pub totp_enabled: bool,
    pub totp_secret: Option<String>,
    pub totp_verified: bool,
    pub phone_number: Option<String>,
    pub phone_verified: bool,
    pub locked_until: Option<DateTime<Utc>>,
    pub failed_login_attempts: i32,
    pub last_login_at: Option<DateTime<Utc>>,
    pub last_password_change_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
}

impl User {
    /// Check if user account is locked
    pub fn is_locked(&self) -> bool {
        if let Some(locked_until) = self.locked_until {
            locked_until > Utc::now()
        } else {
            false
        }
    }

    /// Check if user has verified email
    pub fn is_email_verified(&self) -> bool {
        self.email_verified
    }

    /// Check if user has enabled TOTP 2FA
    pub fn has_totp_enabled(&self) -> bool {
        self.totp_enabled && self.totp_verified
    }

    /// Check if user is soft-deleted
    pub fn is_deleted(&self) -> bool {
        self.deleted_at.is_some()
    }
}

#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct RefreshTokenRequest {
    pub refresh_token: String,
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub old_password: String,
    pub new_password: String,
}

#[derive(Debug, Deserialize)]
pub struct RequestPasswordResetRequest {
    pub email: String,
}

#[derive(Debug, Deserialize)]
pub struct ResetPasswordRequest {
    pub token: String,
    pub new_password: String,
}
