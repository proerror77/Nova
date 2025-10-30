use thiserror::Error;
use tonic::{Code, Status};
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

pub type AuthResult<T> = Result<T, AuthError>;

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("Invalid credentials")]
    InvalidCredentials,

    #[error("User not found")]
    UserNotFound,

    #[error("Email already exists")]
    EmailAlreadyExists,

    #[error("Username already exists")]
    UsernameAlreadyExists,

    #[error("Invalid email format")]
    InvalidEmailFormat,

    #[error("Password too weak")]
    WeakPassword,

    #[error("Invalid token")]
    InvalidToken,

    #[error("Token expired")]
    TokenExpired,

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

    #[error("Database error: {0}")]
    Database(String),

    #[error("Redis error: {0}")]
    Redis(String),

    #[error("JWT error: {0}")]
    JwtError(String),

    #[error("Internal server error: {0}")]
    Internal(String),
}

impl AuthError {
    pub fn to_status(&self) -> Status {
        match self {
            AuthError::InvalidCredentials => {
                Status::new(Code::Unauthenticated, "Invalid credentials")
            }
            AuthError::UserNotFound => Status::new(Code::NotFound, "User not found"),
            AuthError::EmailAlreadyExists => {
                Status::new(Code::AlreadyExists, "Email already exists")
            }
            AuthError::UsernameAlreadyExists => {
                Status::new(Code::AlreadyExists, "Username already exists")
            }
            AuthError::InvalidEmailFormat => {
                Status::new(Code::InvalidArgument, "Invalid email format")
            }
            AuthError::WeakPassword => Status::new(Code::InvalidArgument, "Password too weak"),
            AuthError::InvalidToken | AuthError::TokenExpired => {
                Status::new(Code::Unauthenticated, "Invalid or expired token")
            }
            AuthError::InvalidOAuthState => {
                Status::new(Code::InvalidArgument, "Invalid OAuth state")
            }
            AuthError::InvalidOAuthProvider => {
                Status::new(Code::InvalidArgument, "Invalid OAuth provider")
            }
            AuthError::OAuthError(msg) => Status::new(Code::Internal, format!("OAuth error: {}", msg)),
            AuthError::PasswordResetTokenExpired => {
                Status::new(Code::InvalidArgument, "Password reset token expired")
            }
            AuthError::InvalidPasswordResetToken => {
                Status::new(Code::InvalidArgument, "Invalid password reset token")
            }
            AuthError::SessionNotFound => Status::new(Code::NotFound, "Session not found"),
            AuthError::TwoFARequired => Status::new(Code::Unauthenticated, "Two FA required"),
            AuthError::InvalidTwoFACode => {
                Status::new(Code::Unauthenticated, "Invalid two FA code")
            }
            AuthError::TwoFANotEnabled => {
                Status::new(Code::FailedPrecondition, "Two FA not enabled")
            }
            AuthError::Database(_) | AuthError::Redis(_) | AuthError::JwtError(_) | AuthError::Internal(_) => {
                Status::new(Code::Internal, "Internal server error")
            }
        }
    }
}

impl From<sqlx::Error> for AuthError {
    fn from(err: sqlx::Error) -> Self {
        tracing::error!("Database error: {}", err);
        AuthError::Database(err.to_string())
    }
}

impl From<redis::RedisError> for AuthError {
    fn from(err: redis::RedisError) -> Self {
        tracing::error!("Redis error: {}", err);
        AuthError::Redis(err.to_string())
    }
}

impl From<jsonwebtoken::errors::Error> for AuthError {
    fn from(err: jsonwebtoken::errors::Error) -> Self {
        tracing::error!("JWT error: {}", err);
        AuthError::JwtError(err.to_string())
    }
}

impl From<anyhow::Error> for AuthError {
    fn from(err: anyhow::Error) -> Self {
        let msg = err.to_string();
        // Map specific JWT errors from crypto-core
        if msg.contains("Token validation failed") {
            AuthError::InvalidToken
        } else if msg.contains("already initialized") {
            AuthError::JwtError(msg)
        } else if msg.contains("not initialized") {
            AuthError::JwtError(msg)
        } else {
            AuthError::Internal(msg)
        }
    }
}

impl From<AuthError> for Status {
    fn from(err: AuthError) -> Self {
        err.to_status()
    }
}

impl IntoResponse for AuthError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            AuthError::InvalidCredentials => (
                StatusCode::UNAUTHORIZED,
                "Invalid credentials".to_string(),
            ),
            AuthError::UserNotFound => (
                StatusCode::NOT_FOUND,
                "User not found".to_string(),
            ),
            AuthError::EmailAlreadyExists => (
                StatusCode::CONFLICT,
                "Email already exists".to_string(),
            ),
            AuthError::UsernameAlreadyExists => (
                StatusCode::CONFLICT,
                "Username already exists".to_string(),
            ),
            AuthError::InvalidEmailFormat => (
                StatusCode::BAD_REQUEST,
                "Invalid email format".to_string(),
            ),
            AuthError::WeakPassword => (
                StatusCode::BAD_REQUEST,
                "Password too weak".to_string(),
            ),
            AuthError::InvalidToken | AuthError::TokenExpired => (
                StatusCode::UNAUTHORIZED,
                "Invalid or expired token".to_string(),
            ),
            AuthError::InvalidOAuthState => (
                StatusCode::BAD_REQUEST,
                "Invalid OAuth state".to_string(),
            ),
            AuthError::InvalidOAuthProvider => (
                StatusCode::BAD_REQUEST,
                "Invalid OAuth provider".to_string(),
            ),
            AuthError::OAuthError(msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("OAuth error: {}", msg),
            ),
            AuthError::PasswordResetTokenExpired => (
                StatusCode::BAD_REQUEST,
                "Password reset token expired".to_string(),
            ),
            AuthError::InvalidPasswordResetToken => (
                StatusCode::BAD_REQUEST,
                "Invalid password reset token".to_string(),
            ),
            AuthError::SessionNotFound => (
                StatusCode::NOT_FOUND,
                "Session not found".to_string(),
            ),
            AuthError::TwoFARequired => (
                StatusCode::UNAUTHORIZED,
                "Two FA required".to_string(),
            ),
            AuthError::InvalidTwoFACode => (
                StatusCode::UNAUTHORIZED,
                "Invalid two FA code".to_string(),
            ),
            AuthError::TwoFANotEnabled => (
                StatusCode::BAD_REQUEST,
                "Two FA not enabled".to_string(),
            ),
            AuthError::Database(msg) | AuthError::Redis(msg) | AuthError::JwtError(msg) | AuthError::Internal(msg) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                msg,
            ),
        };

        let body = Json(json!({
            "error": error_message,
        }));

        (status, body).into_response()
    }
}
