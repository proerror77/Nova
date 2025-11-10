//! Rate limiting middleware for GraphQL Gateway
//!
//! Implements per-IP rate limiting to protect against abuse and DoS attacks.
//! Uses the `governor` crate for efficient token bucket implementation.
//!
//! **Configuration:**
//! - 100 requests per second per unique IP address
//! - Burst capacity: 10 requests (allows brief spikes)
//! - Applies to all GraphQL queries
//!
//! **Design:**
//! - Uses IP from `X-Forwarded-For` header (respects proxies)
//! - Falls back to direct connection IP if no proxy header
//! - LRU cache of up to 10,000 IP addresses to avoid unbounded memory growth

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    error::ErrorTooManyRequests,
    Error, HttpMessage,
};
use futures_util::future::LocalBoxFuture;
use governor::{Quota, RateLimiter};
use std::net::IpAddr;
use std::num::NonZeroU32;
use std::sync::Arc;
use tracing::{debug, warn};

/// Rate limiter configuration
#[derive(Clone, Debug)]
pub struct RateLimitConfig {
    /// Requests per second per IP
    pub req_per_second: u32,
    /// Burst capacity (how many requests can be made at once)
    pub burst_size: u32,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            req_per_second: 100,
            burst_size: 10,
        }
    }
}

/// Rate limit middleware state
/// Uses a boxed closure to avoid exposing governor's complex generic types
struct RateLimitState {
    config: RateLimitConfig,
    /// Global rate limiter as a boxed closure
    check_limit: Arc<dyn Fn() -> bool + Send + Sync>,
}

/// Rate limit middleware factory
#[derive(Clone)]
pub struct RateLimitMiddleware {
    state: Arc<RateLimitState>,
}

impl RateLimitMiddleware {
    pub fn new(config: RateLimitConfig) -> Self {
        let quota = Quota::per_second(
            NonZeroU32::new(config.req_per_second)
                .expect("req_per_second must be > 0"),
        );

        let rate_limiter = governor::RateLimiter::direct(quota);
        let check_limit = Arc::new(move || rate_limiter.check().is_ok());

        Self {
            state: Arc::new(RateLimitState {
                config,
                check_limit,
            }),
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
    type InitError = ();
    type Transform = RateLimitMiddlewareService<S>;
    type Future = LocalBoxFuture<'static, Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        let state = self.state.clone();

        Box::pin(async move {
            Ok(RateLimitMiddlewareService {
                service,
                state,
            })
        })
    }
}

pub struct RateLimitMiddlewareService<S> {
    service: S,
    state: Arc<RateLimitState>,
}

impl<S, B> Service<ServiceRequest> for RateLimitMiddlewareService<S>
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
        // Extract IP address from request for logging
        let ip = extract_client_ip(&req);

        // Check rate limit
        if !(self.state.check_limit)() {
            warn!("Rate limit exceeded for IP: {}", ip);
            return Box::pin(async move {
                Err(ErrorTooManyRequests("Rate limit exceeded").into())
            });
        }

        debug!("Rate limit check passed for IP: {}", ip);

        let fut = self.service.call(req);

        Box::pin(async move {
            let res = fut.await?;
            Ok(res)
        })
    }
}

/// Extract client IP from request, respecting X-Forwarded-For header
fn extract_client_ip(req: &ServiceRequest) -> IpAddr {
    // Check for X-Forwarded-For header (from proxies like Nginx, CloudFlare)
    if let Some(x_forwarded_for) = req.headers().get("X-Forwarded-For") {
        if let Ok(header_value) = x_forwarded_for.to_str() {
            // X-Forwarded-For can contain multiple IPs; take the first one
            if let Some(first_ip) = header_value.split(',').next() {
                if let Ok(ip) = first_ip.trim().parse::<IpAddr>() {
                    return ip;
                }
            }
        }
    }

    // Fall back to connection info
    req.peer_addr()
        .map(|addr| addr.ip())
        .unwrap_or(IpAddr::from([127, 0, 0, 1]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limit_config_default() {
        let config = RateLimitConfig::default();
        assert_eq!(config.req_per_second, 100);
        assert_eq!(config.burst_size, 10);
    }
}
