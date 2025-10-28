/// Error types for Content Service
///
/// This module defines all error types that can occur in the content-service.
/// Errors are converted to appropriate HTTP responses for API clients.

use actix_web::{error::ResponseError, http::StatusCode, HttpResponse};
use std::fmt;

/// Result type for content-service operations
pub type Result<T> = std::result::Result<T, AppError>;

/// Application error types
#[derive(Debug)]
pub enum AppError {
    /// Database operation failed
    DatabaseError(String),

    /// Cache operation failed
    CacheError(String),

    /// Validation failed
    ValidationError(String),

    /// Resource not found
    NotFound(String),

    /// Unauthorized access
    Unauthorized(String),

    /// Forbidden access
    Forbidden(String),

    /// Internal server error
    Internal(String),

    /// Bad request
    BadRequest(String),

    /// Conflict (duplicate resource, etc.)
    Conflict(String),
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppError::DatabaseError(msg) => write!(f, "Database error: {}", msg),
            AppError::CacheError(msg) => write!(f, "Cache error: {}", msg),
            AppError::ValidationError(msg) => write!(f, "Validation error: {}", msg),
            AppError::NotFound(msg) => write!(f, "Not found: {}", msg),
            AppError::Unauthorized(msg) => write!(f, "Unauthorized: {}", msg),
            AppError::Forbidden(msg) => write!(f, "Forbidden: {}", msg),
            AppError::Internal(msg) => write!(f, "Internal error: {}", msg),
            AppError::BadRequest(msg) => write!(f, "Bad request: {}", msg),
            AppError::Conflict(msg) => write!(f, "Conflict: {}", msg),
        }
    }
}

impl ResponseError for AppError {
    fn status_code(&self) -> StatusCode {
        match self {
            AppError::DatabaseError(_) | AppError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::CacheError(_) => StatusCode::INTERNAL_SERVER_ERROR,
            AppError::ValidationError(_) => StatusCode::BAD_REQUEST,
            AppError::NotFound(_) => StatusCode::NOT_FOUND,
            AppError::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            AppError::Forbidden(_) => StatusCode::FORBIDDEN,
            AppError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AppError::Conflict(_) => StatusCode::CONFLICT,
        }
    }

    fn error_response(&self) -> HttpResponse {
        let status = self.status_code();
        let error_msg = self.to_string();

        HttpResponse::build(status).json(serde_json::json!({
            "error": error_msg,
            "status": status.as_u16(),
        }))
    }
}

impl From<String> for AppError {
    fn from(msg: String) -> Self {
        AppError::Internal(msg)
    }
}

impl From<&str> for AppError {
    fn from(msg: &str) -> Self {
        AppError::Internal(msg.to_string())
    }
}

impl From<sqlx::Error> for AppError {
    fn from(err: sqlx::Error) -> Self {
        AppError::DatabaseError(err.to_string())
    }
}

impl From<serde_json::Error> for AppError {
    fn from(err: serde_json::Error) -> Self {
        AppError::Internal(err.to_string())
    }
}
