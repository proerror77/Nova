use std::time::Duration;

use actix_web::HttpResponse;
use once_cell::sync::Lazy;
use prometheus::{Encoder, HistogramOpts, HistogramVec, IntCounterVec, Opts, TextEncoder};

static HTTP_REQUESTS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    let counter = IntCounterVec::new(
        Opts::new(
            "streaming_service_http_requests_total",
            "Total HTTP requests handled by streaming-service",
        ),
        &["method", "path", "status"],
    )
    .expect("failed to create streaming_service_http_requests_total");
    prometheus::default_registry()
        .register(Box::new(counter.clone()))
        .expect("failed to register streaming_service_http_requests_total");
    counter
});

static HTTP_REQUEST_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    let histogram = HistogramVec::new(
        HistogramOpts::new(
            "streaming_service_http_request_duration_seconds",
            "HTTP request latency for streaming-service",
        )
        .buckets(vec![
            0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5,
        ]),
        &["method", "path", "status"],
    )
    .expect("failed to create streaming_service_http_request_duration_seconds");
    prometheus::default_registry()
        .register(Box::new(histogram.clone()))
        .expect("failed to register streaming_service_http_request_duration_seconds");
    histogram
});

pub fn observe_http_request(method: &str, path: &str, status: u16, elapsed: Duration) {
    let status_label = status.to_string();
    HTTP_REQUESTS_TOTAL
        .with_label_values(&[method, path, &status_label])
        .inc();
    HTTP_REQUEST_DURATION_SECONDS
        .with_label_values(&[method, path, &status_label])
        .observe(elapsed.as_secs_f64());
}

pub async fn serve_metrics() -> HttpResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    if let Err(err) = encoder.encode(&metric_families, &mut buffer) {
        return HttpResponse::InternalServerError().body(err.to_string());
    }

    HttpResponse::Ok()
        .content_type(encoder.format_type())
        .body(buffer)
}
