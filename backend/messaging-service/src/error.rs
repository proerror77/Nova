use crate::middleware::error_handling;
use axum::response::{IntoResponse, Response};
use thiserror::Error;

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        error_handling::into_response(self).into_response()
    }
}

pub type AppResult<T> = Result<T, AppError>;

/// Distinguishes between retryable and permanent errors
#[derive(Debug, Clone, Copy)]
pub enum ErrorKind {
    Retryable,
    Permanent,
}

#[derive(Debug, Error)]
pub enum AppError {
    #[error("configuration error: {0}")]
    Config(String),

    #[error("server start failure: {0}")]
    StartServer(String),

    #[error("bad request: {0}")]
    BadRequest(String),

    #[error("unauthorized")]
    Unauthorized,

    #[error("forbidden")]
    Forbidden,

    #[error("not found")]
    NotFound,

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("encryption error: {0}")]
    Encryption(String),

    #[error("internal server error")]
    Internal,

    #[error("message already recalled")]
    AlreadyRecalled,

    #[error("recall window expired (created_at: {created_at}, max_recall_minutes: {max_recall_minutes})")]
    RecallWindowExpired {
        created_at: chrono::DateTime<chrono::Utc>,
        max_recall_minutes: i64,
    },

    #[error("edit window expired (max_edit_minutes: {max_edit_minutes})")]
    EditWindowExpired { max_edit_minutes: i64 },

    #[error("version conflict: client version {client_version} != server version {current_version}, server content: {server_content}")]
    VersionConflict {
        current_version: i32,
        client_version: i32,
        server_content: String,
    },
}

impl AppError {
    /// Returns whether this error is retryable (e.g., database connection timeout)
    pub fn is_retryable(&self) -> bool {
        match self {
            AppError::Database(e) => {
                matches!(
                    e,
                    sqlx::Error::PoolTimedOut | sqlx::Error::PoolClosed | sqlx::Error::Io(_)
                )
            }
            AppError::Internal => true,
            _ => false,
        }
    }

    /// Returns HTTP status code
    pub fn status_code(&self) -> u16 {
        match self {
            AppError::BadRequest(_) => 400,
            AppError::Unauthorized => 401,
            AppError::Forbidden => 403,
            AppError::NotFound => 404,
            AppError::AlreadyRecalled => 410,        // 410 Gone
            AppError::VersionConflict { .. } => 409, // 409 Conflict
            AppError::RecallWindowExpired { .. } | AppError::EditWindowExpired { .. } => 403,
            AppError::Database(_) | AppError::Internal => 500,
            _ => 500,
        }
    }
}
