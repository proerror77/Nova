/// Identity Service Library
///
/// Provides authentication, authorization, and identity management for Nova backend.
///
/// ## Modules
///
/// - `config`: Service configuration
/// - `db`: Database repositories (users, sessions, oauth)
/// - `domain`: Domain aggregates and events
/// - `error`: Error types
/// - `grpc`: gRPC server implementation
/// - `models`: Data models
/// - `security`: JWT, password hashing, TOTP, token revocation
/// - `services`: Business logic (email, kafka, oauth, 2FA)
/// - `validators`: Input validation
pub mod config;
pub mod db;
pub mod domain;
pub mod error;
pub mod grpc;
pub mod models;
pub mod security;
pub mod services;
pub mod validators;

// Re-export commonly used types
pub use error::{IdentityError, Result};
pub use grpc::IdentityServiceServer;
