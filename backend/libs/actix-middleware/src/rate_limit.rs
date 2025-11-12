use actix_web::{
    dev::{Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::{ready, Ready};
use lazy_static::lazy_static;
use redis::{aio::ConnectionManager, AsyncCommands};
use serde::Deserialize;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::time::timeout;

/// Rate limit failure behavior when Redis is unavailable
#[derive(Debug, Clone, Copy, Deserialize)]
#[derive(Default)]
pub enum FailureMode {
    /// Allow requests when Redis fails (prioritize availability)
    #[default]
    FailOpen,
    /// Deny requests when Redis fails (prioritize security)
    FailClosed,
}


// In-memory fallback rate limit counter (per-process, not distributed)
// Used when Redis is unavailable and FailClosed mode is enabled
// Structure: HashMap<key, (count, window_start_time)>
lazy_static! {
    static ref LOCAL_RATE_LIMIT: Arc<Mutex<HashMap<String, (u32, Instant)>>> =
        Arc::new(Mutex::new(HashMap::new()));
}

#[derive(Debug, Clone, Deserialize)]
pub struct RateLimitConfig {
    pub max_requests: u32,
    pub window_seconds: u64,
    /// Redis operation timeout in milliseconds
    pub redis_timeout_ms: u64,
    /// Include User-Agent in rate limit key (recommended for auth endpoints)
    #[serde(default)]
    pub include_user_agent: bool,
    /// Failure mode when Redis is unavailable
    #[serde(default)]
    pub failure_mode: FailureMode,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 100,
            window_seconds: 900,   // 15 minutes
            redis_timeout_ms: 100, // Fast timeout to prevent blocking
            include_user_agent: false,
            failure_mode: FailureMode::FailOpen,
        }
    }
}

impl RateLimitConfig {
    /// Preset for authentication endpoints (strict)
    pub fn auth_strict() -> Self {
        Self {
            max_requests: 5,
            window_seconds: 60, // 5 attempts per minute
            redis_timeout_ms: 100,
            include_user_agent: true,
            failure_mode: FailureMode::FailClosed, // Security > Availability
        }
    }

    /// Preset for general API endpoints (lenient)
    pub fn api_lenient() -> Self {
        Self {
            max_requests: 100,
            window_seconds: 60,
            redis_timeout_ms: 100,
            include_user_agent: false,
            failure_mode: FailureMode::FailOpen,
        }
    }
}

#[derive(Clone)]
pub struct RateLimitMiddleware {
    config: RateLimitConfig,
    redis: Arc<Mutex<ConnectionManager>>,
}

impl RateLimitMiddleware {
    pub fn new(config: RateLimitConfig, redis: Arc<Mutex<ConnectionManager>>) -> Self {
        Self { config, redis }
    }

    /// Create with default config
    pub fn with_default_config(redis: Arc<Mutex<ConnectionManager>>) -> Self {
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
            // Build rate limit key with IP + optional User-Agent
            let ip = req
                .connection_info()
                .realip_remote_addr()
                .unwrap_or("unknown")
                .to_string();

            let key = if let Some(user_id) = req.extensions().get::<crate::jwt_auth::UserId>() {
                // Authenticated users: rate limit by user_id
                format!("rate_limit:user:{}", user_id.0)
            } else if config.include_user_agent {
                // Unauthenticated + User-Agent: better protection against distributed attacks
                let user_agent = req
                    .headers()
                    .get("user-agent")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("unknown");
                format!("rate_limit:ip_ua:{}:{}", ip, user_agent)
            } else {
                // Unauthenticated: rate limit by IP only
                format!("rate_limit:ip:{}", ip)
            };

            // Check rate limit with timeout protection
            let rate_limit_result = timeout(
                Duration::from_millis(config.redis_timeout_ms),
                check_rate_limit(&redis, &key, &config),
            )
            .await;

            match rate_limit_result {
                Ok(Ok(exceeded)) => {
                    if exceeded {
                        tracing::warn!(
                            "Rate limit exceeded for key={} ({})",
                            key,
                            req.uri().path()
                        );
                        return Err(actix_web::error::ErrorTooManyRequests(
                            serde_json::json!({
                                "error": "Rate limit exceeded",
                                "max_requests": config.max_requests,
                                "window_seconds": config.window_seconds,
                            })
                            .to_string(),
                        ));
                    }
                }
                Ok(Err(e)) => {
                    // Redis error: behavior depends on failure_mode
                    match config.failure_mode {
                        FailureMode::FailOpen => {
                            tracing::warn!(
                                "Rate limit Redis error (fail-open, allowing request): {}",
                                e
                            );
                        }
                        FailureMode::FailClosed => {
                            // Use local fallback instead of blanket denial
                            tracing::warn!(
                                "Rate limit Redis error (fail-closed mode, using in-memory fallback): {}",
                                e
                            );

                            match check_rate_limit_local(&key, &config).await {
                                Ok(true) => {
                                    tracing::warn!(
                                        "Rate limit exceeded (local fallback) for key={} ({})",
                                        key,
                                        req.uri().path()
                                    );
                                    return Err(actix_web::error::ErrorTooManyRequests(
                                        serde_json::json!({
                                            "error": "Rate limit exceeded (fallback mode)",
                                            "max_requests": config.max_requests,
                                            "window_seconds": config.window_seconds,
                                        })
                                        .to_string(),
                                    ));
                                }
                                Ok(false) => {
                                    // Within limit - allow request
                                    tracing::debug!("Request allowed (local fallback)");
                                }
                                Err(fallback_err) => {
                                    // Even fallback failed - this is extremely rare
                                    tracing::error!(
                                        "Both Redis and local fallback failed: Redis={}, Fallback={}",
                                        e,
                                        fallback_err
                                    );
                                    return Err(actix_web::error::ErrorServiceUnavailable(
                                        "Rate limiting service temporarily unavailable",
                                    ));
                                }
                            }
                        }
                    }
                }
                Err(_) => {
                    // Timeout: behavior depends on failure_mode
                    match config.failure_mode {
                        FailureMode::FailOpen => {
                            tracing::warn!(
                                "Rate limit Redis timeout ({}ms, fail-open, allowing request)",
                                config.redis_timeout_ms
                            );
                        }
                        FailureMode::FailClosed => {
                            // Use local fallback instead of blanket denial
                            tracing::warn!(
                                "Rate limit Redis timeout ({}ms, fail-closed mode, using in-memory fallback)",
                                config.redis_timeout_ms
                            );

                            match check_rate_limit_local(&key, &config).await {
                                Ok(true) => {
                                    tracing::warn!(
                                        "Rate limit exceeded (local fallback after timeout) for key={} ({})",
                                        key,
                                        req.uri().path()
                                    );
                                    return Err(actix_web::error::ErrorTooManyRequests(
                                        serde_json::json!({
                                            "error": "Rate limit exceeded (fallback mode)",
                                            "max_requests": config.max_requests,
                                            "window_seconds": config.window_seconds,
                                        })
                                        .to_string(),
                                    ));
                                }
                                Ok(false) => {
                                    // Within limit - allow request
                                    tracing::debug!(
                                        "Request allowed (local fallback after timeout)"
                                    );
                                }
                                Err(fallback_err) => {
                                    // Even fallback failed - this is extremely rare
                                    tracing::error!(
                                        "Redis timeout and local fallback failed: {}",
                                        fallback_err
                                    );
                                    return Err(actix_web::error::ErrorServiceUnavailable(
                                        "Rate limiting service timeout",
                                    ));
                                }
                            }
                        }
                    }
                }
            }

            service.call(req).await
        })
    }
}

/// Check rate limit for a given key
/// Returns Ok(true) if limit exceeded, Ok(false) if within limit
async fn check_rate_limit(
    redis: &Arc<Mutex<ConnectionManager>>,
    key: &str,
    config: &RateLimitConfig,
) -> Result<bool, String> {
    // Lock the connection manager and clone the connection
    let mut conn = {
        let guard = redis.lock().await;
        guard.clone()
    };

    let count: u32 = conn
        .incr(key, 1)
        .await
        .map_err(|e| format!("Redis incr failed: {}", e))?;

    // Set expiry on first request
    if count == 1 {
        let _: () = conn
            .expire(key, config.window_seconds as i64)
            .await
            .map_err(|e| format!("Redis expire failed: {}", e))?;
    }

    Ok(count > config.max_requests)
}

/// Local in-memory rate limit check (fallback when Redis unavailable)
/// Returns Ok(true) if limit exceeded, Ok(false) if within limit
/// NOTE: This is per-process, not distributed across instances
async fn check_rate_limit_local(key: &str, config: &RateLimitConfig) -> Result<bool, String> {
    let mut map = LOCAL_RATE_LIMIT.lock().await;
    let now = Instant::now();

    // Get or create entry
    let entry = map.entry(key.to_string()).or_insert((0, now));

    // Reset window if expired
    if now.duration_since(entry.1).as_secs() >= config.window_seconds {
        entry.0 = 0;
        entry.1 = now;
    }

    // Increment counter
    entry.0 += 1;
    let current_count = entry.0;

    // Periodic cleanup: remove expired entries (simple approach)
    // This prevents unbounded memory growth
    if map.len() > 10000 {
        map.retain(|_, (_, start)| {
            now.duration_since(*start).as_secs() < config.window_seconds * 2
        });
    }

    Ok(current_count > config.max_requests)
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
        assert!(!config.include_user_agent);
        assert!(matches!(config.failure_mode, FailureMode::FailOpen));
    }

    #[test]
    fn test_rate_limit_config_auth_strict() {
        let config = RateLimitConfig::auth_strict();
        assert_eq!(config.max_requests, 5);
        assert_eq!(config.window_seconds, 60);
        assert_eq!(config.redis_timeout_ms, 100);
        assert!(config.include_user_agent);
        assert!(matches!(config.failure_mode, FailureMode::FailClosed));
    }

    #[test]
    fn test_rate_limit_config_api_lenient() {
        let config = RateLimitConfig::api_lenient();
        assert_eq!(config.max_requests, 100);
        assert_eq!(config.window_seconds, 60);
        assert!(!config.include_user_agent);
        assert!(matches!(config.failure_mode, FailureMode::FailOpen));
    }

    #[test]
    fn test_rate_limit_config_custom() {
        let config = RateLimitConfig {
            max_requests: 50,
            window_seconds: 300,
            redis_timeout_ms: 50,
            include_user_agent: true,
            failure_mode: FailureMode::FailClosed,
        };
        assert_eq!(config.max_requests, 50);
        assert_eq!(config.window_seconds, 300);
        assert_eq!(config.redis_timeout_ms, 50);
        assert!(config.include_user_agent);
        assert!(matches!(config.failure_mode, FailureMode::FailClosed));
    }

    #[test]
    fn test_failure_mode_default() {
        let mode = FailureMode::default();
        assert!(matches!(mode, FailureMode::FailOpen));
    }

    #[test]
    fn test_rate_limit_key_format_user() {
        let key = "rate_limit:user:12345";
        assert!(key.starts_with("rate_limit:user:"));
    }

    #[test]
    fn test_rate_limit_key_format_ip() {
        let key = "rate_limit:ip:192.168.1.1";
        assert!(key.starts_with("rate_limit:ip:"));
    }

    #[test]
    fn test_rate_limit_key_format_ip_ua() {
        let key = "rate_limit:ip_ua:192.168.1.1:Mozilla/5.0";
        assert!(key.starts_with("rate_limit:ip_ua:"));
        assert!(key.contains("Mozilla"));
    }

    #[test]
    fn test_auth_strict_security_over_availability() {
        let config = RateLimitConfig::auth_strict();
        // Auth endpoints should fail closed
        assert!(matches!(config.failure_mode, FailureMode::FailClosed));
        // Auth endpoints should be very restrictive
        assert!(config.max_requests <= 10);
        assert!(config.window_seconds <= 60);
    }

    #[test]
    fn test_rate_limit_fast_timeout() {
        let config = RateLimitConfig::default();
        assert_eq!(config.redis_timeout_ms, 100);
        assert!(
            config.redis_timeout_ms < 1000,
            "Timeout too long, will block requests"
        );
    }
}
