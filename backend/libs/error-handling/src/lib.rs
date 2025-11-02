//! Unified error handling library for Nova microservices
//!
//! ⚠️  DEPRECATED: This crate now re-exports from `error-types` for backward compatibility.
//! New code should use `error-types` directly.
//!
//! This is maintained for compatibility with existing services.
//! Will be removed in the next major version.

// Re-export main types and modules from error-types for backward compatibility
pub use ::error_types::{error_codes, ErrorResponse, ServiceError};

// Re-export the error_types module with full path to avoid naming conflict
pub mod error_types {
    pub use ::error_types::error_types::*;
}
