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
//! - `correlation_id`: Request correlation ID middleware for distributed tracing
//! - `request_id`: Request ID middleware for tracking HTTP requests
//! - `logging`: HTTP request/response logging middleware

pub mod circuit_breaker;
pub mod correlation_id;
pub mod jwt_auth;
pub mod logging;
pub mod metrics;
pub mod rate_limit;
pub mod request_id;
pub mod token_revocation;

pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig};
pub use correlation_id::{get_correlation_id, CorrelationIdMiddleware};
pub use jwt_auth::{JwtAuthMiddleware, UserId};
pub use logging::Logging;
pub use metrics::MetricsMiddleware;
pub use rate_limit::{FailureMode, RateLimitConfig, RateLimitMiddleware};
pub use request_id::RequestId;
pub use token_revocation::TokenRevocationMiddleware;
