/// HTTP middleware utilities for media-service
use actix_web::dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform};
use actix_web::{error::ErrorUnauthorized, Error, FromRequest, HttpMessage, HttpRequest};
use crypto_core::jwt;
use futures::future::{ready, LocalBoxFuture, Ready};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Instant;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct UserId(pub Uuid);

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
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, mut req: ServiceRequest) -> Self::Future {
        let service = self.service.clone();

        Box::pin(async move {
            let auth_header = req
                .headers()
                .get("Authorization")
                .and_then(|h| h.to_str().ok())
                .ok_or_else(|| ErrorUnauthorized("Missing Authorization header"))?;

            let token = auth_header
                .strip_prefix("Bearer ")
                .ok_or_else(|| ErrorUnauthorized("Invalid Authorization scheme"))?;

            let claims = jwt::validate_token(token)
                .map_err(|_| ErrorUnauthorized("Invalid or expired token"))?;

            let user_id = Uuid::parse_str(&claims.claims.sub)
                .map_err(|_| ErrorUnauthorized("Invalid user ID"))?;

            req.extensions_mut().insert(UserId(user_id));

            service.call(req).await
        })
    }
}

impl FromRequest for UserId {
    type Error = Error;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _: &mut actix_web::dev::Payload) -> Self::Future {
        ready(
            req.extensions()
                .get::<UserId>()
                .cloned()
                .ok_or_else(|| ErrorUnauthorized("User ID missing")),
        )
    }
}

#[derive(Clone, Debug)]
pub struct RateLimitConfig {
    pub max_requests: u32,
    pub window_seconds: u64,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 5,
            window_seconds: 900,
        }
    }
}

pub struct RateLimiter {
    redis: ConnectionManager,
    config: RateLimitConfig,
}

impl RateLimiter {
    pub fn new(redis: ConnectionManager, config: RateLimitConfig) -> Self {
        Self { redis, config }
    }

    pub async fn is_rate_limited(&self, client_id: &str) -> Result<bool, redis::RedisError> {
        let mut conn = self.redis.clone();
        let key = format!("rate_limit:{}", client_id);
        let current: u32 = conn.get(&key).await.unwrap_or(0);

        if current >= self.config.max_requests {
            return Ok(true);
        }

        let _: () = conn
            .set_ex(&key, current + 1, self.config.window_seconds)
            .await?;
        Ok(false)
    }
}

#[derive(Clone)]
pub struct GlobalRateLimitMiddleware {
    rate_limiter: Arc<RateLimiter>,
}

impl GlobalRateLimitMiddleware {
    pub fn new(rate_limiter: RateLimiter) -> Self {
        Self {
            rate_limiter: Arc::new(rate_limiter),
        }
    }
}

impl<S, B> Transform<S, ServiceRequest> for GlobalRateLimitMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = GlobalRateLimitMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(GlobalRateLimitMiddlewareService {
            service: Rc::new(service),
            rate_limiter: self.rate_limiter.clone(),
        }))
    }
}

pub struct GlobalRateLimitMiddlewareService<S> {
    service: Rc<S>,
    rate_limiter: Arc<RateLimiter>,
}

impl<S, B> Service<ServiceRequest> for GlobalRateLimitMiddlewareService<S>
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
        let client_id = req
            .extensions()
            .get::<UserId>()
            .map(|id| format!("user:{}", id.0))
            .unwrap_or_else(|| {
                req.connection_info()
                    .realip_remote_addr()
                    .map(|ip| format!("ip:{}", ip))
                    .unwrap_or_else(|| "ip:unknown".to_string())
            });

        let service = self.service.clone();
        let limiter = self.rate_limiter.clone();

        Box::pin(async move {
            match limiter.is_rate_limited(&client_id).await {
                Ok(true) => Err(ErrorUnauthorized("Too many requests")),
                Ok(false) => service.call(req).await,
                Err(err) => {
                    tracing::warn!("Rate limiter unavailable: {}", err);
                    service.call(req).await
                }
            }
        })
    }
}

pub struct MetricsMiddleware;

impl<S, B> Transform<S, ServiceRequest> for MetricsMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = MetricsMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(MetricsMiddlewareService {
            service: Rc::new(service),
        }))
    }
}

pub struct MetricsMiddlewareService<S> {
    service: Rc<S>,
}

impl<S, B> Service<ServiceRequest> for MetricsMiddlewareService<S>
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
        let path = req.path().to_string();
        let method = req.method().to_string();
        let start = Instant::now();

        Box::pin(async move {
            let res = service.call(req).await;
            let elapsed = start.elapsed().as_millis();
            tracing::debug!(%method, %path, %elapsed, "request completed");
            res
        })
    }
}
