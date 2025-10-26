/// JWT Token Revocation Middleware
///
/// CRITICAL FIX: Check if JWT token has been revoked before allowing access
/// This prevents stolen tokens from being used after logout or password change
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::LocalBoxFuture;
use redis::aio::ConnectionManager;
use std::rc::Rc;
use tracing::warn;

/// Middleware that checks JWT token revocation
pub struct TokenRevocationMiddleware {
    redis: Option<Rc<ConnectionManager>>,
}

impl TokenRevocationMiddleware {
    pub fn new(redis: Option<Rc<ConnectionManager>>) -> Self {
        TokenRevocationMiddleware { redis }
    }
}

impl<S, B> Transform<S, ServiceRequest> for TokenRevocationMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = TokenRevocationMiddlewareService<S>;
    type Future = std::future::Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        std::future::ready(Ok(TokenRevocationMiddlewareService {
            service: Rc::new(service),
            redis: self.redis.clone(),
        }))
    }
}

pub struct TokenRevocationMiddlewareService<S> {
    service: Rc<S>,
    redis: Option<Rc<ConnectionManager>>,
}

impl<S, B> Service<ServiceRequest> for TokenRevocationMiddlewareService<S>
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
        let redis = self.redis.clone();

        Box::pin(async move {
            // Extract token from Authorization header
            if let Some(auth_header) = req.headers().get("Authorization") {
                if let Ok(header_value) = auth_header.to_str() {
                    if let Some(token) = header_value.strip_prefix("Bearer ") {
                        // Check token revocation if Redis is available
                        if let Some(redis_mgr) = redis {
                            match crate::security::token_revocation::is_token_revoked(
                                redis_mgr.as_ref(),
                                token,
                            )
                            .await
                            {
                                Ok(true) => {
                                    // Token is revoked, deny access
                                    warn!("Attempt to use revoked token");
                                    return Err(actix_web::error::ErrorUnauthorized(
                                        "Token has been revoked",
                                    ));
                                }
                                Ok(false) => {
                                    // Token is valid, continue to next middleware
                                }
                                Err(e) => {
                                    // Redis error, log but continue (fail open)
                                    tracing::error!("Token revocation check failed: {}", e);
                                }
                            }
                        }
                    }
                }
            }

            // Call the wrapped service
            service.call(req).await
        })
    }
}
