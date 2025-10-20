# Grafana Dashboards Setup for Baseline Collection
## Monitoring Infrastructure for 24-Hour Video Ranking Baseline (2025-10-20)

**Purpose**: Configure Grafana dashboards to monitor baseline collection metrics
**Timeline**: Setup by 2025-10-20 08:00 UTC (2 hours before collection starts)
**Owner**: Ops / Monitoring Team
**Duration**: ~60 minutes

---

## 📊 Dashboard Overview

### Required Dashboards (4 total)

| # | Dashboard | Purpose | Refresh | Data Source |
|---|-----------|---------|---------|-------------|
| 1 | System Health & Resources | CPU, Memory, Pod Status | 15s | Prometheus |
| 2 | API Performance & Latency | P50/P95/P99, Throughput, Errors | 10s | Prometheus |
| 3 | Cache Performance | Hit Rate, TTL Efficiency, Size | 15s | Prometheus |
| 4 | Business Metrics | User Engagement, Feed Generation | 30s | Prometheus/ClickHouse |

---

## 🔧 Dashboard 1: System Health & Resources

### Purpose
Monitor infrastructure resource consumption and pod health during baseline collection

### Setup Instructions

#### 1.1 Create Dashboard
```bash
# Option A: Via Grafana UI
1. Grafana > + Create > Dashboard
2. Name: "Video Ranking - System Health"
3. Tags: ["baseline", "video-ranking", "staging"]
4. Save

# Option B: Via API
curl -X POST http://grafana:3000/api/dashboards/db \
  -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- << 'EOF'
{
  "dashboard": {
    "title": "Video Ranking - System Health",
    "tags": ["baseline", "video-ranking", "staging"],
    "timezone": "utc",
    "refresh": "15s"
  }
}
EOF
```

#### 1.2 Add Panels

**Panel 1: Pod CPU Usage**
```
Title: Pod CPU Usage (millicores)
Type: Graph / Time Series
Metrics:
  - sum(rate(container_cpu_usage_seconds_total{pod=~"video-ranking.*"}[5m])) * 1000
Legend: {{pod}}
Y-axis: millicores
Thresholds: warning 200, critical 500
```

**Panel 2: Pod Memory Usage**
```
Title: Pod Memory Usage (MB)
Type: Graph / Time Series
Metrics:
  - sum(container_memory_usage_bytes{pod=~"video-ranking.*"}) / 1024 / 1024
Legend: {{pod}}
Y-axis: MB
Thresholds: warning 512, critical 1024
```

**Panel 3: Pod Restart Count**
```
Title: Pod Restarts
Type: Stat / Gauge
Metrics:
  - max(kube_pod_container_status_restarts_total{pod=~"video-ranking.*"})
Legend: Restarts
Threshold: critical 1 (any restart is critical during baseline)
```

**Panel 4: Replica Count**
```
Title: Active Replicas
Type: Stat
Metrics:
  - count(kube_pod_info{pod=~"video-ranking.*"})
Legend: Replicas
Target: 3 replicas minimum
```

**Panel 5: Node CPU Available**
```
Title: Node CPU Capacity (%)
Type: Gauge
Metrics:
  - (1 - (sum(rate(node_cpu_seconds_total{mode="idle"}[5m])) / count(node_cpu_seconds_total{mode="idle"}))) * 100
Legend: CPU %
Thresholds: warning 70, critical 85
```

**Panel 6: Node Memory Available**
```
Title: Node Memory Available (GB)
Type: Graph
Metrics:
  - (node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024
Legend: {{node}}
Thresholds: warning 5, critical 2
```

**Panel 7: Disk I/O**
```
Title: Disk I/O Operations
Type: Graph
Metrics:
  - rate(node_disk_io_time_ms_total[5m])
Legend: {{device}}
Y-axis: ms/sec
```

---

## 🚀 Dashboard 2: API Performance & Latency

### Purpose
Track real-time API performance metrics during baseline

### Setup Instructions

#### 2.1 Create Dashboard
```bash
# Grafana UI:
1. + Create > Dashboard
2. Name: "Video Ranking - API Performance"
3. Tags: ["baseline", "api", "video-ranking"]
4. Save
```

#### 2.2 Add Panels

**Panel 1: Request Rate (RPS)**
```
Title: Requests Per Second
Type: Graph
Metrics:
  - sum(rate(http_requests_total{handler=~"reels.*"}[1m]))
Legend: {{handler}}
Y-axis: req/sec
Alert: <50 is warning (production typically 100+)
```

**Panel 2: Latency - P50/P95/P99**
```
Title: API Latency Distribution
Type: Graph with Multiple Lines
Metrics:
  - histogram_quantile(0.50, rate(http_request_duration_seconds_bucket{handler=~"reels.*"}[1m])) * 1000
  - histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{handler=~"reels.*"}[1m])) * 1000
  - histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{handler=~"reels.*"}[1m])) * 1000
Legend: P50, P95, P99
Y-axis: ms
Thresholds:
  - P50: target <50ms
  - P95: target <100ms
  - P99: target <300ms
```

**Panel 3: Error Rate**
```
Title: HTTP Error Rate (%)
Type: Graph
Metrics:
  - (sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m]))) * 100
Legend: Error %
Y-axis: percent
Thresholds: warning 0.5%, critical 1%
```

**Panel 4: Endpoint-Specific Latency**
```
Title: Latency by Endpoint
Type: Table
Metrics (one row per endpoint):
  - GET /api/v1/reels: histogram_quantile(0.95, ...)
  - GET /api/v1/reels/search: histogram_quantile(0.95, ...)
  - POST /api/v1/reels/{id}/like: histogram_quantile(0.95, ...)
  - [etc for all 11 endpoints]
Sort by: Latency descending
```

**Panel 5: Request Duration Heatmap**
```
Title: Latency Heatmap
Type: Heatmap
Metrics:
  - histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{handler=~"reels.*"}[1m]))
X-axis: Time
Y-axis: Latency buckets
Shows distribution patterns
```

**Panel 6: Timeout Tracking**
```
Title: Request Timeouts
Type: Stat
Metrics:
  - sum(increase(http_request_timeout_total[5m]))
Legend: Timeouts/5min
Alert: Any timeout is critical
```

---

## 💾 Dashboard 3: Cache Performance

### Purpose
Monitor cache efficiency and Redis behavior during baseline

### Setup Instructions

#### 3.1 Create Dashboard
```bash
# Grafana UI:
1. + Create > Dashboard
2. Name: "Video Ranking - Cache Performance"
3. Tags: ["baseline", "cache", "video-ranking"]
4. Save
```

#### 3.2 Add Panels

**Panel 1: Cache Hit Rate (%)**
```
Title: Cache Hit Rate
Type: Graph with Threshold
Metrics:
  - (sum(rate(cache_hits_total[1m])) / (sum(rate(cache_hits_total[1m])) + sum(rate(cache_misses_total[1m])))) * 100
Legend: Hit Rate %
Y-axis: percent (0-100)
Thresholds: warning 85%, target 95%+
Target Line: 95%
```

**Panel 2: Cache Hits vs Misses**
```
Title: Cache Operations
Type: Stacked Area Graph
Metrics:
  - sum(rate(cache_hits_total[1m]))   [Hits]
  - sum(rate(cache_misses_total[1m])) [Misses]
Legend: Hits, Misses
Y-axis: ops/sec
```

**Panel 3: Redis Memory Usage**
```
Title: Redis Memory
Type: Graph
Metrics:
  - redis_memory_used_bytes / 1024 / 1024  [Used MB]
  - redis_memory_max_bytes / 1024 / 1024   [Max MB]
Legend: Used, Max
Y-axis: MB
Alert: >512MB is warning
```

**Panel 4: Cache Eviction Rate**
```
Title: Cache Evictions
Type: Stat / Counter
Metrics:
  - sum(increase(redis_evicted_keys_total[5m]))
Legend: Evictions/5min
Alert: >100 evictions is warning (cache too small)
```

**Panel 5: Redis Key Count**
```
Title: Keys in Cache
Type: Graph
Metrics:
  - redis_db_keys{db="0"}
Legend: Keys
Y-axis: count
Target: Should grow during Phase 1, stabilize in Phase 2
```

**Panel 6: Cache TTL Histogram**
```
Title: Key TTL Distribution
Type: Heatmap
Metrics: Redis key expiration data
Shows: How many keys at each TTL level
Useful for: Identifying eviction patterns
```

**Panel 7: Cache Size**
```
Title: Cache Size by Category
Type: Pie Chart
Metrics:
  - sum(cache_size_bytes{category="feed"})
  - sum(cache_size_bytes{category="trending"})
  - sum(cache_size_bytes{category="search"})
Legend: Feed Cache, Trending Cache, Search Cache
```

---

## 📈 Dashboard 4: Business Metrics

### Purpose
Track application-level metrics and business impact during baseline

### Setup Instructions

#### 4.1 Create Dashboard
```bash
# Grafana UI:
1. + Create > Dashboard
2. Name: "Video Ranking - Business Metrics"
3. Tags: ["baseline", "business", "video-ranking"]
4. Save
```

#### 4.2 Add Panels

**Panel 1: Feed Requests (Daily)**
```
Title: Feed Requests per Day
Type: Stat / Counter
Metrics:
  - sum(increase(feed_requests_total[24h]))
Legend: Requests/day
Expected: 10,000 - 100,000 (depends on user base)
```

**Panel 2: Engagement Rate**
```
Title: Engagement Actions
Type: Graph (Stacked)
Metrics:
  - sum(rate(engagement_likes_total[1m]))     [Likes]
  - sum(rate(engagement_shares_total[1m]))    [Shares]
  - sum(rate(engagement_watches_total[1m]))   [Watches]
  - sum(rate(engagement_comments_total[1m]))  [Comments]
Y-axis: actions/sec
```

**Panel 3: Video Ranking Score Distribution**
```
Title: Ranking Score Statistics
Type: Graph / Gauge
Metrics:
  - histogram_quantile(0.50, ranking_score) [P50]
  - histogram_quantile(0.95, ranking_score) [P95]
  - histogram_quantile(0.99, ranking_score) [P99]
Shows: How scores are distributed
```

**Panel 4: Feed Generation Time**
```
Title: Feed Generation Duration
Type: Graph
Metrics:
  - histogram_quantile(0.95, feed_generation_seconds_bucket) * 1000
Legend: P95 Duration
Y-axis: ms
Target: <5000ms (5 seconds)
```

**Panel 5: Search Volume**
```
Title: Search Queries
Type: Stat / Counter
Metrics:
  - sum(increase(search_queries_total[1h]))
Legend: Searches/hour
```

**Panel 6: Creator Recommendations**
```
Title: Recommendation Requests
Type: Graph
Metrics:
  - sum(rate(recommendations_total[1m]))
Legend: Recs/sec
Shows: User interest in creator recommendations
```

**Panel 7: Trending Topics**
```
Title: Trending Hashtags/Sounds Served
Type: Stat
Metrics:
  - count(trending_items_served)
Legend: Trending Items
Shows: How many unique trending items served
```

---

## 🔔 Dashboard 5: Alerts & Anomalies (Optional but Recommended)

### Setup

```
Title: Real-time Alerts
Type: Alert List
Show: All firing alerts for video-ranking
Refresh: 5s

Key Alerts to Monitor:
1. HighErrorRate - Error rate > 0.5%
2. LowCacheHitRate - Hit rate < 85%
3. HighLatency - P95 > 300ms
4. PodRestart - Any pod restart
5. OutOfMemory - Memory > 90%
6. NoAvailableReplicas - Replicas < 3
```

---

## 🔧 Prometheus Alert Rules Configuration

Create/update PrometheusRule for baseline collection:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: video-ranking-baseline-alerts
  namespace: nova-staging
spec:
  groups:
  - name: video-ranking.baseline.rules
    interval: 30s
    rules:

    # Critical: High Error Rate
    - alert: VideoRankingHighErrorRate
      expr: |
        (sum(rate(http_requests_total{handler=~"reels.*",status=~"5.."}[5m])) /
         sum(rate(http_requests_total{handler=~"reels.*"}[5m]))) > 0.01
      for: 2m
      annotations:
        summary: "High error rate detected"
        description: "Error rate is {{ $value | humanizePercentage }}"

    # Warning: Low Cache Hit Rate
    - alert: VideoRankingLowCacheHitRate
      expr: |
        (sum(rate(cache_hits_total[5m])) /
         (sum(rate(cache_hits_total[5m])) + sum(rate(cache_misses_total[5m])))) < 0.85
      for: 5m
      annotations:
        summary: "Cache hit rate below target"
        description: "Cache hit rate is {{ $value | humanizePercentage }}"

    # Critical: High Latency
    - alert: VideoRankingHighLatency
      expr: |
        histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{handler=~"reels.*"}[5m])) > 0.5
      for: 3m
      annotations:
        summary: "API latency P95 exceeds 500ms"
        description: "P95 latency is {{ $value | humanizeDuration }}"

    # Critical: Pod Restart
    - alert: VideoRankingPodRestart
      expr: |
        increase(kube_pod_container_status_restarts_total{pod=~"video-ranking.*"}[1h]) > 0
      annotations:
        summary: "Pod restarted during baseline"
        description: "Pod {{ $labels.pod }} restarted"

    # Warning: Memory Pressure
    - alert: VideoRankingHighMemory
      expr: |
        (sum(container_memory_usage_bytes{pod=~"video-ranking.*"}) /
         sum(container_spec_memory_limit_bytes{pod=~"video-ranking.*"})) > 0.8
      for: 5m
      annotations:
        summary: "Memory usage above 80%"
        description: "Memory: {{ $value | humanizePercentage }}"

    # Critical: Insufficient Replicas
    - alert: VideoRankingInsufficientReplicas
      expr: |
        count(kube_pod_info{pod=~"video-ranking.*"}) < 3
      for: 1m
      annotations:
        summary: "Less than 3 replicas available"
        description: "Only {{ $value }} replicas running"
```

---

## 📱 Dashboard Import/Export

### Export Dashboards (for backup)
```bash
# Get dashboard JSON
curl -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  http://grafana:3000/api/dashboards/uid/video-ranking-system-health \
  > dashboard-system-health.json

# Repeat for other dashboards
```

### Import Dashboards (from file)
```bash
# After saving dashboard JSONs, import via:
curl -X POST http://grafana:3000/api/dashboards/db \
  -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @dashboard-system-health.json
```

---

## 🎯 Setup Checklist

### Pre-Collection (by 2025-10-20 08:00 UTC)

- [ ] **Dashboard 1: System Health & Resources**
  - [ ] Panel: Pod CPU Usage
  - [ ] Panel: Pod Memory Usage
  - [ ] Panel: Pod Restart Count
  - [ ] Panel: Replica Count
  - [ ] Panel: Node CPU Available
  - [ ] Panel: Node Memory Available
  - [ ] Panel: Disk I/O

- [ ] **Dashboard 2: API Performance & Latency**
  - [ ] Panel: Request Rate
  - [ ] Panel: Latency Distribution (P50/P95/P99)
  - [ ] Panel: Error Rate
  - [ ] Panel: Endpoint Latency
  - [ ] Panel: Latency Heatmap
  - [ ] Panel: Timeout Tracking

- [ ] **Dashboard 3: Cache Performance**
  - [ ] Panel: Cache Hit Rate
  - [ ] Panel: Cache Hits vs Misses
  - [ ] Panel: Redis Memory Usage
  - [ ] Panel: Cache Eviction Rate
  - [ ] Panel: Redis Key Count
  - [ ] Panel: TTL Histogram
  - [ ] Panel: Cache Size

- [ ] **Dashboard 4: Business Metrics**
  - [ ] Panel: Feed Requests
  - [ ] Panel: Engagement Rate
  - [ ] Panel: Ranking Score Distribution
  - [ ] Panel: Feed Generation Time
  - [ ] Panel: Search Volume
  - [ ] Panel: Recommendations
  - [ ] Panel: Trending Topics

- [ ] **Alert Configuration**
  - [ ] PrometheusRule deployed
  - [ ] 6+ alert rules active
  - [ ] Alert routing configured
  - [ ] Grafana alert notifications enabled

- [ ] **Dashboard Access**
  - [ ] All dashboards visible in Grafana
  - [ ] Time range set to 24h for baseline period
  - [ ] Auto-refresh enabled (15-30 seconds)
  - [ ] Read access granted to ops team

### During Collection (2025-10-20 10:00 - 2025-10-21 10:00 UTC)

- [ ] Monitor dashboards every 1-2 hours
- [ ] Log any anomalies or spikes
- [ ] Check alerts firing (should be minimal)
- [ ] Verify data collection is continuous

### Post-Collection

- [ ] Export all dashboard data
- [ ] Generate STAGING_BASELINE_REPORT.md
- [ ] Archive dashboard snapshots
- [ ] Save PrometheusRule configuration

---

## 🆘 Troubleshooting

### Metrics Not Appearing

```bash
# Check Prometheus scraping
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="video-ranking")'

# Check metrics are being exposed
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- curl localhost:9090/metrics | grep http_requests
```

### Dashboard Blank / No Data

```bash
# Verify metric names in Prometheus UI
# Navigate to http://prometheus:9090 > Metrics browser

# Common metrics:
- http_requests_total
- http_request_duration_seconds
- cache_hits_total
- cache_misses_total
- container_cpu_usage_seconds_total
- container_memory_usage_bytes
```

### Too Many Alerts Firing

```bash
# Adjust alert thresholds in PrometheusRule
# Consider baseline conditions are different from production

# Example: Increase error rate threshold for baseline
# From: > 0.01 (1%)
# To: > 0.05 (5%)
```

---

## 📞 Support

**Dashboard Issues**: ops-dashboard-support@example.com
**Alert Tuning**: monitoring-team@example.com
**Emergency**: @on-call (PagerDuty)

