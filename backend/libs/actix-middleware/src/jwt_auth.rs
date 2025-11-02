use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::{ready, Ready};
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use uuid::Uuid;

/// User ID extracted from JWT
#[derive(Debug, Clone, Copy)]
pub struct UserId(pub Uuid);

/// JWT Authentication Middleware
pub struct JwtAuthMiddleware;

impl<S, B> Transform<S, ServiceRequest> for JwtAuthMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Transform = JwtAuthMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(JwtAuthMiddlewareService {
            service: Rc::new(service),
        }))
    }
}

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
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>>>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let service = self.service.clone();

        Box::pin(async move {
            // Extract Authorization header
            let auth_header = req
                .headers()
                .get("Authorization")
                .and_then(|h| h.to_str().ok())
                .ok_or_else(|| {
                    actix_web::error::ErrorUnauthorized("Missing Authorization header")
                })?;

            // Extract token
            let token = auth_header.strip_prefix("Bearer ").ok_or_else(|| {
                actix_web::error::ErrorUnauthorized("Invalid Authorization header format")
            })?;

            // Validate token (uses crypto-core)
            let token_data = crypto_core::jwt::validate_token(token).map_err(|e| {
                tracing::warn!("JWT validation failed: {}", e);
                actix_web::error::ErrorUnauthorized(format!("Invalid token: {}", e))
            })?;

            // Extract user_id from claims
            let user_id_str = &token_data.claims.sub;
            let user_id = Uuid::parse_str(user_id_str).map_err(|e| {
                tracing::error!("Invalid user_id UUID in token: {}", e);
                actix_web::error::ErrorUnauthorized("Invalid token: malformed user_id")
            })?;

            // Insert UserId into request extensions
            req.extensions_mut().insert(UserId(user_id));

            service.call(req).await
        })
    }
}

/// FromRequest implementation for UserId
impl actix_web::FromRequest for UserId {
    type Error = actix_web::Error;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(
        req: &actix_web::HttpRequest,
        _payload: &mut actix_web::dev::Payload,
    ) -> Self::Future {
        match req.extensions().get::<UserId>() {
            Some(user_id) => ready(Ok(*user_id)),
            None => ready(Err(actix_web::error::ErrorUnauthorized(
                "User not authenticated",
            ))),
        }
    }
}
