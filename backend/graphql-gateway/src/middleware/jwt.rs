//! JWT authentication middleware for GraphQL Gateway
//!
//! SECURITY NOTE: This middleware uses crypto-core::jwt for RS256 validation.
//! DO NOT implement custom JWT logic - always use the shared crypto-core library
//! to prevent algorithm confusion attacks and other JWT vulnerabilities.

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use crypto_core::jwt::validate_token;
use futures_util::future::LocalBoxFuture;
use std::future::{ready, Ready};
use uuid::Uuid;

/// Strongly-typed authenticated user ID extracted from JWT
/// This newtype prevents accidental misuse and ensures type safety
#[derive(Debug, Clone, Copy)]
pub struct AuthenticatedUser(pub Uuid);

/// Check if a path is a public poll endpoint (GET only)
/// Matches: /api/v2/polls/{uuid} or /api/v2/polls/{uuid}/rankings
fn is_public_poll_endpoint(path: &str) -> bool {
    if !path.starts_with("/api/v2/polls/") {
        return false;
    }

    let remaining = &path["/api/v2/polls/".len()..];
    let parts: Vec<&str> = remaining.split('/').collect();

    match parts.as_slice() {
        // /api/v2/polls/{poll_id} - single poll details
        [poll_id] if Uuid::parse_str(poll_id).is_ok() => true,
        // /api/v2/polls/{poll_id}/rankings - poll rankings
        [poll_id, "rankings"] if Uuid::parse_str(poll_id).is_ok() => true,
        _ => false,
    }
}

/// JWT authentication middleware
///
/// Uses crypto-core::jwt for RS256 validation. All JWT operations
/// MUST go through crypto-core to maintain security consistency.
pub struct JwtMiddleware;

impl JwtMiddleware {
    pub fn new() -> Self {
        Self
    }
}

impl Default for JwtMiddleware {
    fn default() -> Self {
        Self::new()
    }
}

impl<S, B> Transform<S, ServiceRequest> for JwtMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = JwtMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(JwtMiddlewareService { service }))
    }
}

pub struct JwtMiddlewareService<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for JwtMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let start = std::time::Instant::now();
        let method = req.method().to_string();
        let path = req.path().to_string();

        // Skip auth for health check, metrics, and selected public endpoints
        let public_prefixes = [
            "/health",
            "/health/circuit-breakers",
            "/metrics",
            "/api/v2/auth/register",
            "/api/v2/auth/login",
            "/api/v2/auth/refresh",
            // Guest feed (unauthenticated trending feed for mobile clients)
            "/api/v2/guest/feed/trending",
            // Invite code validation (pre-registration check, no auth required)
            "/api/v2/auth/invites/validate",
            // Phone authentication (SMS OTP - public endpoints for registration/login)
            "/api/v2/auth/phone",
            // Comments API (public read access for viewing comments)
            "/api/v2/social/comments",
            // Alice AI Assistant API (public access for chat and voice)
            "/api/v2/alice",
            // Polls API (public read access for trending polls and rankings)
            "/api/v2/polls/trending",
            "/api/v2/polls/active",
        ];

        if public_prefixes.iter().any(|p| path.starts_with(p)) {
            let fut = self.service.call(req);
            return Box::pin(async move {
                let res = fut.await?;
                Ok(res)
            });
        }

        // Check for public polls endpoints with dynamic poll_id (GET only)
        // Pattern: /api/v2/polls/{poll_id} or /api/v2/polls/{poll_id}/rankings
        if method == "GET" && is_public_poll_endpoint(&path) {
            let fut = self.service.call(req);
            return Box::pin(async move {
                let res = fut.await?;
                Ok(res)
            });
        }

        // Extract Authorization header
        let auth_header = req.headers().get("Authorization");

        if auth_header.is_none() {
            tracing::warn!(
                method = %method,
                path = %path,
                error = "missing_header",
                error_type = "authentication_error",
                elapsed_ms = start.elapsed().as_millis() as u32,
                "JWT authentication failed: Missing Authorization header"
            );
            return Box::pin(async move {
                Err(actix_web::error::ErrorUnauthorized(
                    "Missing Authorization header",
                ))
            });
        }

        let auth_str = match auth_header.and_then(|h| h.to_str().ok()) {
            Some(s) => s,
            None => {
                tracing::warn!(
                    method = %method,
                    path = %path,
                    error = "invalid_header_encoding",
                    error_type = "authentication_error",
                    elapsed_ms = start.elapsed().as_millis() as u32,
                    "JWT authentication failed: Invalid Authorization header encoding"
                );
                return Box::pin(async move {
                    Err(actix_web::error::ErrorUnauthorized(
                        "Invalid Authorization header",
                    ))
                });
            }
        };

        // Check for Bearer token
        if !auth_str.starts_with("Bearer ") {
            tracing::warn!(
                method = %method,
                path = %path,
                error = "invalid_scheme",
                error_type = "authentication_error",
                elapsed_ms = start.elapsed().as_millis() as u32,
                "JWT authentication failed: Missing Bearer scheme"
            );
            return Box::pin(async move {
                Err(actix_web::error::ErrorUnauthorized(
                    "Authorization must use Bearer scheme",
                ))
            });
        }

        let token = &auth_str[7..]; // Remove "Bearer " prefix

        // Validate JWT using crypto-core (RS256 only)
        let token_data = match validate_token(token) {
            Ok(data) => data,
            Err(e) => {
                tracing::error!(
                    method = %method,
                    path = %path,
                    error = %e,
                    error_type = "authentication_error",
                    elapsed_ms = start.elapsed().as_millis() as u32,
                    "JWT authentication failed: Invalid token"
                );
                return Box::pin(async move {
                    // Don't expose internal error details to clients
                    Err(actix_web::error::ErrorUnauthorized(
                        "Invalid or expired token",
                    ))
                });
            }
        };

        // Parse user ID as UUID for type safety
        let user_id = match Uuid::parse_str(&token_data.claims.sub) {
            Ok(uuid) => uuid,
            Err(e) => {
                tracing::error!(
                    method = %method,
                    path = %path,
                    error = %e,
                    sub = %token_data.claims.sub,
                    error_type = "authentication_error",
                    elapsed_ms = start.elapsed().as_millis() as u32,
                    "JWT authentication failed: Invalid user ID format"
                );
                return Box::pin(async move {
                    Err(actix_web::error::ErrorUnauthorized("Invalid token format"))
                });
            }
        };

        // Log successful authentication (no PII in message, structured in fields)
        tracing::info!(
            user_id = %user_id,
            method = %method,
            path = %path,
            elapsed_ms = start.elapsed().as_millis() as u32,
            "JWT authentication successful"
        );

        // Store strongly-typed user in request extensions
        req.extensions_mut().insert(AuthenticatedUser(user_id));
        req.extensions_mut().insert(token_data.claims);

        let fut = self.service.call(req);
        Box::pin(async move {
            let res = fut.await?;
            Ok(res)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, web, App, HttpResponse};

    async fn test_handler() -> actix_web::Result<HttpResponse> {
        Ok(HttpResponse::Ok().body("success"))
    }

    #[actix_web::test]
    async fn test_health_check_bypasses_auth() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new())
                .route("/health", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get().uri("/health").to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 200);
    }

    #[actix_web::test]
    async fn test_missing_authorization_header() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new())
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get().uri("/test").to_request();

        let resp = test::try_call_service(&app, req).await;
        assert!(resp.is_err(), "Missing auth header should be rejected");
    }

    #[actix_web::test]
    async fn test_invalid_bearer_scheme() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new())
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/test")
            .insert_header(("Authorization", "Basic dGVzdDp0ZXN0"))
            .to_request();

        let resp = test::try_call_service(&app, req).await;
        assert!(resp.is_err(), "Non-Bearer scheme should be rejected");
    }

    // Note: Full integration tests with valid RS256 tokens should be in
    // integration test suite with proper key initialization
}
