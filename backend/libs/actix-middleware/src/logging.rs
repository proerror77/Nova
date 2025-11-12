//! Logging middleware
//!
//! Logs HTTP request/response information using tracing.

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error,
};
use futures::future::LocalBoxFuture;
use std::future::{ready, Ready};
use std::time::Instant;

/// Middleware that logs HTTP requests and responses
#[derive(Clone, Default)]
pub struct Logging;

impl<S, B> Transform<S, ServiceRequest> for Logging
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = LoggingService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(LoggingService { service }))
    }
}

pub struct LoggingService<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for LoggingService<S>
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
        let start = Instant::now();
        let method = req.method().clone();
        let path = req.path().to_string();

        tracing::info!(
            method = %method,
            path = %path,
            "HTTP request started"
        );

        let fut = self.service.call(req);

        Box::pin(async move {
            let res = fut.await?;
            let elapsed = start.elapsed();
            let status = res.status();

            tracing::info!(
                method = %method,
                path = %path,
                status = %status.as_u16(),
                duration_ms = elapsed.as_millis() as u64,
                "HTTP request completed"
            );

            Ok(res)
        })
    }
}
