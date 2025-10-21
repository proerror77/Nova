# RTMP Metrics Integration Guide

## Overview

This document provides guidance for integrating RTMP protocol-level metrics into the Nova Streaming platform. While the core streaming metrics are already instrumented, RTMP-specific metrics can provide deeper insight into broadcaster experience and ingestion quality.

## RTMP Metrics to Consider

### 1. RTMP Connection Metrics

#### Metric: `nova_streaming_rtmp_connections_total`
- **Type**: Counter
- **Labels**: `status` ("success", "failed", "timeout")
- **Description**: Total RTMP connection attempts
- **Where to Add**: RTMP connection handler
- **Recommended Threshold**: Alert if failure rate > 5% over 5m

#### Metric: `nova_streaming_rtmp_connection_duration_seconds`
- **Type**: Histogram
- **Labels**: None
- **Description**: Duration of RTMP connections from auth to disconnect
- **Where to Add**: RTMP session lifecycle
- **Buckets**: 60s, 300s, 600s, 1800s, 3600s (1h), 7200s (2h), 14400s (4h)

### 2. RTMP Frame Metrics

#### Metric: `nova_streaming_rtmp_frames_received_total`
- **Type**: Counter
- **Labels**: `frame_type` ("video", "audio", "data")
- **Description**: Total frames received over RTMP
- **Where to Add**: Frame processing loop
- **Use Case**: Detect missing frame types

#### Metric: `nova_streaming_rtmp_dropped_frames_total`
- **Type**: Counter
- **Labels**: `reason` ("buffer_full", "decode_error", "timeout")
- **Description**: Frames dropped during processing
- **Where to Add**: Frame drop handlers
- **Recommended Alert**: If drop rate > 0.1% over 5m

#### Metric: `nova_streaming_rtmp_frame_size_bytes`
- **Type**: Histogram
- **Labels**: `frame_type` ("video", "audio")
- **Description**: Distribution of frame sizes
- **Where to Add**: Frame size measurement
- **Buckets**: 1KB, 10KB, 50KB, 100KB, 500KB, 1MB

### 3. RTMP Chunk Metrics

#### Metric: `nova_streaming_rtmp_chunk_processing_duration_seconds`
- **Type**: Histogram
- **Labels**: `chunk_size_category` ("small", "medium", "large")
- **Description**: Time to process RTMP chunks
- **Where to Add**: Chunk parsing code
- **Buckets**: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms

#### Metric: `nova_streaming_rtmp_out_of_order_chunks`
- **Type**: Counter
- **Labels**: `stream_id`
- **Description**: Out-of-order chunk sequences detected
- **Where to Add**: Chunk assembly logic
- **Recommended Action**: Log and increment - may indicate broadcaster issues

### 4. RTMP Authentication Metrics

#### Metric: `nova_streaming_rtmp_auth_attempts_total`
- **Type**: Counter
- **Labels**: `status` ("success", "failed"), `method` ("rtmp_url", "token")
- **Description**: RTMP authentication attempts
- **Where to Add**: Auth handler
- **Recommended Alert**: Alert on auth failure rate > 10%

#### Metric: `nova_streaming_rtmp_auth_duration_seconds`
- **Type**: Histogram
- **Labels**: `method` ("rtmp_url", "token")
- **Description**: Time to verify RTMP auth
- **Where to Add**: Auth verification
- **Buckets**: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms

### 5. RTMP Stream State Metrics

#### Metric: `nova_streaming_rtmp_publish_commands_received`
- **Type**: Counter
- **Labels**: None
- **Description**: Total RTMP publish commands received
- **Where to Add**: Command handler
- **Use Case**: Track command frequency

#### Metric: `nova_streaming_rtmp_buffer_fill_percent`
- **Type**: Gauge
- **Labels**: `stream_id`
- **Description**: Current fill level of streaming buffer
- **Where to Add**: Buffer management
- **Typical Range**: 0-100%
- **Recommended Alert**: Alert if > 95% (buffer overflow risk)

### 6. RTMP Bandwidth Metrics

#### Metric: `nova_streaming_rtmp_ingestion_bandwidth_kbps`
- **Type**: Gauge
- **Labels**: `stream_id`
- **Description**: Actual ingestion bandwidth in kilobits per second
- **Where to Add**: Bitrate calculation
- **Use Case**: Monitor bandwidth usage

#### Metric: `nova_streaming_rtmp_bitrate_variation`
- **Type**: Gauge
- **Labels**: `stream_id`
- **Description**: Coefficient of variation in bitrate (0-1)
- **Where to Add**: Quality analysis
- **Interpretation**: Higher = less stable stream

---

## Implementation Patterns

### Pattern 1: Counter for Occurrences

```rust
// In RTMP frame handler
use crate::metrics::streaming_metrics;

if let Err(e) = process_frame(&frame) {
    streaming_metrics::helpers::record_broadcast_error("frame_decode_error");
}
```

### Pattern 2: Histogram for Latency

```rust
// In RTMP processing
use std::time::Instant;

let start = Instant::now();
let latency_ms = process_chunk(&chunk)?;
let elapsed = start.elapsed().as_secs_f64();
streaming_metrics::helpers::record_rtmp_frame_latency("1080p", elapsed);
```

### Pattern 3: Gauge for Current State

```rust
// In buffer management
pub fn update_buffer_status(stream_id: &str, fill_percent: f64) {
    // Add new helper if needed:
    // streaming_metrics::helpers::record_buffer_fill(stream_id, fill_percent);
}
```

### Pattern 4: Automatic Duration Tracking

```rust
// Using StreamTimer for auto-instrumentation
let timer = streaming_metrics::helpers::StreamTimer::new("live");
// Do work...
let duration_sec = timer.finish(); // Auto-recorded on drop
```

---

## Adding New Metrics

### Step 1: Define Metric in streaming_metrics.rs

```rust
// In streaming_metrics.rs

use lazy_static::lazy_static;

lazy_static! {
    pub static ref RTMP_FRAME_DROPS: CounterVec = register_counter_vec!(
        "nova_streaming_rtmp_dropped_frames_total",
        "Number of frames dropped during RTMP processing",
        &["reason"]
    )
    .unwrap();
}
```

### Step 2: Add Helper Function

```rust
// In streaming_metrics::helpers

pub fn record_frame_drop(reason: &str) {
    RTMP_FRAME_DROPS
        .with_label_values(&[reason])
        .inc();
}
```

### Step 3: Register Metric (if using lazy_static)

```rust
// In metrics/mod.rs init_metrics()

pub fn init_metrics() {
    // ... existing code ...
    REGISTRY
        .register(Box::new(RTMP_FRAME_DROPS.clone()))
        .expect("Failed to register RTMP_FRAME_DROPS");
}
```

### Step 4: Use in Code

```rust
// In RTMP handler
streaming_metrics::helpers::record_frame_drop("buffer_full");
```

### Step 5: Update Dashboard/Alerts

```json
{
  "targets": [
    {
      "expr": "rate(nova_streaming_rtmp_dropped_frames_total[5m])",
      "legendFormat": "{{ reason }}"
    }
  ]
}
```

---

## Recommended Alert Rules

```yaml
# PrometheusRule for RTMP-specific alerts

groups:
- name: nova-rtmp.rules
  interval: 30s
  rules:

  # Alert: High RTMP connection failure rate
  - alert: RtmpHighConnectionFailureRate
    expr: |
      (
        rate(nova_streaming_rtmp_connections_total{status="failed"}[5m])
        /
        rate(nova_streaming_rtmp_connections_total[5m])
      ) > 0.05
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "High RTMP connection failure rate ({{ $value | humanizePercentage }})"
      description: "RTMP connection failure rate exceeded 5%"

  # Alert: High frame drop rate
  - alert: RtmpHighFrameDropRate
    expr: |
      rate(nova_streaming_rtmp_dropped_frames_total[5m]) > 100
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High RTMP frame drop rate ({{ $value | humanize }})"
      description: "Frame drop rate exceeded 100 frames/sec"

  # Alert: RTMP buffer near capacity
  - alert: RtmpBufferNearCapacity
    expr: nova_streaming_rtmp_buffer_fill_percent > 95
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "RTMP buffer nearly full ({{ $value | humanize }}%)"
      description: "Stream {{ $labels.stream_id }} buffer fill at {{ $value }}%"
```

---

## Monitoring Dashboard Panels for RTMP

### Panel: Frame Processing Rate
```
Query: rate(nova_streaming_rtmp_frames_received_total[5m])
Type: Time Series
Grouped By: frame_type
Purpose: Monitor frame arrival rate
```

### Panel: Frame Drop Causes
```
Query: rate(nova_streaming_rtmp_dropped_frames_total[5m])
Type: Time Series (Stacked)
Grouped By: reason
Purpose: Identify why frames are being dropped
```

### Panel: Connection Health
```
Query: rate(nova_streaming_rtmp_connections_total{status="failed"}[5m]) / rate(nova_streaming_rtmp_connections_total[5m])
Type: Stat (percentage)
Purpose: Quick view of connection reliability
```

### Panel: Buffer Status
```
Query: nova_streaming_rtmp_buffer_fill_percent
Type: Gauge
Purpose: Real-time buffer capacity monitoring
```

---

## Testing RTMP Metrics

### Unit Test Example

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_frame_drop() {
        helpers::record_frame_drop("buffer_full");
        let metrics = gather_streaming_metrics();
        assert!(metrics.contains("nova_streaming_rtmp_dropped_frames_total"));
        assert!(metrics.contains("buffer_full"));
    }

    #[test]
    fn test_connection_counter() {
        helpers::record_rtmp_connection_success();
        helpers::record_rtmp_connection_failure();
        let metrics = gather_streaming_metrics();
        assert!(metrics.contains("nova_streaming_rtmp_connections_total"));
    }
}
```

### Integration Test Example

```rust
#[tokio::test]
pub async fn test_rtmp_metrics_collection() {
    // Create fake RTMP session
    let stream_id = Uuid::new_v4();

    // Simulate frame processing
    for i in 0..100 {
        if i % 10 == 0 {
            // Simulate occasional drops
            streaming_metrics::helpers::record_broadcast_error("frame_drop");
        }
    }

    // Verify metrics were recorded
    let metrics = streaming_metrics::gather_streaming_metrics();
    assert!(metrics.contains("nova_streaming_broadcast_errors_total"));
}
```

---

## Future Considerations

### 1. Adaptive Bitrate Tracking
Monitor RTMP codec changes and transcoding decisions for different viewers

### 2. Geographic Metrics
Track RTMP ingest latency from different geographic regions

### 3. Broadcaster Device Analysis
Categorize broadcasters by device type (OBS, FFmpeg, mobile, etc.) and track by metrics

### 4. Stream Quality Scores
Compute composite quality scores based on multiple metrics (latency, bitrate variation, error rate)

### 5. Capacity Planning
Use historical RTMP metrics for resource forecasting and CDN scaling decisions

---

## References

- [RTMP Protocol Specification](https://rtmp.veriskope.com/pdf/amf0-file-format-specification.pdf)
- [OBS RTMP Settings Guide](https://obsproject.com/wiki/Streaming-Guide)
- [Prometheus Histogram Best Practices](https://prometheus.io/docs/practices/histograms/)
