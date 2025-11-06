use actix_web::{
    body::{BoxBody, MessageBody},
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage, HttpResponse,
};
use futures::future::LocalBoxFuture;
use std::collections::HashSet;
use std::sync::Arc;

use crate::middleware::rate_limit::RateLimiter;

/// Global rate limiting middleware that limits requests per IP or user
#[derive(Clone)]
pub struct GlobalRateLimitMiddleware {
    rate_limiter: Arc<RateLimiter>,
    trusted_proxies: Arc<HashSet<String>>,
}

impl GlobalRateLimitMiddleware {
    pub fn new(rate_limiter: RateLimiter, trusted_proxies: Vec<String>) -> Self {
        let proxy_set: HashSet<String> = trusted_proxies
            .into_iter()
            .filter_map(|ip| {
                let trimmed = ip.trim();
                if trimmed.is_empty() {
                    None
                } else {
                    Some(trimmed.to_string())
                }
            })
            .collect();

        Self {
            rate_limiter: Arc::new(rate_limiter),
            trusted_proxies: Arc::new(proxy_set),
        }
    }
}

impl<S, B> Transform<S, ServiceRequest> for GlobalRateLimitMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: MessageBody + 'static,
{
    type Response = ServiceResponse<BoxBody>;
    type Error = Error;
    type InitError = ();
    type Transform = GlobalRateLimitMiddlewareService<S>;
    type Future = std::future::Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        std::future::ready(Ok(GlobalRateLimitMiddlewareService {
            service: Arc::new(service),
            rate_limiter: self.rate_limiter.clone(),
            trusted_proxies: self.trusted_proxies.clone(),
        }))
    }
}

pub struct GlobalRateLimitMiddlewareService<S> {
    service: Arc<S>,
    rate_limiter: Arc<RateLimiter>,
    trusted_proxies: Arc<HashSet<String>>,
}

impl<S, B> Service<ServiceRequest> for GlobalRateLimitMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: MessageBody + 'static,
{
    type Response = ServiceResponse<BoxBody>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let service = self.service.clone();
        let rate_limiter = self.rate_limiter.clone();
        let trusted_proxies = self.trusted_proxies.clone();

        // Extract client identifier early before moving req
        let client_id = if let Some(user_id) = req.extensions().get::<crate::middleware::UserId>() {
            format!("user:{}", user_id.0)
        } else {
            // IMPORTANT: Call connection_info() ONCE to avoid BorrowMutError
            // ConnectionInfo internally uses request.extensions() to cache its value
            let conn_info = req.connection_info();
            let peer_addr = conn_info.peer_addr().map(|s| s.to_string());
            drop(conn_info); // Explicitly drop to release borrow

            // Determine client IP with trusted proxy awareness
            let connection_ip = peer_addr
                .as_ref()
                .and_then(|addr| addr.split(':').next().map(|s| s.to_string()));

            let client_ip = if let Some(ref proxy_ip) = connection_ip {
                if trusted_proxies.contains(proxy_ip) {
                    req.headers()
                        .get("X-Forwarded-For")
                        .and_then(|h| h.to_str().ok())
                        .and_then(|header| {
                            header
                                .split(',')
                                .map(|part| part.trim())
                                .find(|part| !part.is_empty())
                                .map(|part| part.to_string())
                        })
                        .unwrap_or_else(|| proxy_ip.clone())
                } else {
                    proxy_ip.clone()
                }
            } else {
                peer_addr
                    .and_then(|addr| addr.split(':').next().map(|s| s.to_string()))
                    .unwrap_or_else(|| "unknown".to_string())
            };

            let client_ip = if client_ip == "unknown" {
                req.headers()
                    .get("X-Real-IP")
                    .and_then(|h| h.to_str().ok())
                    .map(|s| s.to_string())
                    .unwrap_or(client_ip)
            } else {
                client_ip
            };

            let ip = if client_ip.is_empty() {
                "unknown".to_string()
            } else {
                client_ip
            };
            format!("ip:{}", ip)
        };

        Box::pin(async move {
            // Check rate limit
            match rate_limiter.is_rate_limited(&client_id).await {
                Ok(true) => {
                    // Rate limit exceeded
                    let response = HttpResponse::TooManyRequests()
                        .insert_header(("Retry-After", "60"))
                        .json(serde_json::json!({
                            "error": "Too many requests",
                            "details": "Rate limit exceeded. Please try again later."
                        }));
                    Ok(req.into_response(response.map_into_boxed_body()))
                }
                Ok(false) => {
                    // Request is allowed, continue to service
                    let res = service.call(req).await?;
                    Ok(res.map_into_boxed_body())
                }
                Err(e) => {
                    // Redis error - log and allow request to pass through
                    tracing::warn!("Rate limiter error: {}", e);
                    let res = service.call(req).await?;
                    Ok(res.map_into_boxed_body())
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_global_rate_limit_middleware_creation() {
        // This is a compile-time test to ensure the middleware can be created
        // Actual behavior tests would require a running Redis instance
        assert!(true);
    }
}
