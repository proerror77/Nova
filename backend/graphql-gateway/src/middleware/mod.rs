//! GraphQL Gateway Middleware

pub mod jwt;
pub mod auth;
pub mod rate_limit;

// Re-export JWT middleware and AuthenticatedUser type
pub use jwt::{JwtMiddleware, AuthenticatedUser};

// Re-export auth functions
pub use auth::{check_user_authorization, require_auth, get_authenticated_user_id, get_authenticated_claims};

// Re-export rate limiting
pub use rate_limit::{RateLimitMiddleware, RateLimitConfig};

// Re-export Claims from crypto_core for convenience
pub use crypto_core::jwt::Claims;
