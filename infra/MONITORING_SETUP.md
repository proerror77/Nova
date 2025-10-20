# Phase 3 Feed System - Monitoring Setup Guide

## Overview

This guide provides complete instructions for setting up monitoring for the Phase 3 Real-time Personalized Feed Ranking System using Prometheus and Grafana.

**Components:**
- **Prometheus**: Time-series metrics collection and alerting
- **Grafana**: Visualization and dashboarding
- **Alertmanager**: Alert routing and notifications

## Prerequisites

- Docker & Docker Compose (for containerized deployment)
- OR Manual installation of Prometheus v2.40+, Grafana v9.0+
- ClickHouse instance for metrics storage (optional, for long-term storage)
- Email or Slack configured for alert notifications

## Quick Start (Docker Compose)

### 1. Directory Structure

```bash
infra/
├── prometheus/
│   ├── prometheus.yml          # Prometheus configuration
│   ├── rules.yml               # Alert & recording rules
│   └── alertmanager.yml        # Alertmanager config
├── grafana/
│   ├── dashboards/             # Dashboard JSON definitions
│   │   ├── feed-system-overview.json
│   │   ├── data-pipeline.json
│   │   └── ranking-quality.json
│   └── provisioning/
│       ├── dashboards.yml      # Dashboard provisioning
│       └── datasources.yml     # Datasource config
└── docker-compose.monitoring.yml
```

### 2. Start Monitoring Stack

```bash
cd infra/
docker-compose -f docker-compose.monitoring.yml up -d
```

This will start:
- **Prometheus** on http://localhost:9090
- **Grafana** on http://localhost:3000
- **Alertmanager** on http://localhost:9093

### 3. Initial Grafana Setup

1. Login to Grafana: http://localhost:3000
   - Default: admin / admin
   - Change password on first login

2. Dashboards auto-import from `/var/lib/grafana/dashboards/`

3. Verify data flow:
   - Go to **Configuration > Data Sources**
   - Click "Prometheus" → "Save & Test"
   - Should show "Data source is working"

## Prometheus Configuration

### prometheus.yml

```yaml
global:
  scrape_interval: 30s        # Collect metrics every 30s
  evaluation_interval: 30s    # Evaluate rules every 30s
  external_labels:
    cluster: 'nova-prod'
    env: 'production'

scrape_configs:
  # Nova Feed Service Metrics
  - job_name: 'feed-service'
    static_configs:
      - targets: ['localhost:8000']  # Feed service /metrics endpoint
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # ClickHouse Metrics (if using native exporter)
  - job_name: 'clickhouse'
    static_configs:
      - targets: ['localhost:9363']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # Redis Metrics (if using redis_exporter)
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # Kafka Metrics (if using kafka_exporter)
  - job_name: 'kafka'
    static_configs:
      - targets: ['localhost:9308']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - /etc/prometheus/rules.yml
```

### Metrics Exported by Feed Service

The feed service (`main.rs`) exports these metrics on `/metrics`:

```
# HELP feed_api_requests_total Total HTTP requests
# TYPE feed_api_requests_total counter
feed_api_requests_total{method="GET",path="/api/v1/feed",status="200"} 12345

# HELP feed_api_duration_seconds Request latency in seconds
# TYPE feed_api_duration_seconds histogram
feed_api_duration_seconds_bucket{le="0.05"} 1000
feed_api_duration_seconds_bucket{le="0.1"} 1500
feed_api_duration_seconds_bucket{le="0.5"} 1900
feed_api_duration_seconds_bucket{le="1"} 2000
feed_api_duration_seconds_bucket{le="+Inf"} 2000

# HELP feed_cache_hits_total Cache hit count
# TYPE feed_cache_hits_total counter
feed_cache_hits_total 8500

# HELP feed_cache_misses_total Cache miss count
# TYPE feed_cache_misses_total counter
feed_cache_misses_total 1500

# HELP circuit_breaker_state Current state (0=Closed, 1=HalfOpen, 2=Open)
# TYPE circuit_breaker_state gauge
circuit_breaker_state{datasource="clickhouse"} 0

# HELP events_received_total Total events received
# TYPE events_received_total counter
events_received_total 50000

# HELP cdc_messages_processed_total CDC messages processed
# TYPE cdc_messages_processed_total counter
cdc_messages_processed_total{table="posts"} 5000
```

## Alert Rules

### Critical Alerts (Immediate Action Required)

1. **FeedAPILatencyP95High** - P95 latency exceeds 800ms
   - Impact: User experience degradation
   - Action: Check ClickHouse performance, consider fallback
   - Runbook: See docs/operations/runbook.md

2. **CircuitBreakerOpen** - ClickHouse is unavailable
   - Impact: Feed API using PostgreSQL fallback (slower, limited)
   - Action: Check ClickHouse cluster health
   - Runbook: Restart ClickHouse or failover to replica

3. **ClickHouseInsertErrors** - Data insertion failures detected
   - Impact: Data loss risk for new events/CDC changes
   - Action: Check ClickHouse replication, disk space
   - Runbook: Verify ClickHouse cluster state

4. **FeedSystemAvailabilityLow** - Availability below 99.5% SLO
   - Impact: Service degradation at scale
   - Action: Full incident response required
   - Runbook: Check all components systematically

### Warning Alerts (Proactive Attention)

1. **FeedAPICacheHitRateLow** - Cache hit rate below 85%
   - Action: Increase cache TTL or check for cache invalidation issues

2. **EventConsumerLagHigh** - Events consumer 100k+ messages behind
   - Action: Check Events consumer health, may need horizontal scaling

3. **CDCConsumerLagHigh** - CDC consumer 50k+ messages behind
   - Action: Check CDC consumer, investigate PostgreSQL replication

4. **RedisCacheMemoryHigh** - Redis memory usage exceeds 85%
   - Action: Increase Redis memory or reduce cache TTL

## Dashboard Descriptions

### 1. Feed System Overview (feed-system-overview.json)

**Purpose**: High-level system health at a glance

**Panels**:
- Feed API Request Rate: Load monitoring
- Feed API Latency (P50, P95, P99): Performance SLO tracking
- Cache Hit Rate %: Cache efficiency (target: >90%)
- Circuit Breaker Status: ClickHouse availability
- System Availability %: Overall SLO compliance
- Error Rate: Issue detection
- Event-to-Visible Latency P95: End-to-end freshness
- Events Processed: Pipeline throughput

**SLO Targets**:
- Feed API P95 ≤150ms (cache) / ≤800ms (ClickHouse)
- Cache hit rate ≥90%
- System availability ≥99.5%
- Event-to-visible P95 ≤5s

### 2. Data Pipeline & Event Processing (data-pipeline.json)

**Purpose**: Deep dive into CDC and Events consumers

**Panels**:
- CDC/Events Consumer Lag: Detect pipeline backlog
- Messages Processed: Throughput monitoring
- ClickHouse Insert Throughput: Data ingestion rate
- Query Latency: ClickHouse performance
- Processing Latency: End-to-end consumer latency
- Data Loss Events: Failure tracking (target: 0)
- Duplicate Events: Dedup effectiveness
- Consumer Group Status: Partition-level metrics

**Monitoring Points**:
- Consumer lag <10s at P95 (target)
- 0 duplicate events (perfect dedup)
- 0 data loss events (exactly-once semantics)

### 3. Feed Ranking Quality (ranking-quality.json)

**Purpose**: Algorithm performance and data quality

**Panels**:
- Freshness/Engagement/Affinity Components: Weight distribution
- Final Ranking Score: Distribution of scores across feed
- Posts Deduplicated %: Dedup rate (target: >99%)
- Posts Removed by Saturation %: Author diversity control
- Candidate Set Sizes: Algorithm scaling
- Top 1000 Users Feed Cache: Warmer effectiveness
- Cache Warm Success %: Reliability
- Fallback Ratio: Circuit breaker usage

**Data Quality Checks**:
- Dedup rate >99% (prevent repeats)
- Saturation ratio 15-25% (author diversity)
- Fallback ratio <5% (ClickHouse health)

## Alertmanager Configuration

### alertmanager.yml

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'team-slack'
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

  routes:
    - match:
        severity: critical
      receiver: 'team-pagerduty'
      group_wait: 0s

    - match:
        severity: warning
      receiver: 'team-slack'

receivers:
  - name: 'team-slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#nova-alerts'
        title: 'Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'team-pagerduty'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
        description: '{{ .GroupLabels.alertname }}'
```

## Verification Checklist

After deployment, verify:

- [ ] Prometheus scraping metrics from feed service `/metrics` endpoint
- [ ] Grafana dashboards show data (not "No data")
- [ ] Alerts are being evaluated (check Prometheus `/alerts`)
- [ ] Test alert by manually triggering: `curl localhost:9090/api/v1/query?query=up`
- [ ] Alertmanager routing to Slack/PagerDuty
- [ ] Dashboard auto-refresh every 30s
- [ ] Historical data retention minimum 30 days

## Performance Tuning

### Prometheus Optimization

```yaml
# Increase retention for long-term analysis
--storage.tsdb.retention.time=30d

# Adjust WAL for throughput
--storage.tsdb.retention.size=50GB

# Max samples per second
--storage.tsdb.max-samples=1000000
```

### Grafana Optimization

```json
{
  "refresh": "30s",
  "panels": [
    {
      "maxDataPoints": 1000,
      "intervalFactor": 1
    }
  ]
}
```

## Troubleshooting

### No Metrics Appearing in Grafana

1. **Check Prometheus scrape success:**
   ```bash
   curl http://localhost:9090/api/v1/query?query=up
   # Should return value 1 for all targets
   ```

2. **Verify feed service is exporting metrics:**
   ```bash
   curl http://localhost:8000/metrics | head -20
   ```

3. **Check Prometheus targets:**
   - Visit http://localhost:9090/targets
   - Verify `feed-service` shows "UP"

### High Latency / Slow Dashboard Load

1. **Reduce query time range** (use 1h instead of 24h for live dashboard)
2. **Increase Prometheus `max_samples_limit`**
3. **Add dedicated ClickHouse backend for long-term storage**

### Alerts Not Firing

1. **Verify Prometheus rules are loaded:**
   ```bash
   curl http://localhost:9090/api/v1/rules | jq .
   ```

2. **Check alert state:**
   ```bash
   curl 'http://localhost:9090/api/v1/query?query=ALERTS'
   ```

3. **Verify Alertmanager is receiving alerts:**
   ```bash
   curl http://localhost:9093/api/v1/alerts
   ```

## Integration with ClickHouse (Optional)

For long-term metrics storage in ClickHouse:

```sql
CREATE TABLE nova.prometheus_metrics (
    timestamp DateTime,
    metric_name String,
    labels Map(String, String),
    value Float64
) ENGINE = MergeTree()
ORDER BY (timestamp, metric_name)
TTL timestamp + INTERVAL 90 DAY;
```

Use remote storage adapter:
```bash
docker run -p 9009:9009 -v /path/to/config.yml:/config.yml \
  prom/remote-storage-adapter /config.yml
```

## Maintenance

### Weekly Tasks

- [ ] Review alert history for patterns
- [ ] Check for any errors in Prometheus logs
- [ ] Verify data retention isn't hitting size limits

### Monthly Tasks

- [ ] Tune alert thresholds based on actual traffic
- [ ] Archive old dashboards
- [ ] Test failover procedures
- [ ] Review SLO compliance metrics

## Support & References

- **Prometheus Docs**: https://prometheus.io/docs/
- **Grafana Docs**: https://grafana.com/docs/
- **Alerting Best Practices**: https://prometheus.io/docs/practices/alerting/
- **Dashboard JSON Schema**: https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/manage-dashboards/#dashboard-json-schema

---

**Last Updated**: 2024
**Maintained By**: Nova Infrastructure Team
