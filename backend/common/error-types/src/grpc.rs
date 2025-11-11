//! gRPC-specific error handling
//!
//! Provides utilities for consistent gRPC error responses
//! and status code mapping.

use tonic::{Code, Status, Request, Response};
use std::time::Duration;
use crate::{ServiceError, AuthError};

/// Extension trait for adding metadata to gRPC Status
pub trait StatusExt {
    /// Add retry info to status
    fn with_retry_info(self, retry_after: Duration) -> Self;

    /// Add error code for client handling
    fn with_error_code(self, code: &str) -> Self;

    /// Add field violations for validation errors
    fn with_field_violations(self, violations: Vec<FieldViolation>) -> Self;
}

impl StatusExt for Status {
    fn with_retry_info(mut self, retry_after: Duration) -> Self {
        self.metadata_mut().insert(
            "x-retry-after",
            retry_after.as_secs().to_string().parse().unwrap(),
        );
        self
    }

    fn with_error_code(mut self, code: &str) -> Self {
        self.metadata_mut().insert(
            "x-error-code",
            code.parse().unwrap(),
        );
        self
    }

    fn with_field_violations(mut self, violations: Vec<FieldViolation>) -> Self {
        if let Ok(json) = serde_json::to_string(&violations) {
            self.metadata_mut().insert(
                "x-field-violations",
                json.parse().unwrap(),
            );
        }
        self
    }
}

/// Field violation for validation errors
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct FieldViolation {
    pub field: String,
    pub description: String,
}

/// Convert ServiceError to Status with rich metadata
pub fn service_error_to_status(error: &ServiceError) -> Status {
    match error {
        ServiceError::NotFound { resource, .. } => {
            Status::not_found(format!("{} not found", resource))
                .with_error_code("RESOURCE_NOT_FOUND")
        }

        ServiceError::InvalidInput { message, .. } => {
            Status::invalid_argument(message)
                .with_error_code("INVALID_INPUT")
        }

        ServiceError::Unauthenticated { source } => {
            let status = Status::unauthenticated("Authentication required");
            if let Some(auth_error) = source {
                match auth_error {
                    AuthError::TokenExpired { .. } => {
                        status.with_error_code("TOKEN_EXPIRED")
                    }
                    AuthError::InvalidCredentials => {
                        status.with_error_code("INVALID_CREDENTIALS")
                    }
                    _ => status.with_error_code("AUTH_FAILED")
                }
            } else {
                status.with_error_code("AUTH_REQUIRED")
            }
        }

        ServiceError::PermissionDenied { action, resource } => {
            Status::permission_denied("Insufficient permissions")
                .with_error_code("PERMISSION_DENIED")
                .with_metadata("action", action)
                .with_metadata("resource", resource)
        }

        ServiceError::RateLimitExceeded { window_seconds, .. } => {
            Status::resource_exhausted("Rate limit exceeded")
                .with_error_code("RATE_LIMIT_EXCEEDED")
                .with_retry_info(Duration::from_secs(*window_seconds as u64))
        }

        ServiceError::Timeout { operation, timeout_ms } => {
            Status::deadline_exceeded(format!("{} timed out", operation))
                .with_error_code("TIMEOUT")
                .with_metadata("timeout_ms", &timeout_ms.to_string())
        }

        ServiceError::CircuitBreakerOpen { service } => {
            Status::unavailable(format!("{} temporarily unavailable", service))
                .with_error_code("CIRCUIT_BREAKER_OPEN")
                .with_retry_info(Duration::from_secs(30))
        }

        _ => Status::internal("Internal server error")
            .with_error_code("INTERNAL_ERROR")
    }
}

/// Extension trait for Status to add metadata
trait StatusMetadataExt {
    fn with_metadata(self, key: &str, value: &str) -> Self;
}

impl StatusMetadataExt for Status {
    fn with_metadata(mut self, key: &str, value: &str) -> Self {
        if let Ok(parsed) = value.parse() {
            self.metadata_mut().insert(key, parsed);
        }
        self
    }
}

/// Interceptor for consistent error handling
pub async fn error_interceptor<T>(
    req: Request<T>,
    next: impl Fn(Request<T>) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Response<T>, Status>> + Send>>,
) -> Result<Response<T>, Status> {
    let result = next(req).await;

    if let Err(status) = &result {
        // Log error with context
        match status.code() {
            Code::InvalidArgument | Code::NotFound => {
                tracing::debug!(
                    code = ?status.code(),
                    message = %status.message(),
                    "Client error"
                );
            }
            Code::Unauthenticated | Code::PermissionDenied => {
                tracing::warn!(
                    code = ?status.code(),
                    message = %status.message(),
                    "Auth error"
                );
            }
            Code::Internal | Code::Unknown => {
                tracing::error!(
                    code = ?status.code(),
                    message = %status.message(),
                    "Internal error"
                );
            }
            _ => {
                tracing::info!(
                    code = ?status.code(),
                    message = %status.message(),
                    "Service error"
                );
            }
        }
    }

    result
}

/// Helper to create Status from validation errors
pub fn validation_error_to_status(
    field_errors: Vec<(&str, &str)>,
) -> Status {
    let violations: Vec<FieldViolation> = field_errors
        .into_iter()
        .map(|(field, desc)| FieldViolation {
            field: field.to_string(),
            description: desc.to_string(),
        })
        .collect();

    Status::invalid_argument("Validation failed")
        .with_error_code("VALIDATION_FAILED")
        .with_field_violations(violations)
}

/// Macro for consistent gRPC error handling
#[macro_export]
macro_rules! grpc_error {
    ($err:expr) => {
        |e| {
            let service_error = $crate::ServiceError::from(e);
            service_error.log();
            $crate::grpc::service_error_to_status(&service_error)
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_status_with_retry_info() {
        let status = Status::resource_exhausted("Rate limited")
            .with_retry_info(Duration::from_secs(60));

        assert!(status.metadata().contains_key("x-retry-after"));
    }

    #[test]
    fn test_validation_error_to_status() {
        let status = validation_error_to_status(vec![
            ("email", "Invalid email format"),
            ("age", "Must be at least 18"),
        ]);

        assert_eq!(status.code(), Code::InvalidArgument);
        assert!(status.metadata().contains_key("x-field-violations"));
    }
}