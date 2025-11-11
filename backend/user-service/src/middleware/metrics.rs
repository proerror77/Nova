/// Actix-web middleware for automatic Prometheus metrics collection
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures::future::LocalBoxFuture;
use std::future::{ready, Ready};
use std::time::Instant;

use crate::metrics::RATE_LIMIT_HITS;

/// Middleware factory for metrics collection
pub struct MetricsMiddleware;

impl<S, B> Transform<S, ServiceRequest> for MetricsMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = MetricsMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(MetricsMiddlewareService { service }))
    }
}

/// Middleware service that wraps each request
pub struct MetricsMiddlewareService<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for MetricsMiddlewareService<S>
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
        let start_time = Instant::now();

        // CRITICAL FIX for actix-web 4.11.0 BorrowMutError:
        // Extract all immutable data FIRST, before ANY mutable access
        // This ensures no RefCell borrows are active when we call extensions_mut()
        let path = req.path().to_string();
        let method = req.method().to_string();

        // Now safe to mutably borrow - all prior immutable borrows are dropped
        let mut req = req;
        req.extensions_mut().insert(start_time);

        let fut = self.service.call(req);

        Box::pin(async move {
            let res = fut.await?;
            let duration = start_time.elapsed();

            // Record metrics based on path and status
            let status = res.status();
            let status_code = status.as_u16();

            // Log metrics for auth endpoints
            if path.starts_with("/api/v1/auth") {
                tracing::debug!(
                    "Auth request: {} {} - {} ({:.3}ms)",
                    method,
                    path,
                    status_code,
                    duration.as_millis()
                );

                // Record rate limit hits (429 status)
                if status_code == 429 {
                    RATE_LIMIT_HITS.with_label_values(&[&path]).inc();
                }
            }

            Ok(res)
        })
    }
}

/// Helper to extract request duration from extensions
pub fn get_request_duration_ms(req: &ServiceRequest) -> u64 {
    req.extensions()
        .get::<Instant>()
        .map(|start| start.elapsed().as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, web, App, HttpResponse};

    async fn test_handler() -> HttpResponse {
        HttpResponse::Ok().json(serde_json::json!({"status": "ok"}))
    }

    #[actix_web::test]
    async fn test_metrics_middleware_success() {
        let app = test::init_service(
            App::new()
                .wrap(MetricsMiddleware)
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get().uri("/test").to_request();
        let resp = test::call_service(&app, req).await;

        assert!(resp.status().is_success());
    }

    #[actix_web::test]
    async fn test_metrics_middleware_auth_path() {
        let app = test::init_service(
            App::new()
                .wrap(MetricsMiddleware)
                .route("/api/v1/auth/login", web::post().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::post()
            .uri("/api/v1/auth/login")
            .to_request();
        let resp = test::call_service(&app, req).await;

        assert!(resp.status().is_success());
    }
}
