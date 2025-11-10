//! Validation error types
//!
//! Provides structured validation errors with field-level details
//! for input validation across all services.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

/// Validation error with field-level details
#[derive(Debug, Error, Clone, Serialize, Deserialize)]
#[error("Validation failed: {message}")]
pub struct ValidationError {
    /// High-level validation message
    pub message: String,

    /// Field-specific errors
    pub field_errors: HashMap<String, Vec<FieldError>>,

    /// Global errors not tied to specific fields
    pub global_errors: Vec<String>,
}

impl ValidationError {
    /// Create a new validation error
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            field_errors: HashMap::new(),
            global_errors: Vec::new(),
        }
    }

    /// Add a field error
    pub fn add_field_error(
        mut self,
        field: impl Into<String>,
        code: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        let field = field.into();
        let error = FieldError {
            code: code.into(),
            message: message.into(),
            params: HashMap::new(),
        };

        self.field_errors
            .entry(field)
            .or_insert_with(Vec::new)
            .push(error);

        self
    }

    /// Add a global error
    pub fn add_global_error(mut self, message: impl Into<String>) -> Self {
        self.global_errors.push(message.into());
        self
    }

    /// Check if validation has any errors
    pub fn has_errors(&self) -> bool {
        !self.field_errors.is_empty() || !self.global_errors.is_empty()
    }

    /// Get total error count
    pub fn error_count(&self) -> usize {
        self.field_errors.values().map(|v| v.len()).sum::<usize>()
            + self.global_errors.len()
    }

    /// Convert to client-friendly JSON response
    pub fn to_response(&self) -> ValidationResponse {
        ValidationResponse {
            message: self.message.clone(),
            errors: self.field_errors.clone(),
            global_errors: self.global_errors.clone(),
        }
    }
}

/// Individual field validation error
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldError {
    /// Error code (e.g., "required", "invalid_format", "too_long")
    pub code: String,

    /// Human-readable error message
    pub message: String,

    /// Additional parameters for the error
    pub params: HashMap<String, serde_json::Value>,
}

/// Client-friendly validation response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResponse {
    pub message: String,
    pub errors: HashMap<String, Vec<FieldError>>,
    pub global_errors: Vec<String>,
}

/// Common validation rules
pub mod rules {
    use super::ValidationError;
    use regex::Regex;
    use uuid::Uuid;

    /// Validate email format
    pub fn validate_email(email: &str) -> Result<(), ValidationError> {
        // RFC 5322 simplified regex
        let email_regex = Regex::new(
            r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        ).unwrap();

        if !email_regex.is_match(email) {
            return Err(ValidationError::new("Invalid email format")
                .add_field_error("email", "invalid_format", "Email address is not valid"));
        }

        Ok(())
    }

    /// Validate UUID format
    pub fn validate_uuid(value: &str) -> Result<Uuid, ValidationError> {
        Uuid::parse_str(value).map_err(|_| {
            ValidationError::new("Invalid UUID")
                .add_field_error("id", "invalid_format", "Must be a valid UUID")
        })
    }

    /// Validate string length
    pub fn validate_length(
        field: &str,
        value: &str,
        min: Option<usize>,
        max: Option<usize>,
    ) -> Result<(), ValidationError> {
        let len = value.len();

        if let Some(min) = min {
            if len < min {
                return Err(ValidationError::new("Validation failed")
                    .add_field_error(
                        field,
                        "too_short",
                        format!("Must be at least {} characters", min),
                    ));
            }
        }

        if let Some(max) = max {
            if len > max {
                return Err(ValidationError::new("Validation failed")
                    .add_field_error(
                        field,
                        "too_long",
                        format!("Must be at most {} characters", max),
                    ));
            }
        }

        Ok(())
    }

    /// Validate required field
    pub fn validate_required(field: &str, value: &str) -> Result<(), ValidationError> {
        if value.trim().is_empty() {
            return Err(ValidationError::new("Validation failed")
                .add_field_error(field, "required", "This field is required"));
        }
        Ok(())
    }

    /// Validate numeric range
    pub fn validate_range<T: PartialOrd + std::fmt::Display>(
        field: &str,
        value: T,
        min: Option<T>,
        max: Option<T>,
    ) -> Result<(), ValidationError> {
        if let Some(min) = min {
            if value < min {
                return Err(ValidationError::new("Validation failed")
                    .add_field_error(
                        field,
                        "too_small",
                        format!("Must be at least {}", min),
                    ));
            }
        }

        if let Some(max) = max {
            if value > max {
                return Err(ValidationError::new("Validation failed")
                    .add_field_error(
                        field,
                        "too_large",
                        format!("Must be at most {}", max),
                    ));
            }
        }

        Ok(())
    }
}

/// Builder for validation errors
pub struct ValidationErrorBuilder {
    error: ValidationError,
}

impl ValidationErrorBuilder {
    /// Create new builder
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            error: ValidationError::new(message),
        }
    }

    /// Add field error
    pub fn field(
        mut self,
        field: impl Into<String>,
        code: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        self.error = self.error.add_field_error(field, code, message);
        self
    }

    /// Add global error
    pub fn global(mut self, message: impl Into<String>) -> Self {
        self.error = self.error.add_global_error(message);
        self
    }

    /// Build the error if there are any errors, otherwise return Ok
    pub fn build<T>(self) -> Result<T, ValidationError> {
        if self.error.has_errors() {
            Err(self.error)
        } else {
            // This should not happen in practice as builder is used when errors exist
            Err(self.error)
        }
    }

    /// Build and return the error
    pub fn into_error(self) -> ValidationError {
        self.error
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::rules::*;

    #[test]
    fn test_validation_error_builder() {
        let error = ValidationError::new("User validation failed")
            .add_field_error("email", "required", "Email is required")
            .add_field_error("email", "invalid_format", "Invalid email format")
            .add_field_error("age", "too_young", "Must be at least 18")
            .add_global_error("Service temporarily unavailable");

        assert_eq!(error.error_count(), 4);
        assert!(error.has_errors());
        assert_eq!(error.field_errors["email"].len(), 2);
    }

    #[test]
    fn test_email_validation() {
        assert!(validate_email("user@example.com").is_ok());
        assert!(validate_email("invalid-email").is_err());
        assert!(validate_email("@example.com").is_err());
        assert!(validate_email("user@").is_err());
    }

    #[test]
    fn test_length_validation() {
        assert!(validate_length("name", "John", Some(3), Some(10)).is_ok());
        assert!(validate_length("name", "Jo", Some(3), Some(10)).is_err());
        assert!(validate_length("name", "VeryLongName", Some(3), Some(10)).is_err());
    }

    #[test]
    fn test_range_validation() {
        assert!(validate_range("age", 25, Some(18), Some(100)).is_ok());
        assert!(validate_range("age", 15, Some(18), Some(100)).is_err());
        assert!(validate_range("age", 150, Some(18), Some(100)).is_err());
    }
}