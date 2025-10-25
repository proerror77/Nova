# Prometheus Monitoring and Alerting System

## Overview

Complete observability solution for Nova platform with real-time metrics collection, alerting, and historical data storage.

**Key Components:**
- **Prometheus** - Time-series database for metrics
- **AlertManager** - Alert routing and notification
- **Grafana** - Dashboards and visualization
- **Custom metrics** - Application-specific instrumentation

## Architecture

```
Applications
    ↓
Prometheus metrics endpoints (/metrics)
    ↓
Prometheus Server (scrapes every 15 seconds)
    ↓
TSDB (time-series storage)
    ↓
┌─────────────────────────────────────────┐
│  Rules Engine (evaluates every 15s)    │
├─────────────────────────────────────────┤
│  Alert Rules → AlertManager → Channels  │
│  Recording Rules → Grafana Dashboards   │
└─────────────────────────────────────────┘
```

## Metrics Categories

### 1. WebSocket Metrics

**Connection Lifecycle:**
```
ws_connections_total{status="opened|closed|error"}
  ↓ Count of total connections
  ↓ Breakdown by success/failure
  ↓ Alerts when error rate > 15%
```

**Message Flow:**
```
ws_messages_sent_total{message_type="message|typing|ping|pong"}
ws_messages_received_total{message_type="..."}
  ↓ Messages per type
  ↓ Throughput measurement
  ↓ Alerts on high error rate
```

**Error Tracking:**
```
ws_errors_total{error_type="timeout|decode|send_failed|connection_lost"}
  ↓ Error categorization
  ↓ Trend analysis
  ↓ Root cause identification
```

**Reconnection Intelligence:**
```
ws_reconnections_total{reason="connection_lost|heartbeat_timeout"}
  ↓ Reconnection frequency
  ↓ Reason analysis
  ↓ Alerts on high reconnection rate (>10/min)
```

**Latency:**
```
ws_message_latency_seconds{message_type="message|typing"}
  ↓ Histogram: 1ms, 5ms, 10ms, 50ms, 100ms, 500ms, 1s, 5s
  ↓ Percentiles: p50, p95, p99
  ↓ Alerts when p95 > 5s
```

**Current State:**
```
ws_active_connections{conversation_id}
  ↓ Gauge of live connections per conversation
  ↓ Scaling analysis
  ↓ Connection pool planning
```

### 2. Messaging Metrics

**API Operations:**
```
messages_sent_total{status="success|failed"}
messages_received_total{status="success|failed"}
message_delivery_failures_total{error_type="network|timeout|invalid|other"}
conversations_created_total{status="success|failed"}
  ↓ Operation success rates
  ↓ Error categorization
  ↓ SLA tracking
```

**Search Functionality:**
```
message_searches_total{index_type="fulltext|bm25", status="success|failed"}
message_search_latency_seconds{index_type="..."}
  ↓ Search performance
  ↓ Index health
  ↓ Alerts on latency > 2s
```

**Queue Management:**
```
message_queue_depth{queue_type="pending|failed|retry"}
  ↓ Messages awaiting delivery
  ↓ Failed message backlog
  ↓ Retry queue size
  ↓ Alerts when pending > 1000 or failed > 500
```

**Delivery SLA:**
```
message_delivery_latency_seconds{delivery_type="direct|queue|broadcast"}
  ↓ Time from send to broadcast
  ↓ SLA compliance
  ↓ Alerts when p95 > 500ms
```

### 3. API Latency Metrics

```
message_api_latency_seconds{endpoint="send|receive|list|search"}
  ↓ REST API performance
  ↓ Endpoint-specific tracking
  ↓ Database query performance
  ↓ Alerts when p99 > 1s
```

## Alert Severity Levels

### Critical (Immediate Action)
- `CriticalWebSocketErrorRate` - >15% error rate
- `CriticalMessageDeliveryFailure` - >10% message failures
- `FailedMessageQueueCritical` - >500 failed messages
- `ServiceDown` - Service unreachable
- `PersistentHighErrorRate` - Sustained system errors

**Response Time:** < 5 minutes
**Escalation:** Page on-call engineer

### Warning (Investigate within 1 hour)
- `HighWebSocketErrorRate` - >5% error rate
- `HighWebSocketReconnectionRate` - >10/min reconnections
- `WebSocketConnectionTimeoutExceeded` - P95 latency > 5s
- `HighMessageDeliveryFailureRate` - >2% message failures
- `MessageQueueBacklog` - >1000 pending messages
- `HighMessageSearchLatency` - P95 > 2s
- `ConversationCreationFailure` - >5% failure rate

**Response Time:** < 1 hour
**Investigation:** Check logs and metrics dashboard

### Info (Monitoring)
- `IdleConversationsTooHigh` - >90% idle
- `WebSocketHeartbeatFailures` - Elevated timeouts
- `MessageSearchFailures` - Search errors detected

**Response Time:** Next business day
**Action:** Trend analysis and optimization

## Setting Up Prometheus

### Docker Compose (Recommended)

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus.rules.yml:/etc/prometheus/rules/prometheus.rules.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'

  alertmanager:
    image: prom/alertmanager:latest
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager_data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - prometheus

volumes:
  prometheus_data:
  alertmanager_data:
  grafana_data:
```

### Kubernetes Deployment

Use Prometheus Operator:

```bash
# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# Create ServiceMonitor for Nova services
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nova-services
spec:
  selector:
    matchLabels:
      app: nova
  endpoints:
  - port: metrics
    interval: 15s
EOF
```

## Dashboard Setup

### Grafana Dashboards

**Navigation:** Grafana (port 3000) → Dashboards → Create New

#### Dashboard 1: System Overview
- Top: Service health (up/down indicators)
- WebSocket connections (current/peak)
- Message throughput (msgs/sec)
- Error rate (%)
- Queue depths

#### Dashboard 2: WebSocket Health
- Connection states (pie chart)
- Message latency (p50, p95, p99)
- Reconnection frequency
- Error breakdown (pie chart)
- Heartbeat failures

#### Dashboard 3: Messaging Performance
- Message delivery rate
- Search latency by index type
- Queue backlog (pending/failed/retry)
- Conversation creation success rate
- API endpoint latencies

#### Dashboard 4: Error Analysis
- Error rate trend (multi-service)
- Error type breakdown
- Failed message queue depth
- Top error sources
- Error correlation matrix

## Querying Metrics

### Prometheus Web UI

Access at `http://localhost:9090`

**Basic Queries:**

```promql
# Current WebSocket connections
ws_active_connections

# Message delivery success rate
rate(messages_sent_total{status="success"}[5m])

# WebSocket error rate
rate(ws_errors_total[5m]) / rate(ws_messages_sent_total[5m])

# Message search latency P95
histogram_quantile(0.95, rate(message_search_latency_seconds_bucket[5m]))

# Current queue backlog
message_queue_depth{queue_type="pending"}

# Total reconnections in last hour
increase(ws_reconnections_total[1h])
```

**Advanced Queries:**

```promql
# WebSocket connections with throughput
ws_active_connections * rate(ws_messages_sent_total[5m])

# Error rate by service
sum(rate(ws_errors_total[5m])) by (service)

# Latency breakdown
histogram_quantile(0.99, rate(message_api_latency_seconds_bucket[5m]))
- histogram_quantile(0.50, rate(message_api_latency_seconds_bucket[5m]))

# Failed message queue trend
delta(message_queue_depth{queue_type="failed"}[1h])
```

## Alerting Configuration

### AlertManager Setup

Create `alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      continue: true
    - match:
        severity: warning
      receiver: 'warning'

receivers:
  - name: 'default'
    # Webhook, email, etc.

  - name: 'critical'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_CRITICAL}'
        channel: '#alerts-critical'
        title: '[CRITICAL] {{ .GroupLabels.alertname }}'

  - name: 'warning'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_WARNING}'
        channel: '#alerts-warning'
```

## Performance Tuning

### Scrape Interval Strategy

```
Fast metrics (system, WebSocket):
  scrape_interval: 10s - 15s

Medium metrics (API, database):
  scrape_interval: 30s

Slow metrics (business analytics):
  scrape_interval: 60s
```

### Storage Optimization

```bash
# Default retention
--storage.tsdb.retention.time=30d

# For long-term storage, use remote write
remote_write:
  - url: "http://long-term-storage:9009/api/v1/push"
```

### Scaling Considerations

**Single Server (< 1M samples/sec):**
- Local disk storage
- Basic Grafana dashboards
- Self-hosted AlertManager

**Distributed (> 1M samples/sec):**
- Remote storage (InfluxDB, S3, etc.)
- Prometheus federation
- Multiple AlertManager replicas
- Distributed Grafana setup

## Recording Rules

Pre-compute expensive queries for dashboards:

```yaml
groups:
  - name: "high-cardinality"
    interval: 1m
    rules:
      # Pre-compute message delivery rates
      - record: 'message:delivery:success_rate:5m'
        expr: |
          rate(messages_sent_total{status="success"}[5m])

      # Pre-compute search latency percentiles
      - record: 'message_search:p95_latency:5m'
        expr: |
          histogram_quantile(0.95, rate(message_search_latency_seconds_bucket[5m]))
```

## Troubleshooting

### High Memory Usage
```
1. Check cardinality (Prometheus UI → Status → TSDB Status)
2. Reduce retention period: --storage.tsdb.retention.time=7d
3. Implement metric relabeling to drop unnecessary labels
4. Use recording rules to pre-compute expensive queries
```

### Missing Metrics
```
1. Verify scrape configuration: Prometheus UI → Status → Targets
2. Check /metrics endpoint availability: curl http://service:port/metrics
3. Verify metric names in application code
4. Check Prometheus logs: docker logs prometheus
```

### False Positive Alerts
```
1. Adjust alert threshold based on baseline
2. Increase `for` duration (2m → 5m)
3. Add severity labels to filter noise
4. Implement metric smoothing with moving averages
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
- name: Check Prometheus Rules
  run: |
    docker run --rm \
      -v $PWD/prometheus.rules.yml:/etc/prometheus/prometheus.rules.yml \
      prom/prometheus:latest \
      promtool check rules /etc/prometheus/prometheus.rules.yml
```

### Pre-deployment Validation

```bash
# Validate Prometheus config
promtool check config prometheus.yml

# Validate alert rules
promtool check rules prometheus.rules.yml

# Test alert expressions
promtool query instant http://prometheus:9090 'ws_errors_total'
```

## Best Practices

1. **Label Strategy**
   - Keep cardinality low (< 100 unique label combinations per metric)
   - Use consistent label names across services
   - Avoid high-cardinality labels (user_id, message_id)

2. **Metric Naming**
   - Follow Prometheus convention: `<namespace>_<subsystem>_<name>_<unit>`
   - Example: `message_api_latency_seconds`

3. **Alert Design**
   - Alert on business SLOs, not low-level metrics
   - Use multiple conditions for critical alerts
   - Include runbook links in annotations

4. **Recording Rules**
   - Pre-compute expensive aggregations
   - Use for dashboards that refresh frequently
   - Update interval: 1m - 5m

5. **Data Retention**
   - Keep recent data local (high resolution)
   - Archive old data to long-term storage
   - Balance cost vs. retention needs

## Related Documentation

- **ERROR_HANDLING.md** - Frontend error tracking integration
- **WEBSOCKET_RECONNECTION.md** - WebSocket metrics explanation
- **Performance Tuning Guide** - Query optimization
- **Runbook Collection** - Alert response procedures

## Dashboard Examples

See `/grafana/dashboards/` for:
- `websocket-health.json` - Real-time connection monitoring
- `message-delivery.json` - Message throughput and latency
- `system-overview.json` - Service health overview
- `error-analysis.json` - Error trend analysis

## Summary

This monitoring system provides:

✅ **Real-time visibility** - 15-second resolution
✅ **Proactive alerting** - Before users notice issues
✅ **Root cause analysis** - Rich context in metrics
✅ **SLA tracking** - Delivery guarantees
✅ **Capacity planning** - Historical trends
✅ **Cost optimization** - Identify inefficiencies

The metrics bridge the gap between application instrumentation and operational visibility.
