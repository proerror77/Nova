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
