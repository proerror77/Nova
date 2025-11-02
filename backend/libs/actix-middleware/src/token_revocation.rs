use actix_web::{
    dev::{Service, ServiceRequest, ServiceResponse, Transform},
    Error,
};
use futures::future::{ready, Ready};
use redis::{aio::ConnectionManager, AsyncCommands};
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct TokenRevocationMiddleware {
    redis: Arc<Mutex<ConnectionManager>>,
}

impl TokenRevocationMiddleware {
    pub fn new(redis: Arc<Mutex<ConnectionManager>>) -> Self {
        Self { redis }
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
    type Transform = TokenRevocationMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(TokenRevocationMiddlewareService {
            service: Rc::new(service),
            redis: self.redis.clone(),
        }))
    }
}

pub struct TokenRevocationMiddlewareService<S> {
    service: Rc<S>,
    redis: Arc<Mutex<ConnectionManager>>,
}

impl<S, B> Service<ServiceRequest> for TokenRevocationMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>>>>;

    actix_web::dev::forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let service = self.service.clone();
        let redis = self.redis.clone();

        Box::pin(async move {
            // Extract token from Authorization header
            let token = req
                .headers()
                .get("Authorization")
                .and_then(|h| h.to_str().ok())
                .and_then(|s| s.strip_prefix("Bearer "))
                .ok_or_else(|| {
                    actix_web::error::ErrorUnauthorized("Missing or invalid Authorization header")
                })?;

            // Compute token hash
            let token_hash = crypto_core::hash::sha256(token.as_bytes());

            // Check if token is revoked
            let revocation_key = format!("revoked_token:{}", hex::encode(&token_hash));
            let mut conn = redis.lock().await;
            let is_revoked: bool = conn.exists(&revocation_key).await.map_err(|e| {
                tracing::error!("Redis check failed: {}", e);
                actix_web::error::ErrorInternalServerError("Token revocation check failed")
            })?;

            if is_revoked {
                return Err(actix_web::error::ErrorUnauthorized("Token has been revoked"));
            }

            drop(conn);
            service.call(req).await
        })
    }
}
