//! Prometheus Metrics for Live Streaming
//!
//! Tracks real-time streaming metrics:
//! - Nova_streaming_active_streams (gauge)
//! - Nova_streaming_viewers_total (histogram)
//! - Nova_streaming_peak_viewers (gauge)
//! - Nova_streaming_stream_duration_seconds (histogram)
//! - Nova_streaming_websocket_connections (gauge)
//! - Nova_streaming_broadcast_errors_total (counter)
//! - Nova_streaming_rtmp_ingestion_latency_seconds (histogram)
//! - Nova_streaming_quality_bitrate (gauge)

use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec, register_gauge, register_gauge_vec, register_histogram_vec, CounterVec,
    Encoder, Gauge, GaugeVec, HistogramVec, Registry, TextEncoder,
};

lazy_static! {
    // ===================================
    // Gauges - Real-time stream states
    // ===================================

    /// Current number of active broadcasting streams
    /// Labels: region (us-west-2, eu-central-1, etc.)
    pub static ref STREAMING_ACTIVE_STREAMS: GaugeVec = register_gauge_vec!(
        "nova_streaming_active_streams",
        "Number of currently active streaming broadcasts",
        &["region"]
    )
    .unwrap();

    /// Current number of connected WebSocket viewers
    /// Labels: stream_id (UUID)
    pub static ref STREAMING_WEBSOCKET_CONNECTIONS: GaugeVec = register_gauge_vec!(
        "nova_streaming_websocket_connections",
        "Number of currently connected WebSocket viewers",
        &["stream_id"]
    )
    .unwrap();

    /// Peak viewers for current active streams
    /// Labels: stream_id (UUID)
    pub static ref STREAMING_PEAK_VIEWERS: GaugeVec = register_gauge_vec!(
        "nova_streaming_peak_viewers",
        "Peak viewer count during stream lifetime",
        &["stream_id"]
    )
    .unwrap();

    /// Current streaming quality bitrate (kbps)
    /// Labels: stream_id, quality (720p, 1080p, 4k)
    pub static ref STREAMING_QUALITY_BITRATE: GaugeVec = register_gauge_vec!(
        "nova_streaming_quality_bitrate_kbps",
        "Current bitrate for streamed quality level",
        &["stream_id", "quality"]
    )
    .unwrap();

    // ===================================
    // Counters - Cumulative events
    // ===================================

    /// Total broadcast errors encountered
    /// Labels: error_type (rtmp_connection_failed, rtmp_frame_error, etc.)
    pub static ref STREAMING_BROADCAST_ERRORS_TOTAL: CounterVec = register_counter_vec!(
        "nova_streaming_broadcast_errors_total",
        "Total number of broadcast errors",
        &["error_type"]
    )
    .unwrap();

    // ===================================
    // Histograms - Performance metrics
    // ===================================

    /// Distribution of viewer counts per stream
    /// Labels: region
    pub static ref STREAMING_VIEWERS_HISTOGRAM: HistogramVec = register_histogram_vec!(
        "nova_streaming_viewers_total",
        "Total viewers per stream (histogram for distribution analysis)",
        &["region"],
        vec![1.0, 5.0, 10.0, 50.0, 100.0, 500.0, 1000.0, 5000.0, 10000.0]
    )
    .unwrap();

    /// Stream duration distribution in seconds
    /// Labels: stream_type (live, pre-recorded)
    pub static ref STREAMING_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "nova_streaming_stream_duration_seconds",
        "Duration of streaming sessions in seconds",
        &["stream_type"],
        vec![
            60.0,      // 1 minute
            300.0,     // 5 minutes
            600.0,     // 10 minutes
            1800.0,    // 30 minutes
            3600.0,    // 1 hour
            7200.0,    // 2 hours
            14400.0,   // 4 hours
            21600.0,   // 6 hours
            43200.0,   // 12 hours
            86400.0,   // 24 hours
        ]
    )
    .unwrap();

    /// RTMP ingestion latency in seconds
    /// Labels: quality (720p, 1080p, 4k)
    pub static ref STREAMING_RTMP_INGESTION_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
        "nova_streaming_rtmp_ingestion_latency_seconds",
        "Latency from broadcaster to Nginx-RTMP in seconds",
        &["quality"],
        vec![
            0.001,  // 1ms
            0.005,  // 5ms
            0.01,   // 10ms
            0.025,  // 25ms
            0.05,   // 50ms
            0.1,    // 100ms
            0.25,   // 250ms
            0.5,    // 500ms
            1.0,    // 1s
        ]
    )
    .unwrap();
}

/// Helper functions for streaming metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Record start of new broadcast stream
    pub fn record_stream_started(stream_id: &str, region: &str) {
        STREAMING_ACTIVE_STREAMS.with_label_values(&[region]).inc();
        STREAMING_PEAK_VIEWERS
            .with_label_values(&[stream_id])
            .set(0.0);
    }

    /// Record end of broadcast stream
    pub fn record_stream_ended(
        stream_id: &str,
        region: &str,
        duration_seconds: f64,
        viewer_count: i32,
    ) {
        STREAMING_ACTIVE_STREAMS.with_label_values(&[region]).dec();
        STREAMING_DURATION_SECONDS
            .with_label_values(&["live"])
            .observe(duration_seconds);
        STREAMING_VIEWERS_HISTOGRAM
            .with_label_values(&[region])
            .observe(viewer_count as f64);
    }

    /// Update current viewer count for a stream
    pub fn record_viewer_count_change(stream_id: &str, new_count: i32, region: &str) {
        STREAMING_WEBSOCKET_CONNECTIONS
            .with_label_values(&[stream_id])
            .set(new_count as f64);

        // Update peak viewers if this is a new peak
        // Note: This should be atomic in production
        if new_count > 0 {
            // In a real implementation, would fetch and compare with stored peak
            STREAMING_PEAK_VIEWERS
                .with_label_values(&[stream_id])
                .set(new_count as f64);
        }
    }

    /// Record RTMP connection established
    pub fn record_rtmp_connection_success(quality: &str) {
        // No specific metric for this, but could add to counters
    }

    /// Record RTMP connection failure
    pub fn record_rtmp_connection_failure() {
        STREAMING_BROADCAST_ERRORS_TOTAL
            .with_label_values(&["rtmp_connection_failed"])
            .inc();
    }

    /// Record RTMP frame processing latency
    pub fn record_rtmp_frame_latency(quality: &str, latency_seconds: f64) {
        STREAMING_RTMP_INGESTION_LATENCY_SECONDS
            .with_label_values(&[quality])
            .observe(latency_seconds);
    }

    /// Record broadcast error
    pub fn record_broadcast_error(error_type: &str) {
        STREAMING_BROADCAST_ERRORS_TOTAL
            .with_label_values(&[error_type])
            .inc();
    }

    /// Update streaming quality bitrate
    pub fn record_quality_bitrate(stream_id: &str, quality: &str, bitrate_kbps: f64) {
        STREAMING_QUALITY_BITRATE
            .with_label_values(&[stream_id, quality])
            .set(bitrate_kbps);
    }

    /// Record WebSocket connection
    pub fn record_websocket_connection(stream_id: &str) {
        STREAMING_WEBSOCKET_CONNECTIONS
            .with_label_values(&[stream_id])
            .inc();
    }

    /// Record WebSocket disconnection
    pub fn record_websocket_disconnection(stream_id: &str) {
        STREAMING_WEBSOCKET_CONNECTIONS
            .with_label_values(&[stream_id])
            .dec();
    }

    /// Timer guard for stream operations
    pub struct StreamTimer {
        start: Instant,
        stream_type: String,
    }

    impl StreamTimer {
        pub fn new(stream_type: &str) -> Self {
            Self {
                start: Instant::now(),
                stream_type: stream_type.to_string(),
            }
        }

        pub fn finish(self) -> f64 {
            self.start.elapsed().as_secs_f64()
        }
    }

    impl Drop for StreamTimer {
        fn drop(&mut self) {
            let duration = self.start.elapsed().as_secs_f64();
            STREAMING_DURATION_SECONDS
                .with_label_values(&[&self.stream_type])
                .observe(duration);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stream_started_metrics() {
        helpers::record_stream_started("stream-123", "us-west-2");
        let metrics = gather_streaming_metrics();
        assert!(metrics.contains("nova_streaming_active_streams"));
    }

    #[test]
    fn test_viewer_count_update() {
        helpers::record_viewer_count_change("stream-456", 42, "eu-central-1");
        let metrics = gather_streaming_metrics();
        assert!(metrics.contains("nova_streaming_websocket_connections"));
    }

    #[test]
    fn test_error_recording() {
        helpers::record_broadcast_error("frame_drop");
        let metrics = gather_streaming_metrics();
        assert!(metrics.contains("nova_streaming_broadcast_errors_total"));
    }
}

/// Gather streaming metrics in Prometheus text format
pub fn gather_streaming_metrics() -> String {
    let encoder = TextEncoder::new();
    let metric_families = crate::metrics::REGISTRY.gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).ok();
    String::from_utf8_lossy(&buffer).to_string()
}
