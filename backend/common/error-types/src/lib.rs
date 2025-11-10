//! Unified error types for Nova backend services
//!
//! This library provides standardized error handling across all microservices,
//! ensuring consistent error reporting, logging, and client responses.
//!
//! # Design Principles
//!
//! 1. **Type Safety**: Strongly typed errors prevent runtime surprises
//! 2. **Context Preservation**: Errors carry context for debugging
//! 3. **GDPR Compliance**: No PII in error messages
//! 4. **gRPC Integration**: Maps cleanly to gRPC status codes
//! 5. **Observability**: Structured logging with tracing

use std::fmt;
use thiserror::Error;
use tonic::{Code, Status};
use uuid::Uuid;

pub mod database;
pub mod validation;
pub mod auth;
pub mod grpc;
pub mod http;

// Re-export common types
pub use database::DatabaseError;
pub use validation::ValidationError;
pub use auth::AuthError;

/// Core service error type used across all Nova services
///
/// # Example
/// ```rust
/// use error_types::ServiceError;
///
/// fn process_user(id: Uuid) -> Result<User, ServiceError> {
///     let user = db.get_user(id)
///         .await
///         .map_err(|e| ServiceError::NotFound {
///             resource: "user",
///             id: id.to_string(),
///         })?;
///     Ok(user)
/// }
/// ```
#[derive(Debug, Error)]
pub enum ServiceError {
    /// Resource not found
    #[error("Resource not found: {resource}")]
    NotFound {
        resource: &'static str,
        #[source]
        id: String,
    },

    /// Invalid input provided
    #[error("Invalid input: {message}")]
    InvalidInput {
        message: String,
        #[source]
        source: Option<Box<dyn std::error::Error + Send + Sync>>,
    },

    /// Authentication required
    #[error("Authentication required")]
    Unauthenticated {
        #[source]
        source: Option<AuthError>,
    },

    /// Permission denied
    #[error("Permission denied")]
    PermissionDenied {
        action: String,
        resource: String,
    },

    /// Database operation failed
    #[error("Database error")]
    Database {
        #[from]
        source: DatabaseError,
    },

    /// Validation failed
    #[error("Validation failed")]
    Validation {
        #[from]
        source: ValidationError,
    },

    /// External service error
    #[error("External service error: {service}")]
    ExternalService {
        service: String,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },

    /// Rate limit exceeded
    #[error("Rate limit exceeded")]
    RateLimitExceeded {
        limit: u32,
        window_seconds: u32,
    },

    /// Internal server error (catch-all)
    #[error("Internal server error")]
    Internal {
        #[source]
        source: anyhow::Error,
    },

    /// Conflict (e.g., duplicate resource)
    #[error("Conflict: {message}")]
    Conflict {
        message: String,
    },

    /// Timeout
    #[error("Operation timed out")]
    Timeout {
        operation: String,
        timeout_ms: u64,
    },

    /// Circuit breaker open
    #[error("Service temporarily unavailable")]
    CircuitBreakerOpen {
        service: String,
    },
}

impl ServiceError {
    /// Convert to gRPC Status for service boundaries
    pub fn to_status(&self) -> Status {
        match self {
            Self::NotFound { resource, .. } => {
                Status::not_found(format!("{} not found", resource))
            }
            Self::InvalidInput { message, .. } => {
                Status::invalid_argument(message)
            }
            Self::Unauthenticated { .. } => {
                Status::unauthenticated("Authentication required")
            }
            Self::PermissionDenied { .. } => {
                Status::permission_denied("Insufficient permissions")
            }
            Self::Database { .. } => {
                // Don't expose database details to clients
                Status::internal("Database operation failed")
            }
            Self::Validation { source } => {
                Status::invalid_argument(source.to_string())
            }
            Self::ExternalService { service, .. } => {
                Status::unavailable(format!("{} is unavailable", service))
            }
            Self::RateLimitExceeded { .. } => {
                Status::resource_exhausted("Rate limit exceeded")
            }
            Self::Internal { .. } => {
                Status::internal("Internal server error")
            }
            Self::Conflict { message } => {
                Status::already_exists(message)
            }
            Self::Timeout { operation, .. } => {
                Status::deadline_exceeded(format!("{} timed out", operation))
            }
            Self::CircuitBreakerOpen { service } => {
                Status::unavailable(format!("{} is temporarily unavailable", service))
            }
        }
    }

    /// Log error with appropriate level and context
    pub fn log(&self) {
        match self {
            Self::NotFound { .. } | Self::InvalidInput { .. } => {
                tracing::debug!(error = ?self, "Client error");
            }
            Self::Unauthenticated { .. } | Self::PermissionDenied { .. } => {
                tracing::warn!(error = ?self, "Authorization failure");
            }
            Self::RateLimitExceeded { .. } => {
                tracing::info!(error = ?self, "Rate limit hit");
            }
            Self::Database { .. } | Self::Internal { .. } => {
                tracing::error!(error = ?self, "Server error");
            }
            Self::ExternalService { .. } | Self::Timeout { .. } | Self::CircuitBreakerOpen { .. } => {
                tracing::warn!(error = ?self, "Dependency issue");
            }
            _ => {
                tracing::info!(error = ?self, "Service error");
            }
        }
    }

    /// Create internal error from any error type
    pub fn internal<E: Into<anyhow::Error>>(error: E) -> Self {
        Self::Internal {
            source: error.into(),
        }
    }
}

impl From<Status> for ServiceError {
    fn from(status: Status) -> Self {
        match status.code() {
            Code::NotFound => Self::NotFound {
                resource: "resource",
                id: String::new(),
            },
            Code::InvalidArgument => Self::InvalidInput {
                message: status.message().to_string(),
                source: None,
            },
            Code::Unauthenticated => Self::Unauthenticated { source: None },
            Code::PermissionDenied => Self::PermissionDenied {
                action: String::new(),
                resource: String::new(),
            },
            Code::ResourceExhausted => Self::RateLimitExceeded {
                limit: 0,
                window_seconds: 0,
            },
            Code::DeadlineExceeded => Self::Timeout {
                operation: String::new(),
                timeout_ms: 0,
            },
            _ => Self::internal(anyhow::anyhow!("gRPC error: {}", status)),
        }
    }
}

/// Result type alias for Service operations
pub type ServiceResult<T> = Result<T, ServiceError>;

/// Error context extension trait for adding context to Results
pub trait ErrorContext<T> {
    /// Add context to an error
    fn context<C>(self, context: C) -> ServiceResult<T>
    where
        C: fmt::Display + Send + Sync + 'static;

    /// Add lazy context (only evaluated on error)
    fn with_context<C, F>(self, f: F) -> ServiceResult<T>
    where
        C: fmt::Display + Send + Sync + 'static,
        F: FnOnce() -> C;
}

impl<T, E> ErrorContext<T> for Result<T, E>
where
    E: std::error::Error + Send + Sync + 'static,
{
    fn context<C>(self, context: C) -> ServiceResult<T>
    where
        C: fmt::Display + Send + Sync + 'static,
    {
        self.map_err(|e| {
            ServiceError::internal(anyhow::anyhow!("{}: {}", context, e))
        })
    }

    fn with_context<C, F>(self, f: F) -> ServiceResult<T>
    where
        C: fmt::Display + Send + Sync + 'static,
        F: FnOnce() -> C,
    {
        self.map_err(|e| {
            ServiceError::internal(anyhow::anyhow!("{}: {}", f(), e))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_to_status_conversion() {
        let error = ServiceError::NotFound {
            resource: "user",
            id: "123".to_string(),
        };

        let status = error.to_status();
        assert_eq!(status.code(), Code::NotFound);
        assert_eq!(status.message(), "user not found");
    }

    #[test]
    fn test_no_pii_in_error_messages() {
        let error = ServiceError::NotFound {
            resource: "user",
            id: "user@example.com".to_string(), // PII in id field
        };

        // Error message should not contain the ID (PII)
        let message = error.to_string();
        assert!(!message.contains("user@example.com"));
        assert_eq!(message, "Resource not found: user");
    }

    #[test]
    fn test_error_context() {
        fn failing_operation() -> Result<(), std::io::Error> {
            Err(std::io::Error::new(std::io::ErrorKind::NotFound, "file not found"))
        }

        let result: ServiceResult<()> = failing_operation()
            .context("Failed to load configuration");

        assert!(result.is_err());
        let error = result.unwrap_err();
        matches!(error, ServiceError::Internal { .. });
    }
}