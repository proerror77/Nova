pub mod auth;
pub mod authorization;
pub mod error_handling;
pub mod guards;
pub mod logging;

// Re-export for compatibility
pub use auth::{verify_jwt, Claims};
