//! gRPC Metrics Layer - Shared Tower Middleware for RED Metrics
//!
//! This library provides a reusable tower layer for collecting Prometheus metrics
//! on all gRPC services. It tracks:
//! - Requests by service/method/status
//! - Latency histograms
//! - In-flight request count
//!
//! Usage:
//! ```ignore
//! use grpc_metrics::GrpcMetricsLayer;
//!
//! let metrics_layer = GrpcMetricsLayer::new();
//! let server = Server::builder()
//!     .layer(metrics_layer)
//!     .add_service(my_service)
//!     .serve(addr)
//!     .await?;
//! ```

pub mod layer;
mod metrics;

pub use layer::GrpcMetricsLayer;
pub use metrics::{GrpcMetrics, GRPC_METRICS};

/// Register metrics with the Prometheus registry
///
/// Call this once during server initialization
pub fn register_metrics() -> prometheus::Result<()> {
    GRPC_METRICS.register()
}
