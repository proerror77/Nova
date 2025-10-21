# Metrics Collection and Dashboarding Guide

## Overview

This document describes the complete metrics collection and observability setup for the Nova Streaming platform. The system uses **Prometheus** for metrics collection, **Kubernetes ServiceMonitor** for automated scraping, and **Grafana** for visualization.

## Table of Contents

1. [Architecture](#architecture)
2. [Metrics Definitions](#metrics-definitions)
3. [Instrumentation Points](#instrumentation-points)
4. [Prometheus Setup](#prometheus-setup)
5. [Grafana Dashboards](#grafana-dashboards)
6. [Alerting](#alerting)
7. [Recording Rules](#recording-rules)
8. [Operational Procedures](#operational-procedures)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Nova Streaming Service (user-service)              │
│  Port 8081/metrics                                  │
│  ├─ Active streams gauge                            │
│  ├─ WebSocket connections gauge                     │
│  ├─ Peak viewers gauge                              │
│  ├─ Quality bitrate gauge                           │
│  ├─ Broadcast errors counter                        │
│  ├─ Viewers histogram                               │
│  ├─ Stream duration histogram                       │
│  └─ RTMP ingestion latency histogram                │
└─────────────────────────────────────────────────────┘
              │
              │ Scrapes every 30s
              ▼
┌─────────────────────────────────────────────────────┐
│  Prometheus                                         │
│  (via Prometheus Operator)                          │
│  ├─ ServiceMonitor: nova-streaming-monitor          │
│  ├─ PrometheusRule: nova-streaming-alerts           │
│  └─ PrometheusRule: nova-streaming-recording        │
└─────────────────────────────────────────────────────┘
              │
              │ Query endpoint
              ▼
┌─────────────────────────────────────────────────────┐
│  Grafana                                            │
│  Dashboard: Nova Streaming Metrics                  │
│  5-panel dashboard with streaming KPIs              │
└─────────────────────────────────────────────────────┘
```

---

## Metrics Definitions

### Gauges (Real-Time Values)

#### 1. `nova_streaming_active_streams`
- **Type**: Gauge
- **Labels**: `region` (e.g., "us-west-2", "eu-central-1")
- **Description**: Number of currently active broadcasting streams
- **Update Frequency**: On stream start/end
- **Typical Range**: 0-10000+

```rust
// Recording
streaming_metrics::helpers::record_stream_started("stream-uuid", "us-west-2");
streaming_metrics::helpers::record_stream_ended("stream-uuid", "us-west-2", 3600.0, 500);
```

#### 2. `nova_streaming_websocket_connections`
- **Type**: Gauge
- **Labels**: `stream_id` (UUID)
- **Description**: Current number of connected WebSocket viewers for a stream
- **Update Frequency**: On viewer join/leave
- **Typical Range**: 0-100000 per stream

```rust
// Recording
streaming_metrics::helpers::record_websocket_connection("stream-uuid");
streaming_metrics::helpers::record_websocket_disconnection("stream-uuid");
```

#### 3. `nova_streaming_peak_viewers`
- **Type**: Gauge
- **Labels**: `stream_id` (UUID)
- **Description**: Peak viewer count reached during stream lifetime
- **Update Frequency**: Updated whenever a new peak is reached
- **Typical Range**: 0-100000+ per stream

```rust
// Recording
streaming_metrics::helpers::record_viewer_count_change("stream-uuid", 1500, "us-west-2");
```

#### 4. `nova_streaming_quality_bitrate_kbps`
- **Type**: Gauge
- **Labels**: `stream_id` (UUID), `quality` (e.g., "720p", "1080p", "4k")
- **Description**: Current bitrate for a specific quality level
- **Update Frequency**: On quality adaptation
- **Typical Range**: 1000-50000 kbps

```rust
// Recording
streaming_metrics::helpers::record_quality_bitrate("stream-uuid", "1080p", 5000.0);
```

### Counters (Cumulative Events)

#### 5. `nova_streaming_broadcast_errors_total`
- **Type**: Counter
- **Labels**: `error_type` (e.g., "rtmp_connection_failed", "frame_drop", "timeout")
- **Description**: Total number of broadcasting errors encountered
- **Update Frequency**: On error occurrence
- **Notes**: Only increments (monotonically increasing)

```rust
// Recording
streaming_metrics::helpers::record_broadcast_error("rtmp_connection_failed");
streaming_metrics::helpers::record_rtmp_connection_failure();
```

### Histograms (Distributions)

#### 6. `nova_streaming_viewers_total`
- **Type**: Histogram
- **Labels**: `region` (e.g., "us-west-2")
- **Description**: Distribution of viewer counts across streams
- **Buckets**: 1, 5, 10, 50, 100, 500, 1000, 5000, 10000
- **Update Frequency**: On stream end (records final viewer count)

```rust
// Recording (part of stream_ended)
streaming_metrics::helpers::record_stream_ended("stream-uuid", "us-west-2", 3600.0, 5000);
```

#### 7. `nova_streaming_stream_duration_seconds`
- **Type**: Histogram
- **Labels**: `stream_type` ("live" or "pre-recorded")
- **Description**: Distribution of stream durations
- **Buckets**: 60s, 300s (5m), 600s (10m), 1800s (30m), 3600s (1h), 7200s (2h), 14400s (4h), 21600s (6h), 43200s (12h), 86400s (24h)
- **Update Frequency**: On stream end

```rust
// Recording (automatic via drop on StreamTimer)
let timer = streaming_metrics::helpers::StreamTimer::new("live");
// ... do work ...
// timer automatically recorded on drop
```

#### 8. `nova_streaming_rtmp_ingestion_latency_seconds`
- **Type**: Histogram
- **Labels**: `quality` ("720p", "1080p", "4k", etc.)
- **Description**: Latency from broadcaster to Nginx-RTMP ingestion point
- **Buckets**: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1000ms
- **Update Frequency**: On frame receipt from broadcaster

```rust
// Recording
streaming_metrics::helpers::record_rtmp_frame_latency("1080p", 0.045);
```

---

## Instrumentation Points

### 1. WebSocket Connection Lifecycle
**File**: `backend/user-service/src/handlers/streaming_websocket.rs`

```rust
// On WebSocket connection
fn started(&mut self, ctx: &mut Self::Context) {
    streaming_metrics::helpers::record_websocket_connection(&stream_id.to_string());
}

// On WebSocket disconnection
fn stopped(&mut self, _: &mut Self::Context) {
    streaming_metrics::helpers::record_websocket_disconnection(&stream_id.to_string());
}
```

### 2. Stream Lifecycle Events
**File**: `backend/user-service/src/handlers/streaming_websocket.rs`

```rust
// When broadcast begins
pub fn notify_stream_started(hub: &Addr<StreamingHub>, stream_id: Uuid) {
    streaming_metrics::helpers::record_stream_started(&stream_id.to_string(), "us-west-2");
    // ...
}

// When broadcast ends
pub fn notify_stream_ended(hub: &Addr<StreamingHub>, stream_id: Uuid) {
    streaming_metrics::helpers::record_stream_ended(&stream_id.to_string(), "us-west-2", 0.0, 0);
    // ...
}
```

### 3. Viewer Count Updates
**File**: `backend/user-service/src/handlers/streaming_websocket.rs`

```rust
pub async fn notify_viewer_count_changed(
    hub: &Addr<StreamingHub>,
    redis: &ConnectionManager,
    stream_id: Uuid,
) -> Result<()> {
    let viewer_count = counter.get_viewer_count(stream_id).await?;
    streaming_metrics::helpers::record_viewer_count_change(
        &stream_id.to_string(),
        viewer_count as i32,
        "us-west-2",
    );
    // ...
}
```

### 4. RTMP Frame Processing
**Location**: In RTMP handler (to be integrated)

```rust
// When processing RTMP frames
let latency = Instant::now().elapsed().as_secs_f64();
streaming_metrics::helpers::record_rtmp_frame_latency("1080p", latency);
```

### 5. Error Handling
**Location**: In error handlers throughout codebase

```rust
// On RTMP connection failures
streaming_metrics::helpers::record_rtmp_connection_failure();

// On broadcast errors
streaming_metrics::helpers::record_broadcast_error("frame_drop");
```

---

## Prometheus Setup

### Prerequisites

1. **Prometheus Operator** installed in cluster:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm install prometheus-operator prometheus-community/kube-prometheus-stack
   ```

2. **ServiceMonitor** label selector enabled:
   ```bash
   helm get values prometheus-operator | grep -A 5 "serviceMonitorSelectorNilUsesHelmValues"
   ```

### Installation

1. Apply the Kubernetes manifests:
   ```bash
   kubectl apply -f k8s/monitoring/servicemonitor-streaming.yaml
   ```

2. Verify ServiceMonitor is recognized:
   ```bash
   kubectl get servicemonitor -n default
   kubectl describe servicemonitor nova-streaming-monitor -n default
   ```

3. Verify Prometheus targets:
   ```bash
   # Port-forward to Prometheus
   kubectl port-forward -n default svc/prometheus-kube-prometheus-prometheus 9090:9090

   # Visit http://localhost:9090/targets
   # Look for "nova-streaming-monitor" in the list
   ```

### Configuration Details

**ServiceMonitor** (`servicemonitor-streaming.yaml`):
- **Scrape Interval**: 30 seconds
- **Scrape Timeout**: 10 seconds
- **Metrics Endpoint**: `/metrics` on user-service
- **Port**: 8081 (metrics)
- **Relabel Configs**: Add cluster, namespace, pod, service labels

---

## Grafana Dashboards

### Dashboard: Nova Streaming Metrics Dashboard

**File**: `k8s/monitoring/grafana-streaming-dashboard.json`

#### Panel 1: Active Streaming Sessions
- **Type**: Time Series (Line Graph)
- **Query**: `nova_streaming_active_streams`
- **X-Axis**: Time (last 1 hour)
- **Y-Axis**: Number of active streams
- **Purpose**: Monitor stream count trends
- **Alert Threshold**: Red if > 1000 concurrent streams (if overloaded)

#### Panel 2: Peak Viewers Distribution
- **Type**: Pie Chart
- **Query**: `sum(nova_streaming_peak_viewers) by (stream_id)`
- **Purpose**: Visual distribution of peak viewers across streams
- **Shows**: Which streams attract the most viewers

#### Panel 3: Current Viewer Count
- **Type**: Stat (Gauge)
- **Query**: `sum(nova_streaming_websocket_connections)`
- **Thresholds**:
  - Green: < 100 viewers
  - Yellow: 100-1000 viewers
  - Red: > 1000 viewers
- **Purpose**: Real-time total viewer count
- **Big Number Display**: Large, easy to read

#### Panel 4: Broadcast Error Rate
- **Type**: Time Series (Stacked Bars)
- **Query**: `rate(nova_streaming_broadcast_errors_total[5m])`
- **Group By**: `error_type`
- **X-Axis**: Time (last 1 hour)
- **Y-Axis**: Errors per second
- **Purpose**: Monitor error trends
- **Color Stack**: Different colors for each error type

#### Panel 5: RTMP Ingestion Latency
- **Type**: Time Series (Line Graph)
- **Query**: `histogram_quantile(0.95, rate(nova_streaming_rtmp_ingestion_latency_seconds_bucket[5m])) * 1000`
- **X-Axis**: Time (last 1 hour)
- **Y-Axis**: Latency (milliseconds)
- **Purpose**: Monitor RTMP ingestion performance
- **Acceptable Range**: < 100ms (p95)

### Importing Dashboard into Grafana

1. **Method 1: Direct JSON Upload**
   ```bash
   # Port-forward to Grafana
   kubectl port-forward -n default svc/prometheus-kube-prometheus-grafana 3000:80

   # Visit http://localhost:3000
   # Login with default credentials (admin/prom-operator)
   # Go to Dashboards → Import
   # Paste contents of grafana-streaming-dashboard.json
   ```

2. **Method 2: ConfigMap (GitOps)**
   ```bash
   kubectl create configmap grafana-streaming-dashboard \
     --from-file=k8s/monitoring/grafana-streaming-dashboard.json \
     -n default
   ```

---

## Alerting

### Alert Rules

**File**: `k8s/monitoring/servicemonitor-streaming.yaml` (PrometheusRule section)

#### 1. StreamingHighErrorRate
- **Condition**: Error rate > 10% for 5+ minutes
- **Severity**: warning
- **Action**: Review RTMP infrastructure, check for network issues

#### 2. StreamingPeakViewersHigh
- **Condition**: Peak viewers > 10000 for 2+ minutes
- **Severity**: warning
- **Action**: Scale horizontally, verify CDN capacity

#### 3. StreamingHighIngestionLatency
- **Condition**: p95 latency > 1.0 seconds for 3+ minutes
- **Severity**: warning
- **Action**: Check Nginx-RTMP performance, review network path

#### 4. StreamingNoActiveStreams
- **Condition**: No active streams in production for 10+ minutes
- **Severity**: info
- **Action**: Informational only - might be expected during off-hours

#### 5. StreamingWebSocketConnectionDrop
- **Condition**: Active stream has no connected viewers for 5+ minutes
- **Severity**: warning
- **Action**: Check WebSocket infrastructure, viewer connection issues

### Setting Up AlertManager

1. Create AlertManager config:
   ```yaml
   global:
     resolve_timeout: 5m

   route:
     receiver: 'default-receiver'
     group_by: ['alertname', 'cluster']
     group_wait: 30s
     group_interval: 5m
     repeat_interval: 12h

   receivers:
   - name: 'default-receiver'
     slack_configs:
     - api_url: 'YOUR_SLACK_WEBHOOK_URL'
       channel: '#streaming-alerts'
       title: 'Nova Streaming Alert'
   ```

2. Apply to cluster:
   ```bash
   kubectl apply -f alertmanager-config.yaml
   ```

---

## Recording Rules

**File**: `k8s/monitoring/servicemonitor-streaming.yaml` (Recording Rules section)

Recording rules pre-compute metric aggregations for faster dashboard queries.

### Rule 1: `nova:streaming:viewers:avg`
```
avg(nova_streaming_websocket_connections) by (region)
```
- **Purpose**: Average viewers per region
- **Update Interval**: 15 seconds
- **Use Case**: Regional performance comparison

### Rule 2: `nova:streaming:viewers:max`
```
max(nova_streaming_peak_viewers) by (region)
```
- **Purpose**: Peak viewers per region
- **Update Interval**: 15 seconds
- **Use Case**: Regional capacity planning

### Rule 3: `nova:streaming:duration:avg`
```
avg(rate(nova_streaming_stream_duration_seconds[5m])) by (stream_type)
```
- **Purpose**: Average stream duration by type
- **Update Interval**: 15 seconds
- **Use Case**: Stream patterns analysis

### Rule 4: `nova:streaming:error_rate:5m`
```
rate(nova_streaming_broadcast_errors_total[5m])
```
- **Purpose**: 5-minute error rate
- **Update Interval**: 15 seconds
- **Use Case**: Real-time error monitoring

### Rule 5: `nova:streaming:active:by_region`
```
sum(nova_streaming_active_streams) by (region)
```
- **Purpose**: Active streams by region
- **Update Interval**: 15 seconds
- **Use Case**: Regional stream distribution

---

## Operational Procedures

### 1. Viewing Metrics in Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n default svc/prometheus-kube-prometheus-prometheus 9090:9090

# Visit http://localhost:9090

# Example queries:
# - nova_streaming_active_streams{region="us-west-2"}
# - rate(nova_streaming_broadcast_errors_total[5m])
# - histogram_quantile(0.95, nova_streaming_rtmp_ingestion_latency_seconds_bucket)
```

### 2. Viewing Metrics in Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n default svc/prometheus-kube-prometheus-grafana 3000:80

# Visit http://localhost:3000
# Login with default credentials
# Select "Nova Streaming Metrics Dashboard" from dashboards list
```

### 3. Troubleshooting Missing Metrics

1. **Check ServiceMonitor is properly configured:**
   ```bash
   kubectl describe servicemonitor nova-streaming-monitor -n default
   ```

2. **Verify user-service is running and metrics endpoint is accessible:**
   ```bash
   kubectl port-forward -n default svc/user-service 8081:8081
   curl http://localhost:8081/metrics | head -50
   ```

3. **Check Prometheus targets:**
   ```
   Prometheus UI → Status → Targets
   Look for "nova-streaming-monitor" status (should be "UP")
   ```

4. **Verify PrometheusRule is loaded:**
   ```bash
   kubectl get prometheusrule -n default
   kubectl describe prometheusrule nova-streaming-alerts -n default
   ```

### 4. Metrics Retention

Default Prometheus retention policy:
- **Retention Period**: 24 hours (configurable)
- **Storage Size**: ~GB per day (depends on cardinality)

To change retention:
```bash
kubectl patch prometheus prometheus-kube-prometheus-prometheus \
  -p '{"spec":{"retention":"7d"}}'
```

### 5. Metric Cardinality Considerations

High-cardinality labels (stream_id) can cause performance issues:
- **Concern**: Too many unique stream_ids create too many time series
- **Mitigation**: Implement cardinality caps or use recording rules
- **Example**: Don't create separate metric per stream_id indefinitely

---

## Integration Checklist

- [ ] Deploy Prometheus Operator in cluster
- [ ] Apply ServiceMonitor manifest
- [ ] Verify Prometheus targets are healthy
- [ ] Deploy Grafana dashboard JSON
- [ ] Test all dashboard panels show data
- [ ] Configure AlertManager receivers
- [ ] Test alert firing/routing
- [ ] Document alert runbook for team
- [ ] Set up on-call rotation with alerts
- [ ] Monitor metric cardinality over time
- [ ] Plan retention policy based on storage
- [ ] Document custom queries team uses

---

## Performance Considerations

### Cardinality
- **Stream ID Label**: Unbounded, grows with stream count
- **Error Type Label**: Bounded (~5-10 types)
- **Region Label**: Bounded (~5-10 regions)
- **Quality Label**: Bounded (~3-4 types)

### Query Optimization
- Use recording rules instead of complex queries on dashboards
- Aggregate by region rather than stream_id when possible
- Use appropriate time ranges (shorter = more detailed but slower)

### Monitoring the Monitor
- Set up alerts on Prometheus itself (scrape success rate)
- Monitor AlertManager delivery success
- Track Prometheus storage usage over time

---

## References

- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboarding Guide](https://grafana.com/docs/grafana/latest/dashboards/)
- [PromQL Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Kubernetes Monitoring with Prometheus](https://kubernetes.io/docs/tasks/debug-application-cluster/resource-metrics-pipeline/)

