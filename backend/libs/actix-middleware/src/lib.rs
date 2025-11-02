//! # Actix Middleware Library
//!
//! Unified middleware components for Nova Actix services
//!
//! ## Modules
//! - `jwt_auth`: JWT authentication middleware
//! - `metrics`: Prometheus metrics middleware
//! - `rate_limit`: Redis-backed rate limiting
//! - `circuit_breaker`: Circuit breaker for external services
//! - `token_revocation`: Token revocation check middleware

pub mod circuit_breaker;
pub mod jwt_auth;
pub mod metrics;
pub mod rate_limit;
pub mod token_revocation;

pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig};
pub use jwt_auth::{JwtAuthMiddleware, UserId};
pub use metrics::MetricsMiddleware;
pub use rate_limit::{RateLimitConfig, RateLimitMiddleware};
pub use token_revocation::TokenRevocationMiddleware;
