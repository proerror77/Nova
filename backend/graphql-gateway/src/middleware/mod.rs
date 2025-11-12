//! GraphQL Gateway Middleware

pub mod auth;
pub mod jwt;
pub mod persisted_queries;
pub mod rate_limit;

// Re-export JWT middleware and AuthenticatedUser type
pub use jwt::JwtMiddleware;

// Re-export auth functions
pub use auth::{check_user_authorization, get_authenticated_user_id};

// Re-export rate limiting
pub use rate_limit::{RateLimitConfig, RateLimitMiddleware};

// Re-export persisted queries middleware

// Re-export Claims from crypto_core for convenience
