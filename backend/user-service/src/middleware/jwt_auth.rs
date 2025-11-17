/// JWT authentication middleware for Bearer token validation
/// Extracts user_id from JWT claims and adds it to request extensions
use actix_web::{
    dev::{forward_ready, Payload, Service, ServiceRequest, ServiceResponse, Transform},
    error::ErrorUnauthorized,
    Error, FromRequest, HttpMessage, HttpRequest,
};
use futures::future::{ready, LocalBoxFuture, Ready};
use std::rc::Rc;
use uuid::Uuid;

use crate::security::jwt;

/// User ID extracted from JWT token
#[derive(Debug, Clone)]
pub struct UserId(pub Uuid);

/// JWT authentication middleware factory
pub struct JwtAuthMiddleware;

impl<S, B> Transform<S, ServiceRequest> for JwtAuthMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = JwtAuthMiddlewareService<S>;
    type Future = std::future::Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        std::future::ready(Ok(JwtAuthMiddlewareService {
            service: Rc::new(service),
        }))
    }
}

/// JWT authentication middleware service
pub struct JwtAuthMiddlewareService<S> {
    service: Rc<S>,
}

impl<S, B> Service<ServiceRequest> for JwtAuthMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let service = self.service.clone();

        Box::pin(async move {
            // CRITICAL FIX for actix-web 4.11.0 BorrowMutError:
            // Extract all immutable data (headers) FIRST, before ANY mutable access (extensions_mut)
            // This ensures no RefCell borrows are active when we call extensions_mut()

            // Extract Authorization header (creates immutable borrow)
            let auth_header = match req.headers().get("Authorization") {
                Some(header) => match header.to_str() {
                    Ok(h) => h.to_string(), // Clone to owned String to drop borrow
                    Err(_) => {
                        return Err(ErrorUnauthorized("Invalid Authorization header"));
                    }
                },
                None => {
                    return Err(ErrorUnauthorized("Missing Authorization header"));
                }
            };

            // Extract Bearer token (works on owned String, no borrow)
            let token = match auth_header.strip_prefix("Bearer ") {
                Some(t) => t,
                None => {
                    return Err(ErrorUnauthorized(
                        "Invalid Authorization scheme, expected Bearer",
                    ));
                }
            };

            // Validate token and extract user_id (no req access)
            let user_id = match jwt::validate_token(token) {
                Ok(token_data) => match Uuid::parse_str(&token_data.claims.sub) {
                    Ok(id) => id,
                    Err(_) => {
                        return Err(ErrorUnauthorized("Invalid user ID in token"));
                    }
                },
                Err(e) => {
                    tracing::debug!("Token validation failed: {}", e);
                    return Err(ErrorUnauthorized("Invalid or expired token"));
                }
            };

            // Now safe to mutably borrow - all prior immutable borrows are dropped
            req.extensions_mut().insert(UserId(user_id));

            // Continue to next middleware/handler
            let res = service.call(req).await?;
            Ok(res)
        })
    }
}

impl FromRequest for UserId {
    type Error = Error;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _: &mut Payload) -> Self::Future {
        match req.extensions().get::<UserId>().cloned() {
            Some(user_id) => ready(Ok(user_id)),
            None => ready(Err(ErrorUnauthorized(
                "User ID missing in request extensions",
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_id_creation() {
        let id = Uuid::new_v4();
        let user_id = UserId(id);
        assert_eq!(user_id.0, id);
    }
}
