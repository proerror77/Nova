use std::time::Instant;

use axum::{
    body::Body,
    extract::MatchedPath,
    http::Request,
    middleware::Next,
    response::{IntoResponse, Response},
};
use once_cell::sync::Lazy;
use prometheus::{
    Encoder, HistogramOpts, HistogramVec, IntCounterVec, Opts, TextEncoder,
};

static HTTP_REQUESTS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    let counter = IntCounterVec::new(
        Opts::new(
            "auth_service_http_requests_total",
            "Total number of HTTP requests handled by auth-service",
        ),
        &["method", "path", "status"],
    )
    .expect("failed to create auth_service_http_requests_total");
    prometheus::default_registry()
        .register(Box::new(counter.clone()))
        .expect("failed to register auth_service_http_requests_total");
    counter
});

static HTTP_REQUEST_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    let histogram = HistogramVec::new(
        HistogramOpts::new(
            "auth_service_http_request_duration_seconds",
            "HTTP request latencies for auth-service",
        )
        .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]),
        &["method", "path", "status"],
    )
    .expect("failed to create auth_service_http_request_duration_seconds");
    prometheus::default_registry()
        .register(Box::new(histogram.clone()))
        .expect("failed to register auth_service_http_request_duration_seconds");
    histogram
});

/// Axum middleware that records Prometheus HTTP metrics.
pub async fn track_http_metrics(req: Request<Body>, next: Next) -> Response {
    let method = req.method().as_str().to_string();
    let path = req
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_string())
        .unwrap_or_else(|| req.uri().path().to_string());

    let start = Instant::now();
    let response = next.run(req).await;
    let status = response.status().as_u16().to_string();
    let elapsed = start.elapsed().as_secs_f64();

    HTTP_REQUESTS_TOTAL
        .with_label_values(&[&method, &path, &status])
        .inc();
    HTTP_REQUEST_DURATION_SECONDS
        .with_label_values(&[&method, &path, &status])
        .observe(elapsed);

    response
}

/// Handler that serialises Prometheus metrics in text format.
pub async fn metrics_handler() -> impl IntoResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    if let Err(err) = encoder.encode(&metric_families, &mut buffer) {
        return (
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            err.to_string(),
        )
            .into_response();
    }

    Response::builder()
        .status(axum::http::StatusCode::OK)
        .header(axum::http::header::CONTENT_TYPE, encoder.format_type())
        .body(buffer.into())
        .unwrap_or_else(|err| {
            Response::builder()
                .status(axum::http::StatusCode::INTERNAL_SERVER_ERROR)
                .body(err.to_string().into())
                .expect("failed to build metrics error response")
        })
}
