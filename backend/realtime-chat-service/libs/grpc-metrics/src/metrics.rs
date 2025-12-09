//! Prometheus metrics definitions for gRPC services
//!
//! Tracks RED (Request, Error, Duration) metrics at the method level

use lazy_static::lazy_static;
use prometheus::{histogram_opts, opts, CounterVec, HistogramVec, IntGaugeVec, Registry, Result};

lazy_static! {
    /// Global gRPC metrics instance
    pub static ref GRPC_METRICS: GrpcMetrics = GrpcMetrics::new();
}

/// gRPC RED Metrics
#[derive(Clone)]
pub struct GrpcMetrics {
    /// Total gRPC requests by service, method, and gRPC code
    /// Labels: service, method, code
    pub requests_total: CounterVec,

    /// gRPC request latency in seconds (histogram)
    /// Labels: service, method
    pub request_duration_seconds: HistogramVec,

    /// Current in-flight gRPC requests by service and method
    /// Labels: service, method
    pub in_flight_requests: IntGaugeVec,

    /// Internal registry for proper scoping (reserved for future use)
    #[allow(dead_code)]
    registry: Option<Registry>,
}

impl GrpcMetrics {
    /// Create new GrpcMetrics instance
    pub fn new() -> Self {
        let requests_total = CounterVec::new(
            opts!("grpc_server_requests_total", "Total gRPC server requests"),
            &["service", "method", "code"],
        )
        .expect("failed to create requests_total metric");

        let request_duration_seconds = HistogramVec::new(
            histogram_opts!(
                "grpc_server_request_duration_seconds",
                "gRPC server request latency in seconds"
            ),
            &["service", "method"],
        )
        .expect("failed to create request_duration_seconds metric");

        let in_flight_requests = IntGaugeVec::new(
            opts!(
                "grpc_server_in_flight_requests",
                "Current in-flight gRPC server requests"
            ),
            &["service", "method"],
        )
        .expect("failed to create in_flight_requests metric");

        Self {
            requests_total,
            request_duration_seconds,
            in_flight_requests,
            registry: None,
        }
    }

    /// Register metrics with Prometheus registry
    pub fn register(&self) -> Result<()> {
        let registry = Registry::new();

        registry.register(Box::new(self.requests_total.clone()))?;
        registry.register(Box::new(self.request_duration_seconds.clone()))?;
        registry.register(Box::new(self.in_flight_requests.clone()))?;

        Ok(())
    }

    /// Record a completed gRPC request
    pub fn record_request(&self, service: &str, method: &str, code: &str, duration_secs: f64) {
        // Record total requests
        self.requests_total
            .with_label_values(&[service, method, code])
            .inc();

        // Record latency
        self.request_duration_seconds
            .with_label_values(&[service, method])
            .observe(duration_secs);
    }

    /// Increment in-flight request counter
    pub fn inc_in_flight(&self, service: &str, method: &str) {
        self.in_flight_requests
            .with_label_values(&[service, method])
            .inc();
    }

    /// Decrement in-flight request counter
    pub fn dec_in_flight(&self, service: &str, method: &str) {
        self.in_flight_requests
            .with_label_values(&[service, method])
            .dec();
    }
}

impl Default for GrpcMetrics {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metrics_creation() {
        let metrics = GrpcMetrics::new();
        assert!(metrics.register().is_ok());
    }

    #[test]
    fn test_record_request() {
        let metrics = GrpcMetrics::new();
        metrics.record_request("auth", "GetUser", "0", 0.123);
        // Metric recorded successfully
    }
}
