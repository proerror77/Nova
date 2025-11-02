use actix_web::{
    dev::{Service, ServiceRequest, ServiceResponse, Transform},
    Error,
};
use futures::future::{ready, Ready};
use prometheus::{HistogramVec, IntCounterVec};
use std::future::Future;
use std::pin::Pin;
use std::rc::Rc;
use std::time::Instant;

/// Prometheus Metrics Middleware
pub struct MetricsMiddleware;

lazy_static::lazy_static! {
    pub static ref HTTP_REQUESTS_TOTAL: IntCounterVec = prometheus::register_int_counter_vec!(
        "http_requests_total",
        "Total HTTP requests",
        &["method", "path", "status"]
    ).unwrap();

    pub static ref HTTP_REQUEST_DURATION_SECONDS: HistogramVec = prometheus::register_histogram_vec!(
        "http_request_duration_seconds",
        "HTTP request latency",
        &["method", "path", "status"],
        vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
    ).unwrap();
}

impl<S, B> Transform<S, ServiceRequest> for MetricsMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Transform = MetricsMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(MetricsMiddlewareService {
            service: Rc::new(service),
        }))
    }
}

pub struct MetricsMiddlewareService<S> {
    service: Rc<S>,
}

impl<S, B> Service<ServiceRequest> for MetricsMiddlewareService<S>
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
        let start = Instant::now();
        let method = req.method().to_string();
        let path = req.path().to_string();

        Box::pin(async move {
            let res = service.call(req).await?;
            let status = res.status().as_u16().to_string();
            let duration = start.elapsed().as_secs_f64();

            HTTP_REQUESTS_TOTAL
                .with_label_values(&[&method, &path, &status])
                .inc();

            HTTP_REQUEST_DURATION_SECONDS
                .with_label_values(&[&method, &path, &status])
                .observe(duration);

            Ok(res)
        })
    }
}
