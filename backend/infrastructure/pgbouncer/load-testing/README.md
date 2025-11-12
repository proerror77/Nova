# PgBouncer Load Testing Suite

**Version**: 1.0
**Purpose**: Validate PgBouncer connection pooling performance before and after deployment

---

## Overview

This directory contains load testing scripts to validate PgBouncer's connection pooling performance. The tests verify that PgBouncer correctly multiplexes client connections to a small number of backend PostgreSQL connections while maintaining low latency and high throughput.

## Prerequisites

### 1. Install k6

**macOS**:
```bash
brew install k6
```

**Ubuntu/Debian**:
```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

**Windows**:
```powershell
choco install k6
```

### 2. Setup Port Forwarding

Before running tests, forward the GraphQL Gateway service:

```bash
kubectl port-forward -n nova svc/graphql-gateway 4000:4000
```

### 3. Get JWT Token

Generate a valid JWT token for authentication:

```bash
# Using curl to authenticate
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { login(username: \"test\", password: \"password\") { token } }"
  }'

# Export the token
export JWT_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

---

## Test Scenarios

### 1. Baseline Test (Before PgBouncer)

Run this test against the direct PostgreSQL connection to establish a performance baseline.

```bash
# 50 concurrent users, 5 minutes
k6 run --vus 50 --duration 5m pgbouncer-load-test.js

# Expected results (WITHOUT PgBouncer):
# - P95 latency: 80-150ms
# - Backend connections: 200-300
# - Connection overhead: High
# - Throughput: ~1000 req/s
```

### 2. PgBouncer Validation Test

Run this after deploying PgBouncer to verify performance improvements.

```bash
# Same load as baseline
k6 run --vus 50 --duration 5m pgbouncer-load-test.js

# Expected results (WITH PgBouncer):
# - P95 latency: 50-100ms (40% improvement)
# - Backend connections: 25-50 (80% reduction)
# - Connection overhead: Low
# - Throughput: 2000-2500 req/s (150% improvement)
```

### 3. Stress Test (High Load)

Test PgBouncer under heavy load to find breaking points.

```bash
# 200 concurrent users, 10 minutes
k6 run --vus 200 --duration 10m pgbouncer-load-test.js

# Monitoring checkpoints:
# - pgbouncer_pools_cl_waiting should stay at 0
# - pgbouncer_pools_sv_active should stay below 50
# - Error rate should stay below 1%
```

### 4. Spike Test (Traffic Surge)

Simulate sudden traffic spikes (e.g., viral content).

```bash
# Ramp from 50 to 500 VUs
k6 run --stage 1m:50,5m:500,1m:50 pgbouncer-load-test.js

# Watch for:
# - Connection queueing (pgbouncer_pools_cl_waiting)
# - Query timeouts
# - Backend connection count (should not exceed 50)
```

### 5. Endurance Test (Long-Running)

Verify stability over extended periods.

```bash
# 100 VUs for 1 hour
k6 run --vus 100 --duration 1h pgbouncer-load-test.js

# Check for:
# - Memory leaks
# - Connection leaks
# - Gradual latency increases
```

---

## Test Metrics & Interpretation

### Key Metrics

| Metric | Target | Interpretation |
|--------|--------|----------------|
| **http_req_duration (P95)** | < 100ms | 95% of requests complete in under 100ms |
| **http_req_duration (P99)** | < 300ms | 99% of requests complete in under 300ms |
| **errors** | < 1% | Error rate under 1% |
| **pgbouncer_pools_sv_active** | 25-50 | Backend connections stable |
| **pgbouncer_pools_cl_active** | 100-500 | Client connections handled |
| **pgbouncer_pools_cl_waiting** | 0 | No connection queueing |

### Prometheus Queries for Monitoring

While running tests, monitor these Prometheus metrics:

```promql
# Backend connection count (should stay low)
sum(pgbouncer_pools_sv_active{namespace="nova"})

# Client connections (can be high)
sum(pgbouncer_pools_cl_active{namespace="nova"})

# Connection multiplexing ratio (higher is better)
sum(pgbouncer_pools_cl_active{namespace="nova"}) / sum(pgbouncer_pools_sv_active{namespace="nova"})

# Query throughput
rate(pgbouncer_stats_total_query_count{namespace="nova"}[1m])

# Average query time (microseconds)
pgbouncer_stats_avg_query_time{namespace="nova"} / 1000000

# PostgreSQL connection count (should be ~50)
pg_stat_activity_count{namespace="nova",datname="nova"}
```

---

## Interpreting Results

### ✅ Success Criteria

- **P95 latency < 100ms**: Fast response times
- **Backend connections < 100**: Connection pooling working
- **Error rate < 1%**: High reliability
- **Multiplexing ratio > 5:1**: Efficient pooling (e.g., 250 clients → 50 backends)

### ⚠️ Warning Signs

- **P95 latency 100-200ms**: Check for slow queries
- **Backend connections 100-200**: Pool may be too large
- **Error rate 1-5%**: Investigate specific errors
- **cl_waiting > 0**: Pool saturation, consider increasing `default_pool_size`

### ❌ Failure Indicators

- **P95 latency > 300ms**: Severe performance issues
- **Backend connections > 200**: PgBouncer not effective
- **Error rate > 5%**: Critical failures
- **cl_waiting > 20**: Pool exhausted, immediate action needed

---

## Comparison: Before vs After PgBouncer

### Expected Performance Improvements

| Metric | Before PgBouncer | After PgBouncer | Improvement |
|--------|------------------|-----------------|-------------|
| Backend Connections | 200-300 | 25-50 | **80% reduction** |
| Connection Latency (P95) | 50ms | 5ms | **90% faster** |
| Query Throughput | 1000 qps | 2500 qps | **150% increase** |
| CPU Usage (PostgreSQL) | 60% | 35% | **40% reduction** |
| Connection Errors | 0.5% | 0.01% | **98% fewer errors** |

---

## Advanced Testing

### Custom Load Profiles

Create custom load profiles by modifying `options.stages`:

```javascript
// Gradual ramp-up
export const options = {
  stages: [
    { duration: '5m', target: 50 },   // Ramp to 50
    { duration: '10m', target: 100 }, // Ramp to 100
    { duration: '10m', target: 200 }, // Ramp to 200
    { duration: '5m', target: 0 },    // Cool down
  ],
};
```

### Test Specific Services

Modify the query distribution to focus on specific services:

```javascript
// Test only feed-service (read-heavy)
if (rand < 1.0) {
  selectedQuery = QUERIES.getFeed;
  queryName = 'getFeed';
}
```

### Test Write Operations

Focus on mutations to test write-heavy workloads:

```javascript
// 50% writes, 50% reads
if (rand < 0.5) {
  selectedQuery = QUERIES.createContent;
  queryName = 'createContent';
} else {
  selectedQuery = QUERIES.getFeed;
  queryName = 'getFeed';
}
```

---

## Troubleshooting

### Issue 1: High Error Rate (> 5%)

**Symptoms**: Error rate exceeds 5%, many 500 errors

**Diagnosis**:
```bash
# Check PgBouncer logs
kubectl logs -n nova deployment/pgbouncer --tail=100

# Check PostgreSQL connections
kubectl exec -n nova deployment/postgres -- psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE datname='nova';"
```

**Solutions**:
1. Increase `default_pool_size` in PgBouncer config
2. Check for long-running queries blocking the pool
3. Verify PostgreSQL `max_connections` setting

### Issue 2: Connection Queueing (cl_waiting > 0)

**Symptoms**: `pgbouncer_pools_cl_waiting` metric shows queued clients

**Diagnosis**:
```bash
# Check pool status
kubectl exec -n nova deployment/pgbouncer -- psql -h localhost -p 6432 -U admin pgbouncer -c "SHOW POOLS"
```

**Solutions**:
1. Increase `default_pool_size` (current: 25 per pod)
2. Increase `max_db_connections` (current: 50 per pod)
3. Scale PgBouncer horizontally (add more replicas)

### Issue 3: Authentication Failures

**Symptoms**: 401/403 errors, auth errors in logs

**Diagnosis**:
```bash
# Verify JWT token is valid
echo $JWT_TOKEN | cut -d'.' -f2 | base64 -d | jq .

# Check token expiry
date -r $(echo $JWT_TOKEN | cut -d'.' -f2 | base64 -d | jq -r '.exp')
```

**Solutions**:
1. Regenerate JWT token
2. Check auth-service logs for issues
3. Verify auth-service has database access via PgBouncer

---

## Continuous Monitoring

After load testing, set up continuous monitoring:

### Prometheus Alerts

```yaml
groups:
- name: pgbouncer
  rules:
  - alert: PgBouncerPoolSaturated
    expr: pgbouncer_pools_sv_active / pgbouncer_pools_max_connections > 0.9
    for: 5m
    annotations:
      summary: "PgBouncer pool nearly exhausted"

  - alert: PgBouncerClientWaiting
    expr: rate(pgbouncer_pools_cl_waiting[5m]) > 20
    for: 2m
    annotations:
      summary: "Clients waiting for PgBouncer connections"
```

### Grafana Dashboard

Import the dashboards from `/k8s/monitoring/grafana-dashboards/`:
- `pgbouncer-dashboard.json` - PgBouncer metrics
- `outbox-pattern-dashboard.json` - Event consistency
- `mtls-security-dashboard.json` - Service-to-service auth

---

## References

- [k6 Documentation](https://k6.io/docs/)
- [PgBouncer Performance Tuning](https://www.pgbouncer.org/faq.html)
- [Nova PgBouncer Deployment Guide](/k8s/infrastructure/pgbouncer/DEPLOYMENT_STEPS.md)
- [Nova Monitoring Dashboards](/k8s/monitoring/grafana-dashboards/)
