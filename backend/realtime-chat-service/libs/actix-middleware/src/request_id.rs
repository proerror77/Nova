//! Request ID middleware
//!
//! Generates unique request IDs for tracking HTTP requests.
//! Similar to CorrelationIdMiddleware but uses X-Request-ID header.

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    http::header::{HeaderName, HeaderValue},
    Error, HttpMessage,
};
use futures::future::LocalBoxFuture;
use std::future::{ready, Ready};
use uuid::Uuid;

/// Middleware that generates and attaches request IDs
#[derive(Clone, Default)]
pub struct RequestId;

impl RequestId {
    pub fn new() -> Self {
        Self
    }
}

impl<S, B> Transform<S, ServiceRequest> for RequestId
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = RequestIdService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(RequestIdService { service }))
    }
}

pub struct RequestIdService<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for RequestIdService<S>
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
        // Extract or generate request ID
        let request_id = req
            .headers()
            .get("x-request-id")
            .and_then(|h| h.to_str().ok())
            .map(|s| s.to_string())
            .unwrap_or_else(|| Uuid::new_v4().to_string());

        // Store in request extensions
        req.extensions_mut().insert(request_id.clone());

        let fut = self.service.call(req);

        Box::pin(async move {
            let mut res = fut.await?;

            // Add request ID header to response
            let header_name = HeaderName::from_static("x-request-id");
            let header_value = HeaderValue::from_str(&request_id)
                .expect("request_id should be valid header value");

            res.headers_mut().insert(header_name, header_value);
            Ok(res)
        })
    }
}
