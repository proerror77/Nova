//! Enhanced Rate Limiting Middleware
//!
//! **Security Features**:
//! - Per-user rate limiting (prevents abuse by authenticated users)
//! - Per-IP rate limiting (prevents DDoS from anonymous users)
//! - Per-endpoint rate limiting (protects expensive operations)
//! - Token bucket algorithm (smooth burst handling)
//! - Redis-backed distributed limiting (works across multiple instances)
//! - Graceful degradation (allows requests when Redis unavailable)
//!
//! **CVSS 6.5 Mitigation**: Prevents resource exhaustion and DDoS attacks

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage, HttpResponse,
};
use futures_util::future::LocalBoxFuture;
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use std::collections::HashMap;
use std::future::{ready, Ready};
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use tracing::{error, warn};

/// Rate limit configuration per endpoint
#[derive(Debug, Clone)]
pub struct EndpointLimit {
    /// Requests per second allowed
    pub requests_per_second: u32,
    /// Burst capacity (max tokens in bucket)
    pub burst_capacity: u32,
}

impl Default for EndpointLimit {
    fn default() -> Self {
        Self {
            requests_per_second: 10,
            burst_capacity: 20,
        }
    }
}

/// Enhanced rate limiter configuration
#[derive(Clone)]
pub struct EnhancedRateLimitConfig {
    /// Global per-IP limit (anonymous users)
    pub global_per_ip: EndpointLimit,
    /// Per-user limit (authenticated users)
    pub per_user: EndpointLimit,
    /// Per-endpoint custom limits
    pub endpoint_limits: HashMap<String, EndpointLimit>,
    /// Redis connection for distributed limiting
    pub redis: Option<Arc<RwLock<ConnectionManager>>>,
    /// Fail open when Redis unavailable (security vs availability trade-off)
    pub fail_open: bool,
}

impl EnhancedRateLimitConfig {
    pub fn new() -> Self {
        Self {
            global_per_ip: EndpointLimit {
                requests_per_second: 100,
                burst_capacity: 200,
            },
            per_user: EndpointLimit {
                requests_per_second: 50,
                burst_capacity: 100,
            },
            endpoint_limits: HashMap::new(),
            redis: None,
            fail_open: true, // Default: allow requests if Redis down
        }
    }

    /// Add endpoint-specific limit
    pub fn with_endpoint_limit(mut self, path: &str, limit: EndpointLimit) -> Self {
        self.endpoint_limits.insert(path.to_string(), limit);
        self
    }

    /// Set Redis connection for distributed limiting
    pub fn with_redis(mut self, redis: ConnectionManager) -> Self {
        self.redis = Some(Arc::new(RwLock::new(redis)));
        self
    }

    /// Set fail-open behavior (true = allow when Redis down)
    pub fn with_fail_open(mut self, fail_open: bool) -> Self {
        self.fail_open = fail_open;
        self
    }
}

/// Enhanced rate limiter middleware
pub struct EnhancedRateLimiter {
    config: Rc<EnhancedRateLimitConfig>,
}

impl EnhancedRateLimiter {
    pub fn new(config: EnhancedRateLimitConfig) -> Self {
        Self {
            config: Rc::new(config),
        }
    }
}

impl<S, B> Transform<S, ServiceRequest> for EnhancedRateLimiter
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = EnhancedRateLimiterMiddleware<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(EnhancedRateLimiterMiddleware {
            service: Rc::new(service),
            config: self.config.clone(),
        }))
    }
}

pub struct EnhancedRateLimiterMiddleware<S> {
    service: Rc<S>,
    config: Rc<EnhancedRateLimitConfig>,
}

impl<S, B> Service<ServiceRequest> for EnhancedRateLimiterMiddleware<S>
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
        // Skip rate limiting for health check
        if req.path() == "/health" {
            let fut = self.service.call(req);
            return Box::pin(async move {
                let res = fut.await?;
                Ok(res)
            });
        }

        let config = self.config.clone();
        let service = self.service.clone();

        Box::pin(async move {
            // 1. Extract user ID from JWT claims (if authenticated)
            let user_id = req
                .extensions()
                .get::<String>()
                .map(|s| s.clone());

            // 2. Extract IP address (from X-Forwarded-For or connection info)
            let client_ip = extract_client_ip(&req);

            // 3. Determine which limit to apply
            let endpoint_path = req.path().to_string();
            let limit = determine_limit(&config, &endpoint_path, user_id.is_some());

            // 4. Check rate limit
            let rate_limit_key = if let Some(ref uid) = user_id {
                format!("rate:user:{}:{}", uid, endpoint_path)
            } else {
                format!("rate:ip:{}:{}", client_ip, endpoint_path)
            };

            let allowed = check_rate_limit(&config, &rate_limit_key, &limit).await;

            match allowed {
                Ok(true) => {
                    // Request allowed
                    let res = service.call(req).await?;
                    Ok(res)
                }
                Ok(false) => {
                    // Rate limit exceeded
                    warn!(
                        key = %rate_limit_key,
                        limit = limit.requests_per_second,
                        "Rate limit exceeded"
                    );
                    Err(actix_web::error::ErrorTooManyRequests(
                        "Rate limit exceeded. Please slow down.",
                    ))
                }
                Err(e) => {
                    // Redis error - fail open or closed based on config
                    if config.fail_open {
                        warn!(
                            error = %e,
                            "Rate limiter error - failing open (allowing request)"
                        );
                        let res = service.call(req).await?;
                        Ok(res)
                    } else {
                        error!(
                            error = %e,
                            "Rate limiter error - failing closed (blocking request)"
                        );
                        Err(actix_web::error::ErrorServiceUnavailable(
                            "Rate limiter unavailable",
                        ))
                    }
                }
            }
        })
    }
}

/// Extract client IP from request (X-Forwarded-For or connection info)
fn extract_client_ip(req: &ServiceRequest) -> String {
    // 1. Try X-Forwarded-For header (behind load balancer/proxy)
    if let Some(forwarded) = req.headers().get("X-Forwarded-For") {
        if let Ok(forwarded_str) = forwarded.to_str() {
            // Take first IP (original client)
            if let Some(first_ip) = forwarded_str.split(',').next() {
                return first_ip.trim().to_string();
            }
        }
    }

    // 2. Try X-Real-IP header (nginx)
    if let Some(real_ip) = req.headers().get("X-Real-IP") {
        if let Ok(ip_str) = real_ip.to_str() {
            return ip_str.to_string();
        }
    }

    // 3. Fall back to connection peer address
    req.peer_addr()
        .map(|addr| addr.ip().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

/// Determine which rate limit to apply
fn determine_limit(
    config: &EnhancedRateLimitConfig,
    endpoint_path: &str,
    is_authenticated: bool,
) -> EndpointLimit {
    // 1. Check for endpoint-specific limit
    if let Some(limit) = config.endpoint_limits.get(endpoint_path) {
        return limit.clone();
    }

    // 2. Apply per-user or per-IP limit
    if is_authenticated {
        config.per_user.clone()
    } else {
        config.global_per_ip.clone()
    }
}

/// Check rate limit using token bucket algorithm
async fn check_rate_limit(
    config: &EnhancedRateLimitConfig,
    key: &str,
    limit: &EndpointLimit,
) -> Result<bool, String> {
    // If no Redis, fail open (cannot enforce distributed limits)
    let redis = match &config.redis {
        Some(r) => r,
        None => return Ok(true), // No Redis = allow request
    };

    let mut conn = redis.write().await;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs_f64();

    // Token bucket keys in Redis
    let tokens_key = format!("{}:tokens", key);
    let last_refill_key = format!("{}:last_refill", key);

    // Get current tokens and last refill time
    let (current_tokens, last_refill): (Option<f64>, Option<f64>) = redis::pipe()
        .get(&tokens_key)
        .get(&last_refill_key)
        .query_async(&mut *conn)
        .await
        .map_err(|e| format!("Redis error: {}", e))?;

    let current_tokens = current_tokens.unwrap_or(limit.burst_capacity as f64);
    let last_refill = last_refill.unwrap_or(now);

    // Calculate token refill (based on time elapsed)
    let refill_rate = limit.requests_per_second as f64;
    let time_elapsed = now - last_refill;
    let tokens_to_add = time_elapsed * refill_rate;
    let new_tokens = (current_tokens + tokens_to_add).min(limit.burst_capacity as f64);

    // Check if we have at least 1 token
    if new_tokens >= 1.0 {
        // Consume 1 token
        let remaining_tokens = new_tokens - 1.0;

        // Update Redis
        let ttl = (limit.burst_capacity / limit.requests_per_second) as usize * 2; // 2x bucket drain time
        let _: () = redis::pipe()
            .set_ex(&tokens_key, remaining_tokens, ttl)
            .set_ex(&last_refill_key, now, ttl)
            .query_async(&mut *conn)
            .await
            .map_err(|e| format!("Redis error: {}", e))?;

        Ok(true)
    } else {
        // No tokens available
        Ok(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, web, App};

    async fn test_handler() -> actix_web::Result<HttpResponse> {
        Ok(HttpResponse::Ok().body("success"))
    }

    #[actix_web::test]
    async fn test_rate_limiter_allows_within_limit() {
        let config = EnhancedRateLimitConfig::new();
        let app = test::init_service(
            App::new()
                .wrap(EnhancedRateLimiter::new(config))
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        // First request should be allowed
        let req = test::TestRequest::get().uri("/test").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 200);
    }

    #[actix_web::test]
    async fn test_health_check_bypasses_rate_limit() {
        let config = EnhancedRateLimitConfig::new();
        let app = test::init_service(
            App::new()
                .wrap(EnhancedRateLimiter::new(config))
                .route("/health", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get().uri("/health").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 200);
    }

    #[test]
    fn test_extract_ip_from_x_forwarded_for() {
        let app = test::init_service(App::new().route("/test", web::get().to(test_handler)));

        let req = test::TestRequest::get()
            .uri("/test")
            .insert_header(("X-Forwarded-For", "192.168.1.1, 10.0.0.1"))
            .to_srv_request();

        let ip = extract_client_ip(&req);
        assert_eq!(ip, "192.168.1.1");
    }

    #[test]
    fn test_determine_limit_uses_endpoint_specific() {
        let mut config = EnhancedRateLimitConfig::new();
        config.endpoint_limits.insert(
            "/expensive".to_string(),
            EndpointLimit {
                requests_per_second: 1,
                burst_capacity: 2,
            },
        );

        let limit = determine_limit(&config, "/expensive", false);
        assert_eq!(limit.requests_per_second, 1);
    }

    #[test]
    fn test_determine_limit_uses_per_user_when_authenticated() {
        let config = EnhancedRateLimitConfig::new();
        let limit = determine_limit(&config, "/api/users", true);
        assert_eq!(limit.requests_per_second, config.per_user.requests_per_second);
    }

    #[test]
    fn test_determine_limit_uses_per_ip_when_not_authenticated() {
        let config = EnhancedRateLimitConfig::new();
        let limit = determine_limit(&config, "/api/users", false);
        assert_eq!(limit.requests_per_second, config.global_per_ip.requests_per_second);
    }
}
