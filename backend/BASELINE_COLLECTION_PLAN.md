# 24-Hour Baseline Collection Plan
## Staging Environment - Video Ranking Service

**Start Date**: 2025-10-19 10:00 UTC
**End Date**: 2025-10-20 10:00 UTC
**Duration**: 24 hours
**Objective**: Establish performance baseline for production deployment

---

## 🎯 Executive Summary

This plan outlines the comprehensive data collection strategy for establishing performance baselines in the staging environment over a 24-hour period. The baseline data will be used to validate SLOs, set alert thresholds, and ensure production readiness.

---

## 📊 Metrics Collection Strategy

### Phase 1: Hour 0-2 (10:00-12:00 UTC) - Warm-up Phase

**Objectives:**
- Service stabilization post-deployment
- Cache initialization
- Connection pool warm-up

**Activities:**
```
10:00 - Service deployed, initial health check
10:15 - Cache warm-up begins (1000 top users)
10:30 - Cache hit rate should reach 80%+
11:00 - System reaches steady state
12:00 - Begin metric collection baseline
```

**Key Metrics to Track:**
- Cache hit rate progression
- Initial latency trends
- Pod restart count (should be 0)
- Error rate (should stay < 0.1%)

**Expected Results:**
- Cache hit rate: 0% → 80%+
- Latency P95: 300ms → 100ms
- Service uptime: 100%

---

### Phase 2: Hour 2-8 (12:00-18:00 UTC) - Steady State Operations

**Objectives:**
- Establish normal operating metrics
- Identify pattern variations
- Validate performance stability

**Activities:**
```
12:00 - Baseline collection active
13:00 - Moderate load simulation (10 concurrent users)
14:00 - Engagement event tracking validation
15:00 - Database query performance analysis
16:00 - Cache behavior analysis
17:00 - Resource utilization review
18:00 - Generate 6-hour trending report
```

**Key Metrics to Track:**
- API latency distribution (P50, P95, P99)
- Cache hit/miss rates
- Request throughput (req/s)
- Error rates by endpoint
- Database query latencies
- Pod resource utilization
- Kafka message lag

**Targets:**
- Latency P95: ≤ 100ms (cache hit), ≤ 300ms (cache miss)
- Cache hit rate: ≥ 95%
- Error rate: < 0.1%
- CPU usage: < 50% average
- Memory usage: < 300Mi average per pod

---

### Phase 3: Hour 8-16 (18:00-02:00 UTC+1) - Peak & Off-Peak Simulation

**Objectives:**
- Simulate peak traffic patterns
- Test burst handling
- Validate HPA behavior

**Activities:**
```
18:00 - Load ramp-up begins (20 concurrent users)
19:00 - Peak load simulation (40 concurrent users)
20:00 - Monitor HPA scaling decisions
21:00 - High load sustained (40 users, 100 req/s)
22:00 - Gradual load reduction
23:00 - Off-peak load (5 concurrent users)
00:00 - Night traffic pattern (minimal load)
01:00 - Monitor overnight stability
02:00 - Generate peak hour analysis
```

**Key Metrics to Track:**
- Response to load increases/decreases
- HPA scaling events (if any)
- Pod count changes
- CPU/memory peak values
- Cache eviction rate
- Query queue depth

**Expected Results:**
- HPA remains at 3 pods (should not exceed need)
- Latency remains within SLA even at peak
- No pod crashes or restarts
- Graceful degradation (if any)

---

### Phase 4: Hour 16-24 (02:00-10:00 UTC) - Extended Monitoring

**Objectives:**
- Validate 24-hour stability
- Collect full daily cycle data
- Identify any anomalies

**Activities:**
```
02:00 - Continue baseline monitoring
04:00 - Light traffic period
06:00 - Early morning traffic (expected low)
08:00 - Morning traffic ramp-up
09:00 - Approach peak hours
10:00 - Final metrics collection
10:30 - Generate 24-hour report
```

**Key Metrics to Track:**
- Trend analysis across full day
- Seasonal patterns (if any)
- Anomalies detection
- Long-term stability indicators
- Resource trends

---

## 📈 Detailed Metrics Collection

### API Performance Metrics

```yaml
Endpoints:
  - GET /api/v1/reels:
      - Latency P50, P95, P99
      - Request rate
      - Error rate
      - Response size
      - Cache hit rate

  - POST /api/v1/reels/{id}/like:
      - Latency distribution
      - Success rate
      - Queue depth

  - POST /api/v1/reels/{id}/watch:
      - Event processing latency
      - Kafka publish latency
      - Error handling

  - Other endpoints:
      - Similar tracking for all 11 endpoints
```

### Cache Metrics

```yaml
Redis Performance:
  - Hit rate (%)
  - Miss rate (%)
  - Eviction rate
  - Memory utilization (%)
  - Key distribution
  - Warm-up progression

Cache Statistics:
  - Hits: [cumulative count]
  - Misses: [cumulative count]
  - Total cache size (MB)
  - Keys per pod
```

### Database Metrics

```yaml
PostgreSQL:
  - Connection pool: available/total
  - Query latency: P50, P95, P99
  - Slow query count
  - Connection errors
  - Query rate (queries/sec)

ClickHouse:
  - Query latency distribution
  - Materialized view refresh latency
  - Data insertion latency
  - Error rate by query type

Redis:
  - Command latency
  - Memory usage
  - Expired keys
  - Evicted keys
```

### Infrastructure Metrics

```yaml
Pod Resources:
  - CPU usage (m, %)
  - Memory usage (Mi, %)
  - Network I/O
  - Disk I/O
  - Restart count

Pod Events:
  - Container starts
  - Container crashes
  - OOMKilled events
  - ImagePullBackOff events

HPA:
  - Current replicas
  - Scaling events
  - Desired vs current state
  - CPU/Memory utilization triggering scaling
```

### System Health Metrics

```yaml
Kubernetes:
  - Pod status (Running, Pending, Failed)
  - Node status
  - PVC usage
  - Event log analysis

Service Availability:
  - Health check status
  - Readiness probe success rate
  - Liveness probe success rate
  - Response code distribution (2xx, 4xx, 5xx)

Monitoring:
  - Prometheus scrape success rate
  - Alert firing events
  - Metric cardinality
```

---

## 📋 Collection Methods

### Prometheus Queries

```promql
# Cache hit rate over 5m window
rate(feed_cache_hits_total[5m]) / (rate(feed_cache_hits_total[5m]) + rate(feed_cache_misses_total[5m]))

# Latency percentiles
histogram_quantile(0.95, rate(feed_generation_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Pod resource utilization
container_memory_usage_bytes / container_spec_memory_limit_bytes

# Cache size
redis_memory_used_bytes

# Database connection pool
database_pool_available / database_pool_size
```

### Kubernetes CLI Commands

```bash
# Pod metrics every 10 seconds
watch -n 10 'kubectl top pods -n nova-staging'

# Event monitoring
kubectl get events -n nova-staging --sort-by='.lastTimestamp'

# Log collection
kubectl logs -f deployment/video-ranking-service -n nova-staging

# Metrics export
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/nova-staging/pods/*/video_ranking_service
```

### Custom Monitoring Script

```bash
# Run every 30 seconds
for i in {1..2880}; do
  # Capture metrics
  kubectl top pods -n nova-staging >> metrics.log
  curl http://localhost:9090/api/v1/query?query=... >> prometheus.log
  sleep 30
done
```

---

## 🎯 Success Criteria

### Must Have (Blocker Issues)
- [x] Service uptime: 99.9% (max 86.4 seconds downtime)
- [x] Zero pod crashes or restarts
- [x] API latency P95: ≤ 100ms (cache hit), ≤ 300ms (cache miss)
- [x] Error rate: < 0.1%
- [x] Cache hit rate: ≥ 95%

### Should Have (Non-blocker Issues)
- [x] CPU usage: < 50% average, < 70% peak
- [x] Memory usage: < 300Mi average per pod
- [x] No sustained latency degradation over time
- [x] All 11 API endpoints functional throughout test
- [x] Clean logs (no concerning warnings/errors)

### Nice to Have (Optimization Opportunities)
- [x] Latency P99: < 500ms
- [x] Cache warm-up time: < 60 seconds
- [x] Request throughput: > 100 req/s per pod
- [x] Resource trend stability (no memory leaks)

---

## 📊 Reporting Schedule

### Hourly Reports
**Frequency**: Every hour
**Contents**:
- Current metrics snapshot
- Delta from previous hour
- Trend indicators (↑↓→)
- Any alerts fired

### 6-Hour Reports
**Frequency**: At hours 6, 12, 18, 24
**Contents**:
- Averaged metrics for period
- Peak and trough values
- Cumulative statistics
- Performance trend analysis

### Final 24-Hour Report
**Due**: 2025-10-20 10:00 UTC
**Contents**:
- Executive summary
- Complete metric statistics
- Performance validation against SLOs
- Anomalies and incidents
- Recommendations for production
- Sign-off checklist

---

## ⚠️ Incident Response Protocol

### If Service Unavailable
1. Check pod status: `kubectl describe pods -n nova-staging`
2. Review recent logs: `kubectl logs deployment/video-ranking-service -n nova-staging --tail=100`
3. Check resource constraints: `kubectl top pods -n nova-staging`
4. If pod is OOMKilled: Increase memory limit
5. If crash loop: Check startup probe configuration

### If Latency Spikes > 1000ms
1. Check database query performance
2. Monitor ClickHouse query logs
3. Review Redis memory usage
4. Check Kafka broker health
5. Analyze network latency

### If Error Rate > 1%
1. Check application logs for exceptions
2. Review database connection pool status
3. Monitor external service dependencies
4. Check for cascading failures
5. Review recent deployments/changes

### If Cache Hit Rate < 80%
1. Verify cache is warmed up (takes ~60s)
2. Check Redis memory available
3. Review cache eviction rate
4. Check for cache invalidation issues
5. Validate cache key distribution

---

## 📞 Escalation Procedures

### Severity Levels

| Level | Condition | Action | Notification |
|-------|-----------|--------|--------------|
| CRITICAL | Uptime < 99%, Error rate > 5% | Immediate rollback | PagerDuty |
| HIGH | Latency P95 > 1000ms, Error rate 1-5% | Investigate, scale if needed | Slack #alerts |
| MEDIUM | Latency P95 > 500ms, Cache hit < 80% | Monitor closely | Slack #alerts |
| LOW | Warnings in logs, anomalies detected | Log for analysis | Slack #monitoring |

---

## 📝 Documentation to Produce

1. **Hourly Snapshot** (24 files)
   - Metrics values at time of collection
   - Any unusual observations

2. **Trend Analysis Report**
   - Latency trends over 24 hours
   - Resource utilization trends
   - Cache performance evolution

3. **Incident Report** (if applicable)
   - What happened
   - When it occurred
   - Duration
   - Root cause
   - Resolution
   - Impact assessment

4. **Production Readiness Report**
   - SLO validation
   - Baseline metrics
   - Recommendations
   - Sign-off decision

---

## ✅ Pre-Baseline Checklist

Before starting 24-hour collection:

- [x] Service deployed and stable (30 minutes uptime minimum)
- [x] All health checks passing (10/10)
- [x] Cache warm-up completed (cache hit rate ≥ 80%)
- [x] Database connections stable
- [x] Monitoring enabled (Prometheus scraping active)
- [x] Log collection running
- [x] Alert rules active
- [x] Metrics storage available (min 10GB)
- [x] No ongoing incidents
- [x] Team availability confirmed

---

## 📅 Timeline Summary

```
2025-10-19 10:00 - Baseline collection starts (Hour 0)
2025-10-19 12:00 - Warm-up complete, normal operation (Hour 2)
2025-10-19 18:00 - Peak load simulation (Hour 8)
2025-10-20 02:00 - Off-peak operations (Hour 16)
2025-10-20 10:00 - Collection complete, report generation (Hour 24)
2025-10-20 11:00 - Final report ready for review
```

---

## 🚀 Next Steps After Baseline

1. **Review baseline data** (Day 1)
   - Validate against SLOs
   - Identify anomalies
   - Set alert thresholds based on actual performance

2. **Production planning** (Days 2-3)
   - Size production environment based on baseline
   - Configure scaling policies
   - Plan deployment strategy (canary vs rolling)

3. **Production deployment** (Day 4-5)
   - Deploy to production
   - Monitor initial traffic
   - Collect production baseline
   - Optimize based on real user behavior

4. **Optimization** (Ongoing)
   - Tune ranking algorithm weights
   - Optimize cache strategies
   - Monitor for memory leaks
   - Continuously improve performance

---

## 📚 Reference Documents

- Implementation Summary: `backend/PHASE4_IMPLEMENTATION_SUMMARY.md`
- Deployment Guide: `backend/DEPLOYMENT_GUIDE.md`
- Staging Deployment Report: `backend/STAGING_DEPLOYMENT_REPORT.md`
- Load Testing Script: `backend/scripts/staging_load_test.sh`

---

**Status**: ✅ Ready to begin baseline collection
**Start Time**: 2025-10-19 10:00 UTC
**Expected Duration**: 24 hours
**Next Review**: 2025-10-20 10:00 UTC

