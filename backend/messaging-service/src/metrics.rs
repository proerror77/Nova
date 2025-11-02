use actix_web::HttpResponse;
use once_cell::sync::Lazy;
use prometheus::{Encoder, HistogramOpts, HistogramVec, IntCounterVec, Opts, TextEncoder};

static HTTP_REQUESTS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    let counter = IntCounterVec::new(
        Opts::new(
            "messaging_service_http_requests_total",
            "Total HTTP requests handled by messaging-service",
        ),
        &["method", "path", "status"],
    )
    .expect("failed to create messaging_service_http_requests_total");
    prometheus::default_registry()
        .register(Box::new(counter.clone()))
        .expect("failed to register messaging_service_http_requests_total");
    counter
});

static HTTP_REQUEST_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    let histogram = HistogramVec::new(
        HistogramOpts::new(
            "messaging_service_http_request_duration_seconds",
            "HTTP request latencies for messaging-service",
        )
        .buckets(vec![
            0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5,
        ]),
        &["method", "path", "status"],
    )
    .expect("failed to create messaging_service_http_request_duration_seconds");
    prometheus::default_registry()
        .register(Box::new(histogram.clone()))
        .expect("failed to register messaging_service_http_request_duration_seconds");
    histogram
});

pub async fn metrics_handler() -> HttpResponse {
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
