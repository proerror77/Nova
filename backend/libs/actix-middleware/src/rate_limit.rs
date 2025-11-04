use actix_web::{
    dev::{Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::{ready, Ready};
use redis::{aio::ConnectionManager, AsyncCommands};
use serde::Deserialize;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Clone, Deserialize)]
pub struct RateLimitConfig {
    pub max_requests: u32,
    pub window_seconds: u64,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 100,
            window_seconds: 900, // 15 minutes
        }
    }
}

pub struct RateLimitMiddleware {
    config: RateLimitConfig,
    redis: Arc<Mutex<ConnectionManager>>,
}

impl RateLimitMiddleware {
    pub fn new(config: RateLimitConfig, redis: Arc<Mutex<ConnectionManager>>) -> Self {
        Self { config, redis }
    }
}

impl<S, B> Transform<S, ServiceRequest> for RateLimitMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Transform = RateLimitMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(RateLimitMiddlewareService {
            service: Rc::new(service),
            config: self.config.clone(),
            redis: self.redis.clone(),
        }))
    }
}

pub struct RateLimitMiddlewareService<S> {
    service: Rc<S>,
    config: RateLimitConfig,
    redis: Arc<Mutex<ConnectionManager>>,
}

impl<S, B> Service<ServiceRequest> for RateLimitMiddlewareService<S>
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
        let config = self.config.clone();
        let redis = self.redis.clone();

        Box::pin(async move {
            // Get rate limit key (user_id or IP)
            let key = if let Some(user_id) = req.extensions().get::<crate::jwt_auth::UserId>() {
                format!("rate_limit:user:{}", user_id.0)
            } else {
                let ip = req
                    .connection_info()
                    .realip_remote_addr()
                    .unwrap_or("unknown")
                    .to_string();
                format!("rate_limit:ip:{}", ip)
            };

            // Check rate limit
            let mut conn = redis.lock().await;
            let count: u32 = conn.incr(&key, 1).await.map_err(|e| {
                tracing::error!("Redis incr failed: {}", e);
                actix_web::error::ErrorInternalServerError("Rate limit check failed")
            })?;

            // Set expiry on first request
            if count == 1 {
                let _: () = conn
                    .expire(&key, config.window_seconds as i64)
                    .await
                    .map_err(|e| {
                        tracing::error!("Redis expire failed: {}", e);
                        actix_web::error::ErrorInternalServerError("Rate limit setup failed")
                    })?;
            }

            // Check if limit exceeded
            if count > config.max_requests {
                return Err(actix_web::error::ErrorTooManyRequests(format!(
                    "Rate limit exceeded: {} requests per {} seconds",
                    config.max_requests, config.window_seconds
                )));
            }

            drop(conn);
            service.call(req).await
        })
    }
}
