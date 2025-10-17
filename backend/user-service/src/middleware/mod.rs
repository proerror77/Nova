/// Middleware implementations
pub mod rate_limit;
pub mod jwt_auth;

// Middleware modules:
// - rate_limit: IP-based rate limiting for authentication endpoints
// - jwt_auth: JWT Bearer token validation and user_id extraction
// - Request logging: handled by actix_web::middleware::Logger
// - CORS: handled by actix_cors::Cors

pub use jwt_auth::{JwtAuthMiddleware, UserId};
