use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;
use validator::Validate;

/// User model - core identity entity
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
    // Profile fields
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: bool,
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

/// User registration request (gRPC/HTTP)
#[derive(Debug, Serialize, Deserialize, Validate)]
pub struct RegisterRequest {
    #[validate(email)]
    pub email: String,
    #[validate(
        length(min = 3, max = 32),
        custom(function = "crate::validators::validate_username_shape_validator")
    )]
    pub username: String,
    #[validate(length(min = 8, max = 128))]
    pub password: String,
}

/// User login request (gRPC/HTTP)
#[derive(Debug, Serialize, Deserialize, Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 1, max = 256))]
    pub password: String,
}

/// Token refresh request
#[derive(Debug, Deserialize)]
pub struct RefreshTokenRequest {
    pub refresh_token: String,
}

/// Password change request
#[derive(Debug, Deserialize)]
pub struct ChangePasswordRequest {
    pub old_password: String,
    pub new_password: String,
}

/// Password reset initiation request
#[derive(Debug, Deserialize)]
pub struct RequestPasswordResetRequest {
    pub email: String,
}

/// Password reset completion request
#[derive(Debug, Deserialize)]
pub struct ResetPasswordRequest {
    pub token: String,
    pub new_password: String,
}
