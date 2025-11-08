//! gRPC Authentication Interceptor
//!
//! This interceptor validates JWT tokens in all gRPC requests and enforces
//! authentication across Nova microservices.
//!
//! # Design
//! - Validates RS256 JWT tokens from Authorization metadata
//! - Supports public method whitelist (e.g., health checks)
//! - Injects authenticated user_id into request extensions
//! - Provides audit trail via correlation-id

use tonic::{service::Interceptor, Code, Request, Status};
use crate::jwt::{validate_token, TokenData};
use crate::correlation;
use tracing::{debug, warn};

/// gRPC authentication interceptor
///
/// Validates JWT tokens and ensures only authenticated requests proceed.
/// Public methods (like health checks) can be whitelisted.
#[derive(Clone)]
pub struct GrpcAuthInterceptor {
    /// Methods that do not require authentication
    public_methods: Vec<&'static str>,
}

impl GrpcAuthInterceptor {
    /// Create a new auth interceptor with default public method whitelist
    pub fn new() -> Self {
        Self {
            public_methods: vec![
                "/grpc.health.v1.Health/Check",
                "/grpc.health.v1.Health/Watch",
            ],
        }
    }

    /// Add a public method that doesn't require authentication
    pub fn with_public_method(mut self, method: &'static str) -> Self {
        self.public_methods.push(method);
        self
    }

    /// Check if method is in public whitelist
    fn is_public_method(&self, uri: &str) -> bool {
        self.public_methods.iter().any(|&m| m == uri)
    }

    /// Extract and validate JWT token from Authorization header
    fn extract_and_validate_token(&self, req: &Request<()>) -> Result<TokenData, Status> {
        let auth_header = req
            .metadata()
            .get("authorization")
            .ok_or_else(|| {
                debug!("Missing authorization header");
                Status::new(Code::Unauthenticated, "Missing authorization header")
            })?
            .to_str()
            .map_err(|_| {
                warn!("Invalid authorization header encoding");
                Status::new(Code::Unauthenticated, "Invalid authorization header")
            })?;

        // Extract bearer token (format: "Bearer <token>")
        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or_else(|| {
                debug!("Invalid authorization scheme");
                Status::new(Code::Unauthenticated, "Invalid authorization scheme")
            })?;

        // Validate JWT signature and claims
        validate_token(token).map_err(|err| {
            warn!("JWT validation failed: {}", err);
            Status::new(Code::Unauthenticated, "Invalid or expired token")
        })
    }
}

impl Default for GrpcAuthInterceptor {
    fn default() -> Self {
        Self::new()
    }
}

impl Interceptor for GrpcAuthInterceptor {
    fn call(&mut self, mut req: Request<()>) -> Result<Request<()>, Status> {
        let method = req.uri().path();

        // Public methods bypass authentication
        if self.is_public_method(method) {
            debug!(method = %method, "Allowing public gRPC method");
            return Ok(req);
        }

        // Validate JWT and extract claims
        let token_data = self.extract_and_validate_token(&req)?;

        // Extract correlation-id for distributed tracing
        let correlation_id = req
            .metadata()
            .get("correlation-id")
            .and_then(|v| v.to_str().ok())
            .map(String::from)
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

        // Inject user_id and correlation-id into extensions for handlers
        req.extensions_mut()
            .insert(AuthenticatedUser {
                user_id: token_data.claims.sub,
                correlation_id,
            });

        debug!(
            method = %method,
            user_id = %token_data.claims.sub,
            "gRPC request authenticated"
        );

        Ok(req)
    }
}

/// Authenticated user context available in request extensions
#[derive(Debug, Clone)]
pub struct AuthenticatedUser {
    /// UUID of authenticated user
    pub user_id: uuid::Uuid,
    /// Correlation ID for distributed tracing
    pub correlation_id: String,
}

impl AuthenticatedUser {
    /// Extract authenticated user from request extensions
    pub fn from_request(req: &Request<()>) -> Option<Self> {
        req.extensions().get::<AuthenticatedUser>().cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_methods_bypass_auth() {
        let interceptor = GrpcAuthInterceptor::new();
        assert!(interceptor.is_public_method("/grpc.health.v1.Health/Check"));
        assert!(!interceptor.is_public_method("/nova.user.UserService/GetUser"));
    }

    #[test]
    fn can_add_custom_public_method() {
        let interceptor = GrpcAuthInterceptor::new()
            .with_public_method("/nova.auth.AuthService/Login");
        assert!(interceptor.is_public_method("/nova.auth.AuthService/Login"));
    }
}
