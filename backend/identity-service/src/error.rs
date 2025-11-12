use thiserror::Error;
use tonic::{Code, Status};

pub type Result<T> = std::result::Result<T, IdentityError>;

#[derive(Debug, Error)]
pub enum IdentityError {
    #[error("Invalid credentials")]
    InvalidCredentials,

    #[error("User not found")]
    UserNotFound,

    #[error("Email already exists")]
    EmailAlreadyExists,

    #[error("Username already exists")]
    UsernameAlreadyExists,

    #[error("Invalid email: {0}")]
    InvalidEmail(String),

    #[error("Password too weak: {0}")]
    WeakPassword(String),

    #[error("Invalid username: {0}")]
    InvalidUsername(String),

    #[error("Invalid token")]
    InvalidToken,

    #[error("Token expired")]
    TokenExpired,

    #[error("Token revoked")]
    TokenRevoked,

    #[error("Invalid OAuth state")]
    InvalidOAuthState,

    #[error("Invalid OAuth provider")]
    InvalidOAuthProvider,

    #[error("OAuth provider error: {0}")]
    OAuthError(String),

    #[error("Password reset token expired")]
    PasswordResetTokenExpired,

    #[error("Invalid password reset token")]
    InvalidPasswordResetToken,

    #[error("Session not found")]
    SessionNotFound,

    #[error("Two FA required")]
    TwoFARequired,

    #[error("Invalid two FA code")]
    InvalidTwoFACode,

    #[error("Two FA not enabled")]
    TwoFANotEnabled,

    #[error("Account locked until: {0}")]
    AccountLocked(String),

    #[error("Database error: {0}")]
    Database(String),

    #[error("Redis error: {0}")]
    Redis(String),

    #[error("JWT error: {0}")]
    JwtError(String),

    #[error("Internal server error: {0}")]
    Internal(String),

    #[error("Validation error: {0}")]
    Validation(String),
}

impl IdentityError {
    /// Convert to gRPC Status for wire protocol
    pub fn to_status(&self) -> Status {
        match self {
            IdentityError::InvalidCredentials => {
                Status::new(Code::Unauthenticated, "Invalid credentials")
            }
            IdentityError::UserNotFound => Status::new(Code::NotFound, "User not found"),
            IdentityError::EmailAlreadyExists => {
                Status::new(Code::AlreadyExists, "Email already exists")
            }
            IdentityError::UsernameAlreadyExists => {
                Status::new(Code::AlreadyExists, "Username already exists")
            }
            IdentityError::InvalidEmail(msg) => {
                Status::new(Code::InvalidArgument, format!("Invalid email: {}", msg))
            }
            IdentityError::InvalidUsername(msg) => {
                Status::new(Code::InvalidArgument, format!("Invalid username: {}", msg))
            }
            IdentityError::WeakPassword(msg) => {
                Status::new(Code::InvalidArgument, format!("Password too weak: {}", msg))
            }
            IdentityError::InvalidToken | IdentityError::TokenExpired | IdentityError::TokenRevoked => {
                Status::new(Code::Unauthenticated, "Invalid, expired, or revoked token")
            }
            IdentityError::InvalidOAuthState => {
                Status::new(Code::InvalidArgument, "Invalid OAuth state")
            }
            IdentityError::InvalidOAuthProvider => {
                Status::new(Code::InvalidArgument, "Invalid OAuth provider")
            }
            IdentityError::OAuthError(msg) => {
                Status::new(Code::Internal, format!("OAuth error: {}", msg))
            }
            IdentityError::PasswordResetTokenExpired => {
                Status::new(Code::InvalidArgument, "Password reset token expired")
            }
            IdentityError::InvalidPasswordResetToken => {
                Status::new(Code::InvalidArgument, "Invalid password reset token")
            }
            IdentityError::SessionNotFound => Status::new(Code::NotFound, "Session not found"),
            IdentityError::TwoFARequired => {
                Status::new(Code::Unauthenticated, "Two FA required")
            }
            IdentityError::InvalidTwoFACode => {
                Status::new(Code::Unauthenticated, "Invalid two FA code")
            }
            IdentityError::TwoFANotEnabled => {
                Status::new(Code::FailedPrecondition, "Two FA not enabled")
            }
            IdentityError::AccountLocked(until) => Status::new(
                Code::PermissionDenied,
                format!("Account locked until: {}", until),
            ),
            IdentityError::Validation(msg) => {
                Status::new(Code::InvalidArgument, format!("Validation error: {}", msg))
            }
            IdentityError::Database(_)
            | IdentityError::Redis(_)
            | IdentityError::JwtError(_)
            | IdentityError::Internal(_) => {
                // Don't leak internal details in production
                Status::new(Code::Internal, "Internal server error")
            }
        }
    }
}

// Conversions from external error types
impl From<sqlx::Error> for IdentityError {
    fn from(err: sqlx::Error) -> Self {
        tracing::error!("Database error: {}", err);
        IdentityError::Database(err.to_string())
    }
}

impl From<redis::RedisError> for IdentityError {
    fn from(err: redis::RedisError) -> Self {
        tracing::error!("Redis error: {}", err);
        IdentityError::Redis(err.to_string())
    }
}

impl From<jsonwebtoken::errors::Error> for IdentityError {
    fn from(err: jsonwebtoken::errors::Error) -> Self {
        tracing::error!("JWT error: {}", err);
        IdentityError::JwtError(err.to_string())
    }
}

impl From<anyhow::Error> for IdentityError {
    fn from(err: anyhow::Error) -> Self {
        let msg = err.to_string();
        // Map specific JWT errors from crypto-core
        if msg.contains("Token validation failed") {
            IdentityError::InvalidToken
        } else if msg.contains("already initialized") {
            IdentityError::JwtError(msg)
        } else if msg.contains("not initialized") {
            IdentityError::JwtError(msg)
        } else {
            IdentityError::Internal(msg)
        }
    }
}

impl From<validator::ValidationErrors> for IdentityError {
    fn from(err: validator::ValidationErrors) -> Self {
        IdentityError::Validation(err.to_string())
    }
}

// gRPC Status conversion
impl From<IdentityError> for Status {
    fn from(err: IdentityError) -> Self {
        err.to_status()
    }
}
