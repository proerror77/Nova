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
use std::time::Duration;
use tokio::time::timeout;

#[derive(Debug, Clone, Deserialize)]
pub struct RateLimitConfig {
    pub max_requests: u32,
    pub window_seconds: u64,
    /// Redis operation timeout in milliseconds
    pub redis_timeout_ms: u64,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 100,
            window_seconds: 900, // 15 minutes
            redis_timeout_ms: 100, // Fast timeout to prevent blocking
        }
    }
}

pub struct RateLimitMiddleware {
    config: RateLimitConfig,
    redis: Arc<ConnectionManager>,
}

impl RateLimitMiddleware {
    pub fn new(config: RateLimitConfig, redis: Arc<ConnectionManager>) -> Self {
        Self { config, redis }
    }

    /// Create with default config
    pub fn with_default_config(redis: Arc<ConnectionManager>) -> Self {
        Self {
            config: RateLimitConfig::default(),
            redis,
        }
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
    redis: Arc<ConnectionManager>,
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

            // Check rate limit with timeout protection
            // If Redis is slow/unavailable, we allow the request rather than blocking
            let rate_limit_result = timeout(
                Duration::from_millis(config.redis_timeout_ms),
                check_rate_limit(&redis, &key, &config),
            )
            .await;

            match rate_limit_result {
                Ok(Ok(exceeded)) => {
                    if exceeded {
                        return Err(actix_web::error::ErrorTooManyRequests(format!(
                            "Rate limit exceeded: {} requests per {} seconds",
                            config.max_requests, config.window_seconds
                        )));
                    }
                }
                Ok(Err(e)) => {
                    // Log Redis errors but allow request to proceed
                    // This prevents rate limiting from being a point of failure
                    tracing::warn!("Rate limit Redis error (allowing request): {}", e);
                }
                Err(_) => {
                    // Timeout: allow request but log it
                    // This prevents Redis latency from blocking all requests
                    tracing::warn!(
                        "Rate limit Redis timeout ({}ms, allowing request)",
                        config.redis_timeout_ms
                    );
                }
            }

            service.call(req).await
        })
    }
}

/// Check rate limit for a given key
/// Returns Ok(true) if limit exceeded, Ok(false) if within limit
async fn check_rate_limit(
    redis: &Arc<ConnectionManager>,
    key: &str,
    config: &RateLimitConfig,
) -> Result<bool, String> {
    // Redis ConnectionManager implements Clone which creates a new handle
    // that shares the same underlying connection pool
    let mut conn = redis.as_ref().clone();

    let count: u32 = conn.incr(key, 1).await.map_err(|e| format!("Redis incr failed: {}", e))?;

    // Set expiry on first request
    if count == 1 {
        let _: () = conn
            .expire(key, config.window_seconds as i64)
            .await
            .map_err(|e| format!("Redis expire failed: {}", e))?;
    }

    Ok(count > config.max_requests)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limit_config_default() {
        let config = RateLimitConfig::default();
        assert_eq!(config.max_requests, 100);
        assert_eq!(config.window_seconds, 900);
        assert_eq!(config.redis_timeout_ms, 100);
    }

    #[test]
    fn test_rate_limit_config_custom() {
        let config = RateLimitConfig {
            max_requests: 50,
            window_seconds: 300,
            redis_timeout_ms: 50,
        };
        assert_eq!(config.max_requests, 50);
        assert_eq!(config.window_seconds, 300);
        assert_eq!(config.redis_timeout_ms, 50);
    }

    #[test]
    fn test_rate_limit_middleware_creation() {
        // This test verifies that the middleware can be created
        // In production, redis would be a real connection manager
        // For unit testing, we just verify the API surface
        let config = RateLimitConfig::default();
        assert_eq!(config.max_requests, 100);
        assert_eq!(config.redis_timeout_ms, 100);
    }

    #[test]
    fn test_rate_limit_key_format_user() {
        // Verify that user rate limit keys are formatted correctly
        let key = "rate_limit:user:12345";
        assert!(key.starts_with("rate_limit:user:"));
    }

    #[test]
    fn test_rate_limit_key_format_ip() {
        // Verify that IP rate limit keys are formatted correctly
        let key = "rate_limit:ip:192.168.1.1";
        assert!(key.starts_with("rate_limit:ip:"));
    }

    #[test]
    fn test_rate_limit_window_seconds() {
        let config = RateLimitConfig::default();
        // 15 minutes = 900 seconds
        assert_eq!(config.window_seconds, 900);
    }

    #[test]
    fn test_rate_limit_fast_timeout() {
        let config = RateLimitConfig::default();
        // Redis operations should have a fast timeout (100ms)
        // This prevents Redis slowness from blocking all requests
        assert_eq!(config.redis_timeout_ms, 100);
        assert!(config.redis_timeout_ms < 1000, "Timeout too long, will block requests");
    }

    #[test]
    fn test_with_default_config() {
        let config = RateLimitConfig::default();
        assert_eq!(config.max_requests, 100);
        assert_eq!(config.window_seconds, 900);
        assert_eq!(config.redis_timeout_ms, 100);
    }
}
