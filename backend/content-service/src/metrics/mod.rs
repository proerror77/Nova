//! Prometheus metrics for content-service.
//!
//! Exposes feed-specific collectors and an HTTP handler for the `/metrics` endpoint.

use actix_web::HttpResponse;
use prometheus::{Encoder, TextEncoder};

pub mod content_cleaner;
pub mod feed;

/// Actix handler that renders Prometheus metrics in text format.
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
