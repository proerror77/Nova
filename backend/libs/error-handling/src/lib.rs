//! Unified error handling library for Nova microservices
//!
//! ⚠️  DEPRECATED: This crate now re-exports from `error-types` for backward compatibility.
//! New code should use `error-types` directly.
//!
//! This is maintained for compatibility with existing services.
//! Will be removed in the next major version.

// Re-export everything from error-types
pub use error_types::{ServiceError, ErrorResponse, error_codes, error_types};
