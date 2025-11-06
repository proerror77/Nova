//! gRPC metrics layer utilities and helpers
//!
//! This module provides utilities for recording metrics in gRPC services.
//! The actual integration is typically done via a tonic interceptor.

use crate::metrics::GRPC_METRICS;
use std::time::Instant;

/// Helper to record a gRPC request completion
pub fn record_grpc_request(service: &str, method: &str, code: &str, duration_secs: f64) {
    GRPC_METRICS.record_request(service, method, code, duration_secs);
}

/// Helper to increment in-flight requests
pub fn inc_in_flight(service: &str, method: &str) {
    GRPC_METRICS.inc_in_flight(service, method);
}

/// Helper to decrement in-flight requests
pub fn dec_in_flight(service: &str, method: &str) {
    GRPC_METRICS.dec_in_flight(service, method);
}

/// RAII guard for tracking in-flight requests
///
/// This guard automatically increments the in-flight counter when created,
/// and decrements it when dropped. Use `complete()` to record the request
/// status code before the guard is dropped.
#[derive(Clone)]
pub struct RequestGuard {
    service: String,
    method: String,
    start: Instant,
    completed: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl RequestGuard {
    /// Create a new request guard (increments in-flight counter)
    pub fn new(service: impl Into<String>, method: impl Into<String>) -> Self {
        let service = service.into();
        let method = method.into();
        inc_in_flight(&service, &method);
        Self {
            service,
            method,
            start: Instant::now(),
            completed: std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false)),
        }
    }

    /// Record the request as completed with the given status code
    ///
    /// This must be called before the guard is dropped to properly record metrics.
    /// If not called, only the in-flight decrement will be recorded.
    pub fn complete(&self, code: &str) {
        let duration = self.start.elapsed();
        record_grpc_request(&self.service, &self.method, code, duration.as_secs_f64());
        self.completed
            .store(true, std::sync::atomic::Ordering::Relaxed);
    }
}

impl Drop for RequestGuard {
    fn drop(&mut self) {
        // Always decrement in-flight requests
        dec_in_flight(&self.service, &self.method);
    }
}

/// Create a GrpcMetricsLayer (marker type for documentation)
#[derive(Clone)]
pub struct GrpcMetricsLayer;

impl GrpcMetricsLayer {
    /// Create a new GrpcMetricsLayer
    pub fn new() -> Self {
        Self
    }
}

impl Default for GrpcMetricsLayer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metrics_layer_creation() {
        let _layer = GrpcMetricsLayer::new();
    }

    #[test]
    fn test_request_guard() {
        let _guard = RequestGuard::new("test_service", "test_method");
        // Guard should decrement on drop
    }
}
