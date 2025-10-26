pub mod circuit_breaker;
pub mod global_rate_limit;
pub mod jwt_auth;
pub mod metrics;
/// Middleware implementations
pub mod rate_limit;
pub mod token_revocation;

// Middleware modules:
// - rate_limit: IP-based rate limiting for authentication endpoints
// - jwt_auth: JWT Bearer token validation and user_id extraction
// - metrics: Prometheus metrics collection for all requests
// - circuit_breaker: Circuit breaker pattern for fault tolerance
// - token_revocation: Check if JWT token has been revoked (logout/password change)
// - Request logging: handled by actix_web::middleware::Logger
// - CORS: handled by actix_cors::Cors

pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};
pub use global_rate_limit::GlobalRateLimitMiddleware;
pub use jwt_auth::{JwtAuthMiddleware, UserId};
pub use metrics::MetricsMiddleware;
pub use rate_limit::RateLimiter;
pub use token_revocation::{TokenRevocationMiddleware, TokenRevocationMiddlewareService};
