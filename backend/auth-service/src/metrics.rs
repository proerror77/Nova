use actix_web::{HttpResponse, Responder};
use prometheus::{Encoder, TextEncoder};

/// Handler that serialises Prometheus metrics in text format.
pub async fn metrics_handler() -> impl Responder {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    match encoder.encode(&metric_families, &mut buffer) {
        Ok(_) => HttpResponse::Ok()
            .content_type(encoder.format_type())
            .body(buffer),
        Err(err) => HttpResponse::InternalServerError().body(err.to_string()),
    }
}
