//! UUID Utility Library
//!
//! Eliminates duplicate UUID parsing logic across all microservices.
//! Provides type-safe UUID handling with clear error messages.
//!
//! **Problem Solved**:
//! Before this library, every service had ~20-30 instances of:
//! ```rust,ignore
//! let video_uuid = Uuid::parse_str(&video_id)
//!     .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;
//! ```
//!
//! **After**:
//! ```rust
//! use uuid_utils::parse_uuid;
//! let video_uuid = parse_uuid(&video_id, "video_id")?;
//! ```
//!
//! **Features**:
//! - Type-safe UUID parsing with descriptive errors
//! - Optional actix-web integration (`actix` feature)
//! - Optional tonic/gRPC integration (`grpc` feature)
//! - Zero-cost abstractions (compiled away)

use uuid::Uuid;
use thiserror::Error;

// ============================================================================
// Error Types
// ============================================================================

/// Error type for UUID parsing failures
#[derive(Debug, Error)]
pub enum UuidError {
    #[error("Invalid UUID for field '{field}': {details}")]
    InvalidFormat {
        field: String,
        details: String,
    },

    #[error("Missing required UUID field: {field}")]
    MissingField {
        field: String,
    },
}

// ============================================================================
// Core Parsing Functions
// ============================================================================

/// Parse a UUID from string with field name for error context
///
/// # Examples
///
/// ```
/// use uuid_utils::parse_uuid;
///
/// // Success case
/// let uuid = parse_uuid("550e8400-e29b-41d4-a716-446655440000", "user_id").unwrap();
///
/// // Error case (descriptive error)
/// let err = parse_uuid("not-a-uuid", "video_id").unwrap_err();
/// assert!(err.to_string().contains("video_id"));
/// ```
pub fn parse_uuid(input: &str, field: &str) -> Result<Uuid, UuidError> {
    Uuid::parse_str(input).map_err(|e| UuidError::InvalidFormat {
        field: field.to_string(),
        details: e.to_string(),
    })
}

/// Parse an optional UUID (returns None if input is empty)
///
/// # Examples
///
/// ```
/// use uuid_utils::parse_uuid_opt;
///
/// // Empty string ’ None
/// assert_eq!(parse_uuid_opt("", "optional_id").unwrap(), None);
///
/// // Valid UUID ’ Some(Uuid)
/// let uuid = parse_uuid_opt("550e8400-e29b-41d4-a716-446655440000", "optional_id").unwrap();
/// assert!(uuid.is_some());
/// ```
pub fn parse_uuid_opt(input: &str, field: &str) -> Result<Option<Uuid>, UuidError> {
    if input.trim().is_empty() {
        return Ok(None);
    }
    parse_uuid(input, field).map(Some)
}

/// Parse a vector of UUIDs
///
/// # Examples
///
/// ```
/// use uuid_utils::parse_uuid_vec;
///
/// let ids = vec!["550e8400-e29b-41d4-a716-446655440000"];
/// let uuids = parse_uuid_vec(&ids, "user_ids").unwrap();
/// assert_eq!(uuids.len(), 1);
/// ```
pub fn parse_uuid_vec(inputs: &[String], field: &str) -> Result<Vec<Uuid>, UuidError> {
    inputs
        .iter()
        .enumerate()
        .map(|(i, s)| parse_uuid(s, &format!("{}[{}]", field, i)))
        .collect()
}

// ============================================================================
// Actix-web Integration (feature = "actix")
// ============================================================================

#[cfg(feature = "actix")]
pub mod actix {
    use super::*;
    use actix_web::{error::ResponseError, http::StatusCode, HttpResponse};
    use std::fmt;

    /// Actix-web compatible error type
    impl ResponseError for UuidError {
        fn status_code(&self) -> StatusCode {
            match self {
                UuidError::InvalidFormat { .. } => StatusCode::BAD_REQUEST,
                UuidError::MissingField { .. } => StatusCode::BAD_REQUEST,
            }
        }

        fn error_response(&self) -> HttpResponse {
            HttpResponse::build(self.status_code()).json(serde_json::json!({
                "error": "invalid_uuid",
                "message": self.to_string(),
            }))
        }
    }

    /// Parse UUID from actix-web path parameter
    ///
    /// # Examples
    ///
    /// ```rust,ignore
    /// use actix_web::{web, HttpResponse};
    /// use uuid_utils::actix::parse_path_uuid;
    ///
    /// async fn get_user(path: web::Path<String>) -> Result<HttpResponse, UuidError> {
    ///     let user_id = parse_path_uuid(&path, "user_id")?;
    ///     Ok(HttpResponse::Ok().json(user_id))
    /// }
    /// ```
    pub fn parse_path_uuid(path: &str, field: &str) -> Result<uuid::Uuid, UuidError> {
        parse_uuid(path, field)
    }
}

// ============================================================================
// gRPC/Tonic Integration (feature = "grpc")
// ============================================================================

#[cfg(feature = "grpc")]
pub mod grpc {
    use super::*;
    use tonic::Status;

    /// Convert UuidError to tonic::Status
    impl From<UuidError> for Status {
        fn from(err: UuidError) -> Self {
            match err {
                UuidError::InvalidFormat { field, details } => {
                    Status::invalid_argument(format!("Invalid UUID for {}: {}", field, details))
                }
                UuidError::MissingField { field } => {
                    Status::invalid_argument(format!("Missing required field: {}", field))
                }
            }
        }
    }

    /// Parse UUID for gRPC request field
    ///
    /// # Examples
    ///
    /// ```rust,ignore
    /// use uuid_utils::grpc::parse_grpc_uuid;
    /// use tonic::{Request, Response, Status};
    ///
    /// async fn get_user(request: Request<GetUserRequest>) -> Result<Response<User>, Status> {
    ///     let user_id = parse_grpc_uuid(&request.get_ref().user_id, "user_id")?;
    ///     // ... fetch user ...
    /// }
    /// ```
    pub fn parse_grpc_uuid(input: &str, field: &str) -> Result<uuid::Uuid, Status> {
        parse_uuid(input, field).map_err(Status::from)
    }
}

// ============================================================================
// Validation Helpers
// ============================================================================

/// Validate UUID string format without parsing
pub fn is_valid_uuid(input: &str) -> bool {
    Uuid::parse_str(input).is_ok()
}

/// Generate a new random UUID (v4)
pub fn new_uuid() -> Uuid {
    Uuid::new_v4()
}

/// Convert UUID to lowercase hyphenated string (canonical form)
pub fn to_canonical_string(uuid: &Uuid) -> String {
    uuid.to_string().to_lowercase()
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_UUID: &str = "550e8400-e29b-41d4-a716-446655440000";
    const INVALID_UUID: &str = "not-a-uuid";

    #[test]
    fn test_parse_uuid_success() {
        let uuid = parse_uuid(VALID_UUID, "test_id").unwrap();
        assert_eq!(uuid.to_string(), VALID_UUID);
    }

    #[test]
    fn test_parse_uuid_failure() {
        let err = parse_uuid(INVALID_UUID, "video_id").unwrap_err();
        assert!(matches!(err, UuidError::InvalidFormat { .. }));
        assert!(err.to_string().contains("video_id"));
    }

    #[test]
    fn test_parse_uuid_opt_empty() {
        let result = parse_uuid_opt("", "optional_id").unwrap();
        assert_eq!(result, None);
    }

    #[test]
    fn test_parse_uuid_opt_valid() {
        let result = parse_uuid_opt(VALID_UUID, "optional_id").unwrap();
        assert!(result.is_some());
    }

    #[test]
    fn test_parse_uuid_vec() {
        let ids = vec![VALID_UUID.to_string()];
        let uuids = parse_uuid_vec(&ids, "user_ids").unwrap();
        assert_eq!(uuids.len(), 1);
    }

    #[test]
    fn test_parse_uuid_vec_with_invalid() {
        let ids = vec![VALID_UUID.to_string(), INVALID_UUID.to_string()];
        let err = parse_uuid_vec(&ids, "user_ids").unwrap_err();
        assert!(err.to_string().contains("user_ids[1]"));
    }

    #[test]
    fn test_is_valid_uuid() {
        assert!(is_valid_uuid(VALID_UUID));
        assert!(!is_valid_uuid(INVALID_UUID));
    }

    #[test]
    fn test_new_uuid() {
        let uuid1 = new_uuid();
        let uuid2 = new_uuid();
        assert_ne!(uuid1, uuid2);
    }

    #[test]
    fn test_to_canonical_string() {
        let uuid = Uuid::parse_str(VALID_UUID).unwrap();
        let canonical = to_canonical_string(&uuid);
        assert_eq!(canonical, VALID_UUID);
        assert!(!canonical.contains(char::is_uppercase));
    }
}
