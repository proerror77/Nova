//! Unified error handling for all Nova services
//!
//! Provides consistent error types that work across service boundaries

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Result type alias for Nova services
pub type Result<T> = std::result::Result<T, ServiceError>;

/// Unified error type for inter-service communication
#[derive(Error, Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "error_type", content = "details")]
pub enum ServiceError {
    /// Authentication failed
    #[error("Authentication failed: {0}")]
    Authentication(String),

    /// Authorization failed
    #[error("Authorization failed: {0}")]
    Authorization(String),

    /// Validation error
    #[error("Validation error: {0}")]
    Validation(String),

    /// Not found
    #[error("Resource not found: {0}")]
    NotFound(String),

    /// Conflict (e.g., resource already exists)
    #[error("Conflict: {0}")]
    Conflict(String),

    /// Internal server error
    #[error("Internal error: {0}")]
    Internal(String),

    /// Service unavailable
    #[error("Service unavailable: {0}")]
    ServiceUnavailable(String),

    /// Timeout
    #[error("Timeout: {0}")]
    Timeout(String),

    /// Database error
    #[error("Database error: {0}")]
    DatabaseError(String),

    /// Cache error
    #[error("Cache error: {0}")]
    CacheError(String),

    /// External service call failed
    #[error("External service error: {0}")]
    ExternalService(String),

    /// Invalid request
    #[error("Invalid request: {0}")]
    InvalidRequest(String),
}

impl ServiceError {
    /// Get HTTP status code for this error
    pub fn status_code(&self) -> u16 {
        match self {
            Self::Authentication(_) => 401,
            Self::Authorization(_) => 403,
            Self::Validation(_) => 400,
            Self::NotFound(_) => 404,
            Self::Conflict(_) => 409,
            Self::Internal(_) => 500,
            Self::ServiceUnavailable(_) => 503,
            Self::Timeout(_) => 504,
            Self::DatabaseError(_) => 500,
            Self::CacheError(_) => 500,
            Self::ExternalService(_) => 502,
            Self::InvalidRequest(_) => 400,
        }
    }

    /// Check if this is a retryable error
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::ServiceUnavailable(_) | Self::Timeout(_) | Self::CacheError(_)
        )
    }
}

impl From<anyhow::Error> for ServiceError {
    fn from(err: anyhow::Error) -> Self {
        ServiceError::Internal(err.to_string())
    }
}
