use thiserror::Error;
use axum::response::{IntoResponse, Response};
use crate::middleware::error_handling;

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
}

impl AppError {
    /// Returns whether this error is retryable (e.g., database connection timeout)
    pub fn is_retryable(&self) -> bool {
        match self {
            AppError::Database(e) => {
                matches!(e,
                    sqlx::Error::PoolTimedOut |
                    sqlx::Error::PoolClosed |
                    sqlx::Error::Io(_)
                )
            },
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
            AppError::Database(_) | AppError::Internal => 500,
            _ => 500,
        }
    }
}
