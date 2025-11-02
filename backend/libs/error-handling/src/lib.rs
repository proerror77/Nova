//! Unified error handling library for Nova microservices
//!
//! Provides consistent error types, conversion helpers, and HTTP response formatting

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Standard error response for all services
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
    pub message: String,
    pub status: u16,
    pub error_type: String,
    pub code: String,
    pub details: Option<String>,
    pub timestamp: String,
}

/// Service-level error type
#[derive(Debug, Error)]
pub enum ServiceError {
    #[error("Database error: {0}")]
    Database(String),

    #[error("Resource not found: {0}")]
    NotFound(String),

    #[error("Unauthorized")]
    Unauthorized,

    #[error("Forbidden")]
    Forbidden,

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Internal server error: {0}")]
    InternalError(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Service unavailable")]
    ServiceUnavailable,

    #[error("Timeout")]
    Timeout,
}

impl ServiceError {
    pub fn status_code(&self) -> u16 {
        match self {
            ServiceError::NotFound(_) => 404,
            ServiceError::Unauthorized => 401,
            ServiceError::Forbidden => 403,
            ServiceError::ValidationError(_) => 400,
            ServiceError::BadRequest(_) => 400,
            ServiceError::Conflict(_) => 409,
            ServiceError::ServiceUnavailable => 503,
            ServiceError::Timeout => 408,
            ServiceError::Database(_) | ServiceError::InternalError(_) => 500,
        }
    }

    pub fn error_code(&self) -> &'static str {
        match self {
            ServiceError::NotFound(_) => "NOT_FOUND",
            ServiceError::Unauthorized => "UNAUTHORIZED",
            ServiceError::Forbidden => "FORBIDDEN",
            ServiceError::ValidationError(_) => "VALIDATION_ERROR",
            ServiceError::BadRequest(_) => "BAD_REQUEST",
            ServiceError::Conflict(_) => "CONFLICT",
            ServiceError::ServiceUnavailable => "SERVICE_UNAVAILABLE",
            ServiceError::Timeout => "TIMEOUT",
            ServiceError::Database(_) => "DATABASE_ERROR",
            ServiceError::InternalError(_) => "INTERNAL_ERROR",
        }
    }

    pub fn error_type(&self) -> &'static str {
        match self {
            ServiceError::Database(_) => "DatabaseError",
            ServiceError::NotFound(_) => "NotFoundError",
            ServiceError::Unauthorized => "UnauthorizedError",
            ServiceError::Forbidden => "ForbiddenError",
            ServiceError::ValidationError(_) => "ValidationError",
            ServiceError::BadRequest(_) => "BadRequestError",
            ServiceError::Conflict(_) => "ConflictError",
            ServiceError::ServiceUnavailable => "ServiceUnavailableError",
            ServiceError::Timeout => "TimeoutError",
            ServiceError::InternalError(_) => "InternalError",
        }
    }

    pub fn to_response(&self) -> ErrorResponse {
        ErrorResponse {
            error: self.error_type().to_string(),
            message: self.to_string(),
            status: self.status_code(),
            error_type: self.error_type().to_string(),
            code: self.error_code().to_string(),
            details: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }
}

impl From<sqlx::Error> for ServiceError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => ServiceError::NotFound("Resource not found".to_string()),
            _ => ServiceError::Database(err.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_status_codes() {
        assert_eq!(
            ServiceError::NotFound("test".to_string()).status_code(),
            404
        );
        assert_eq!(ServiceError::Unauthorized.status_code(), 401);
        assert_eq!(
            ServiceError::ValidationError("test".to_string()).status_code(),
            400
        );
    }

    #[test]
    fn test_error_response_format() {
        let err = ServiceError::NotFound("User".to_string());
        let response = err.to_response();
        assert_eq!(response.status, 404);
        assert_eq!(response.code, "NOT_FOUND");
    }
}
