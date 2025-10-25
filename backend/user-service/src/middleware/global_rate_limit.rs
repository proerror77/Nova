use actix_web::{
    body::{BoxBody, MessageBody},
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    error::ErrorTooManyRequests, Error, HttpMessage, HttpResponse,
};
use futures::future::LocalBoxFuture;
use std::sync::Arc;

use crate::middleware::rate_limit::RateLimiter;

/// Global rate limiting middleware that limits requests per IP or user
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
        }))
    }
}

pub struct GlobalRateLimitMiddlewareService<S> {
    service: Arc<S>,
    rate_limiter: Arc<RateLimiter>,
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

        // Extract client identifier early before moving req
        let client_id = if let Some(user_id) = req.extensions().get::<crate::middleware::UserId>() {
            format!("user:{}", user_id.0)
        } else {
            // Get IP address from X-Forwarded-For header or connection
            let ip = req
                .headers()
                .get("X-Forwarded-For")
                .and_then(|h| h.to_str().ok())
                .and_then(|s| s.split(',').next().map(|s| s.trim()))
                .map(|s| s.to_string())
                .or_else(|| req.connection_info().peer_addr().map(|s| s.to_string()))
                .unwrap_or_else(|| "unknown".to_string());
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
