//! HTTP error response handling
//!
//! Provides utilities for consistent HTTP/REST API error responses

use serde::{Deserialize, Serialize};
use crate::{ServiceError, ValidationError};

/// Standard HTTP error response format
#[derive(Debug, Serialize, Deserialize)]
pub struct HttpErrorResponse {
    /// HTTP status code
    pub status: u16,

    /// Error code for client handling
    pub code: String,

    /// Human-readable error message
    pub message: String,

    /// Optional detailed error information
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<ErrorDetails>,

    /// Request ID for tracing
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,

    /// Timestamp of the error
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

/// Detailed error information
#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorDetails {
    /// Field-level validation errors
    #[serde(skip_serializing_if = "Option::is_none")]
    pub field_errors: Option<Vec<FieldError>>,

    /// Stack trace (only in debug mode)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stack_trace: Option<Vec<String>>,

    /// Additional context
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context: Option<serde_json::Value>,
}

/// Field-level error
#[derive(Debug, Serialize, Deserialize)]
pub struct FieldError {
    pub field: String,
    pub code: String,
    pub message: String,
}

impl HttpErrorResponse {
    /// Create new HTTP error response
    pub fn new(status: u16, code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            status,
            code: code.into(),
            message: message.into(),
            details: None,
            request_id: None,
            timestamp: chrono::Utc::now(),
        }
    }

    /// Add request ID for tracing
    pub fn with_request_id(mut self, request_id: impl Into<String>) -> Self {
        self.request_id = Some(request_id.into());
        self
    }

    /// Add error details
    pub fn with_details(mut self, details: ErrorDetails) -> Self {
        self.details = Some(details);
        self
    }

    /// Add field errors
    pub fn with_field_errors(mut self, errors: Vec<FieldError>) -> Self {
        let details = self.details.get_or_insert_with(|| ErrorDetails {
            field_errors: None,
            stack_trace: None,
            context: None,
        });
        details.field_errors = Some(errors);
        self
    }
}

/// Convert ServiceError to HTTP response
impl From<ServiceError> for HttpErrorResponse {
    fn from(error: ServiceError) -> Self {
        match error {
            ServiceError::NotFound { resource, .. } => {
                HttpErrorResponse::new(
                    404,
                    "NOT_FOUND",
                    format!("{} not found", resource),
                )
            }

            ServiceError::InvalidInput { message, .. } => {
                HttpErrorResponse::new(400, "INVALID_INPUT", message)
            }

            ServiceError::Unauthenticated { .. } => {
                HttpErrorResponse::new(401, "UNAUTHENTICATED", "Authentication required")
            }

            ServiceError::PermissionDenied { .. } => {
                HttpErrorResponse::new(403, "FORBIDDEN", "Insufficient permissions")
            }

            ServiceError::Validation { source } => {
                let field_errors: Vec<FieldError> = source
                    .field_errors
                    .into_iter()
                    .flat_map(|(field, errors)| {
                        errors.into_iter().map(move |e| FieldError {
                            field: field.clone(),
                            code: e.code,
                            message: e.message,
                        })
                    })
                    .collect();

                HttpErrorResponse::new(400, "VALIDATION_FAILED", source.message)
                    .with_field_errors(field_errors)
            }

            ServiceError::RateLimitExceeded { limit, window_seconds } => {
                let mut response = HttpErrorResponse::new(
                    429,
                    "RATE_LIMIT_EXCEEDED",
                    "Rate limit exceeded",
                );

                response.details = Some(ErrorDetails {
                    field_errors: None,
                    stack_trace: None,
                    context: Some(serde_json::json!({
                        "limit": limit,
                        "window_seconds": window_seconds,
                        "retry_after": window_seconds,
                    })),
                });

                response
            }

            ServiceError::Conflict { message } => {
                HttpErrorResponse::new(409, "CONFLICT", message)
            }

            ServiceError::Timeout { operation, .. } => {
                HttpErrorResponse::new(
                    504,
                    "TIMEOUT",
                    format!("{} timed out", operation),
                )
            }

            ServiceError::CircuitBreakerOpen { service } => {
                HttpErrorResponse::new(
                    503,
                    "SERVICE_UNAVAILABLE",
                    format!("{} is temporarily unavailable", service),
                )
            }

            ServiceError::ExternalService { service, .. } => {
                HttpErrorResponse::new(
                    502,
                    "BAD_GATEWAY",
                    format!("{} service error", service),
                )
            }

            _ => {
                HttpErrorResponse::new(500, "INTERNAL_ERROR", "Internal server error")
            }
        }
    }
}

/// HTTP status code helpers
pub mod status {
    pub const OK: u16 = 200;
    pub const CREATED: u16 = 201;
    pub const ACCEPTED: u16 = 202;
    pub const NO_CONTENT: u16 = 204;

    pub const BAD_REQUEST: u16 = 400;
    pub const UNAUTHORIZED: u16 = 401;
    pub const FORBIDDEN: u16 = 403;
    pub const NOT_FOUND: u16 = 404;
    pub const METHOD_NOT_ALLOWED: u16 = 405;
    pub const CONFLICT: u16 = 409;
    pub const UNPROCESSABLE_ENTITY: u16 = 422;
    pub const TOO_MANY_REQUESTS: u16 = 429;

    pub const INTERNAL_SERVER_ERROR: u16 = 500;
    pub const BAD_GATEWAY: u16 = 502;
    pub const SERVICE_UNAVAILABLE: u16 = 503;
    pub const GATEWAY_TIMEOUT: u16 = 504;
}

/// Helper function to create standard responses
pub mod responses {
    use super::*;

    /// Create a not found response
    pub fn not_found(resource: &str) -> HttpErrorResponse {
        HttpErrorResponse::new(404, "NOT_FOUND", format!("{} not found", resource))
    }

    /// Create a validation error response
    pub fn validation_error(errors: Vec<(&str, &str)>) -> HttpErrorResponse {
        let field_errors = errors
            .into_iter()
            .map(|(field, message)| FieldError {
                field: field.to_string(),
                code: "INVALID".to_string(),
                message: message.to_string(),
            })
            .collect();

        HttpErrorResponse::new(400, "VALIDATION_FAILED", "Validation failed")
            .with_field_errors(field_errors)
    }

    /// Create an unauthorized response
    pub fn unauthorized() -> HttpErrorResponse {
        HttpErrorResponse::new(401, "UNAUTHORIZED", "Authentication required")
    }

    /// Create a forbidden response
    pub fn forbidden() -> HttpErrorResponse {
        HttpErrorResponse::new(403, "FORBIDDEN", "Access denied")
    }

    /// Create a rate limit response
    pub fn rate_limited(retry_after_seconds: u32) -> HttpErrorResponse {
        let mut response = HttpErrorResponse::new(429, "RATE_LIMITED", "Too many requests");
        response.details = Some(ErrorDetails {
            field_errors: None,
            stack_trace: None,
            context: Some(serde_json::json!({
                "retry_after": retry_after_seconds,
            })),
        });
        response
    }

    /// Create an internal error response
    pub fn internal_error(request_id: Option<String>) -> HttpErrorResponse {
        let mut response = HttpErrorResponse::new(500, "INTERNAL_ERROR", "An error occurred");
        if let Some(id) = request_id {
            response = response.with_request_id(id);
        }
        response
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_response_serialization() {
        let response = HttpErrorResponse::new(404, "NOT_FOUND", "User not found")
            .with_request_id("req-123");

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("\"status\":404"));
        assert!(json.contains("\"code\":\"NOT_FOUND\""));
        assert!(json.contains("\"request_id\":\"req-123\""));
    }

    #[test]
    fn test_validation_error_response() {
        let response = responses::validation_error(vec![
            ("email", "Invalid format"),
            ("age", "Must be positive"),
        ]);

        assert_eq!(response.status, 400);
        assert_eq!(response.code, "VALIDATION_FAILED");
        assert!(response.details.is_some());

        let details = response.details.unwrap();
        assert!(details.field_errors.is_some());
        assert_eq!(details.field_errors.unwrap().len(), 2);
    }
}