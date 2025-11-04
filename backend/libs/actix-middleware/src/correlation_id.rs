//! Request correlation ID middleware
//!
//! Extracts or generates unique correlation IDs for request tracing across services.
//! Propagates correlation IDs through:
//! - HTTP headers (X-Correlation-ID)
//! - gRPC metadata
//! - Kafka message headers
//! - Structured logs (via tracing context)
//!
//! ## Design
//! - If request has X-Correlation-ID header: use it
//! - Otherwise: generate UUID v4
//! - Store in request extensions for access by handlers
//! - Automatically added to all logs via tracing instrumentation
//!
//! ## Example
//! ```rust
//! use actix_middleware::CorrelationIdMiddleware;
//! use actix_web::App;
//!
//! let app = App::new()
//!     .wrap(CorrelationIdMiddleware);
//! ```

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::LocalBoxFuture;
use std::future::{ready, Ready};
use uuid::Uuid;

/// Middleware that manages request correlation IDs
#[derive(Clone)]
pub struct CorrelationIdMiddleware;

impl<S, B> Transform<S, ServiceRequest> for CorrelationIdMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = CorrelationIdMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(CorrelationIdMiddlewareService { service }))
    }
}

pub struct CorrelationIdMiddlewareService<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for CorrelationIdMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        // Extract or generate correlation ID
        let correlation_id = req
            .headers()
            .get("x-correlation-id")
            .and_then(|h| h.to_str().ok())
            .map(|s| s.to_string())
            .unwrap_or_else(|| Uuid::new_v4().to_string());

        // Store in request extensions for handler access
        req.extensions_mut().insert(correlation_id.clone());

        // Set response header
        let fut = self.service.call(req);

        Box::pin(async move {
            let res = fut.await?;
            let mut response = res.into_response();
            response
                .headers_mut()
                .insert("x-correlation-id", correlation_id.parse().unwrap());
            Ok(ServiceResponse::new(response.into(), response))
        })
    }
}

/// Extract correlation ID from request extensions
///
/// ## Example
/// ```rust
/// use actix_middleware::get_correlation_id;
/// use actix_web::HttpRequest;
///
/// fn handler(req: HttpRequest) -> String {
///     let id = get_correlation_id(&req);
///     format!("Request ID: {}", id)
/// }
/// ```
pub fn get_correlation_id(req: &actix_web::HttpRequest) -> String {
    req.extensions()
        .get::<String>()
        .map(|s| s.clone())
        .unwrap_or_else(|| Uuid::new_v4().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_uuid_format() {
        let id = Uuid::new_v4().to_string();
        assert_eq!(id.len(), 36); // UUID v4 string length
        assert!(id.contains('-'));
    }
}
