pub mod circuit_breaker;
pub mod jwt_auth;
pub mod metrics;
/// Middleware implementations
pub mod rate_limit;

// Middleware modules:
// - rate_limit: IP-based rate limiting for authentication endpoints
// - jwt_auth: JWT Bearer token validation and user_id extraction
// - metrics: Prometheus metrics collection for all requests
// - circuit_breaker: Circuit breaker pattern for fault tolerance
// - Request logging: handled by actix_web::middleware::Logger
// - CORS: handled by actix_cors::Cors

pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};
pub use jwt_auth::{JwtAuthMiddleware, UserId};
pub use metrics::MetricsMiddleware;
