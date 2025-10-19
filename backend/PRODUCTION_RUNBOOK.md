# Production Runbook - Video Ranking Service
## Standard Operating Procedures & Incident Response

**Effective Date**: 2025-10-26
**Version**: 1.0.0
**Last Reviewed**: 2025-10-19

---

## 📖 Table of Contents

1. [Service Overview](#service-overview)
2. [Health Monitoring](#health-monitoring)
3. [Common Issues & Solutions](#common-issues--solutions)
4. [Incident Response](#incident-response)
5. [Maintenance Procedures](#maintenance-procedures)
6. [Performance Tuning](#performance-tuning)
7. [Emergency Procedures](#emergency-procedures)

---

## Service Overview

### Service Information
- **Name**: video-ranking-service
- **Namespace**: nova-prod
- **Type**: Kubernetes Deployment
- **Replicas**: 3-10 (auto-scaling)
- **Region**: us-east-1
- **SLA**: 99.9% uptime

### Key Components
```
┌─────────────────────────────────────────────┐
│  Load Balancer (Nginx/ALB)                  │
└─────────────┬───────────────────────────────┘
              │
┌─────────────▼───────────────────────────────┐
│  Kubernetes Service (ClusterIP)             │
└─────────────┬───────────────────────────────┘
              │
    ┌─────────┴─────────┬─────────┐
    │                   │         │
┌───▼────┐         ┌───▼────┐ ┌──▼───┐
│ Pod 1  │         │ Pod 2  │ │ Pod 3│  (+ up to 10 under load)
└───┬────┘         └───┬────┘ └──┬───┘
    │                  │         │
    └──────────────────┼─────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
    ┌───▼──┐      ┌───▼────┐   ┌────▼──┐
    │Redis │      │Postgres│   │ClickH │
    │7.0+  │      │14+     │   │House  │
    └──────┘      └────────┘   └───────┘
```

---

## Health Monitoring

### Daily Health Checks

#### 1. Service Availability
```bash
# Check service is responding
curl http://video-ranking-service.nova-prod/api/v1/health

# Expected response (200 OK):
{
  "status": "healthy",
  "timestamp": "2025-10-26T08:30:00Z",
  "service": "video-ranking-service",
  "version": "1.0.0"
}
```

#### 2. Pod Status
```bash
# Check all pods running
kubectl get pods -n nova-prod

# Expected output: All pods in "Running" state with 1/1 Ready
NAME                                     READY   STATUS    RESTARTS   AGE
video-ranking-service-7f8d9c4b5-abc12   1/1     Running   0          2d4h
video-ranking-service-7f8d9c4b5-def34   1/1     Running   0          2d4h
video-ranking-service-7f8d9c4b5-ghi56   1/1     Running   0          2d4h
```

#### 3. Resource Utilization
```bash
# Check CPU and memory usage
kubectl top pods -n nova-prod

# Expected: CPU < 1000m (1 core), Memory < 512Mi per pod
NAME                                     CPU(cores)   MEMORY(bytes)
video-ranking-service-7f8d9c4b5-abc12   245m         287Mi
video-ranking-service-7f8d9c4b5-def34   238m         291Mi
video-ranking-service-7f8d9c4b5-ghi56   241m         289Mi
```

#### 4. Metrics Availability
```bash
# Check Prometheus is scraping metrics
curl http://prometheus.nova-prod:9090/api/v1/query?query=up{job=\"video-ranking-service\"}

# Expected response: value should be 1 for all pods
```

#### 5. Error Rate
```bash
# Query error rate in last 5 minutes
curl 'http://prometheus.nova-prod:9090/api/v1/query' \
  --data-urlencode 'query=rate(http_requests_total{status=~"5.."}[5m])'

# Expected: Near 0 (< 0.1%)
```

### Alert Thresholds

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| HighErrorRate | > 5% | CRITICAL | Immediate investigation |
| HighLatency | P95 > 1000ms | HIGH | Check database/cache |
| LowCacheHitRate | < 80% | MEDIUM | Monitor, may be warming |
| HighMemoryUsage | > 90% of limit | HIGH | Scale up or optimize |
| PodCrashLoop | > 5 restarts/15m | CRITICAL | Check logs, rollback |
| DatabaseConnectionPoolExhausted | < 20% available | HIGH | Scale up connections |
| RedisConnectionError | > 0.1 errors/sec | CRITICAL | Check Redis health |

---

## Common Issues & Solutions

### Issue 1: High Latency (P95 > 500ms)

**Symptoms:**
- API responses slow
- Latency P95 > 500ms
- Users report slow feed loading

**Diagnosis:**
```bash
# 1. Check database query performance
clickhouse-client --host clickhouse-prod --query \
  "SELECT query_duration_ms FROM system.query_log WHERE query LIKE '%video_ranking_signals%' ORDER BY event_time DESC LIMIT 10"

# 2. Check database connection pool
curl http://video-ranking-service.nova-prod:9090/metrics | grep database_pool

# 3. Check Redis latency
redis-cli -h redis-prod --latency-history

# 4. Check Kafka lag
kafka-consumer-groups --bootstrap-server kafka-prod:9092 --group video-ranking-consumer --describe
```

**Solutions:**
1. **If ClickHouse query slow**: Add missing index or optimize query
2. **If connection pool exhausted**:
   ```bash
   kubectl set env deployment/video-ranking-service \
     DATABASE_MAX_CONNECTIONS=30 -n nova-prod
   ```
3. **If Redis slow**: Check memory usage and eviction rate
4. **If Kafka lag**: Increase consumer parallelism

**Severity**: HIGH (blocks user experience)

---

### Issue 2: Low Cache Hit Rate (< 85%)

**Symptoms:**
- Cache hit rate trending down
- Latency increasing over time
- Redis key count not growing

**Diagnosis:**
```bash
# 1. Check cache size
redis-cli -h redis-prod KEYS "feed:*" | wc -l

# 2. Check cache stats
redis-cli -h redis-prod INFO stats | grep -E "hits|misses|evicted"

# 3. Check for cache invalidation
redis-cli -h redis-prod --scan --pattern "feed:*" | head -20

# 4. Check cache warm-up job
kubectl logs -l app=cache-warmer -n nova-prod --tail=50
```

**Solutions:**
1. **If cache not warmed**: Trigger manual warm-up
   ```bash
   curl -X POST http://video-ranking-service.nova-prod/api/v1/admin/cache-warmup \
     -H "Content-Type: application/json" \
     -d '{"user_count": 1000, "batch_size": 10}'
   ```
2. **If high eviction**: Increase Redis memory
3. **If cache invalidation issue**: Review invalidation logic

**Severity**: MEDIUM (degrades but doesn't break)

---

### Issue 3: Pod Crash Loop

**Symptoms:**
- Pods restarting frequently
- Restart count increasing
- Service partially unavailable

**Diagnosis:**
```bash
# 1. Check pod events
kubectl describe pod <pod-name> -n nova-prod

# 2. Check pod logs
kubectl logs <pod-name> -n nova-prod --previous

# 3. Check why it crashed
kubectl logs <pod-name> -n nova-prod --tail=50 | grep -i error

# 4. Check resource constraints
kubectl describe pod <pod-name> -n nova-prod | grep -A 5 "Limits"
```

**Solutions:**
1. **If out of memory**: Increase memory limit
   ```bash
   kubectl set resources deployment/video-ranking-service \
     -n nova-prod --limits=memory=2Gi
   ```
2. **If startup probe timing out**: Increase timeout
   ```bash
   kubectl patch deployment video-ranking-service -n nova-prod -p \
     '{"spec":{"template":{"spec":{"containers":[{"name":"video-ranking-service","startupProbe":{"failureThreshold":60}}]}}}}'
   ```
3. **If missing secret**: Verify all secrets created
   ```bash
   kubectl get secrets -n nova-prod
   ```
4. **If still crashing**: Rollback to previous version
   ```bash
   kubectl rollout undo deployment/video-ranking-service -n nova-prod
   ```

**Severity**: CRITICAL (service degradation)

---

### Issue 4: Database Connection Pool Exhaustion

**Symptoms:**
- Error: "no connection available"
- Connection pool showing < 20% available
- Queries timing out

**Diagnosis:**
```bash
# 1. Check current connections
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c \
  "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname"

# 2. Check query duration (long-running queries)
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c \
  "SELECT query, now() - pg_stat_statements.query_start as duration FROM pg_stat_statements WHERE query_start IS NOT NULL ORDER BY duration DESC LIMIT 10"

# 3. Check Kubernetes metric
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/nova-prod/pods/*/database_pool_available
```

**Solutions:**
1. **Increase connection pool size**:
   ```bash
   kubectl set env deployment/video-ranking-service \
     DATABASE_MAX_CONNECTIONS=40 -n nova-prod
   ```
2. **Kill long-running queries** (if safe):
   ```bash
   psql postgresql://prod-user:pass@postgres-prod:5432/nova -c \
     "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query_start < now() - interval '5 minutes'"
   ```
3. **Restart the service** to reset connections:
   ```bash
   kubectl rollout restart deployment/video-ranking-service -n nova-prod
   ```

**Severity**: HIGH (API unavailable)

---

### Issue 5: Redis Connection Errors

**Symptoms:**
- Errors in logs: "redis connection refused"
- Cache operations failing
- API latency spike

**Diagnosis:**
```bash
# 1. Check Redis cluster health
redis-cli -h redis-prod cluster info

# 2. Check Redis connectivity
redis-cli -h redis-prod ping
# Expected: PONG

# 3. Check network connectivity
kubectl run -it debug --image=nicolaka/netshoot -n nova-prod -- \
  telnet redis-prod 6379
```

**Solutions:**
1. **Verify Redis is running**: Check Redis cluster status
2. **Check network policy**: Ensure pods can reach Redis
3. **Restart Redis connection**: Restart pods
   ```bash
   kubectl rollout restart deployment/video-ranking-service -n nova-prod
   ```
4. **Fail over Redis node** (if cluster):
   ```bash
   redis-cli -h redis-prod cluster failover <node-id>
   ```

**Severity**: CRITICAL (cache unavailable)

---

### Issue 6: High Memory Usage (> 90% of limit)

**Symptoms:**
- Memory usage near limit (1.8Gi)
- Pod may get OOMKilled
- Service unstable

**Diagnosis:**
```bash
# 1. Check memory usage
kubectl top pod <pod-name> -n nova-prod

# 2. Check memory limits
kubectl get pod <pod-name> -n nova-prod -o json | jq '.spec.containers[].resources'

# 3. Profile memory usage
kubectl debug <pod-name> -n nova-prod -- /bin/sh
# Inside pod: ps aux | grep video-ranking
```

**Solutions:**
1. **Increase memory limit**:
   ```bash
   kubectl set resources deployment/video-ranking-service \
     -n nova-prod --limits=memory=3Gi
   ```
2. **Check for memory leaks**: Monitor trend over time
3. **Reduce cache size**: Configure TTL or max keys
4. **Scale horizontally**: Add more pods (increase replicas)

**Severity**: HIGH (can lead to OOMKill)

---

## Incident Response

### Critical Incident (Error rate > 5%)

**Step 1: Immediate Actions (0-1 min)**
```bash
# 1. Alert team
# - Post to #incidents Slack channel
# - Page on-call engineer

# 2. Check if this is widespread
kubectl get pods -n nova-prod
curl http://video-ranking-service.nova-prod/api/v1/health

# 3. Check recent changes
git log -1 --oneline
kubectl rollout history deployment/video-ranking-service -n nova-prod
```

**Step 2: Investigation (1-5 min)**
```bash
# 1. Check error logs
kubectl logs deployment/video-ranking-service -n nova-prod --tail=100 | grep -i error

# 2. Check metrics
curl 'http://prometheus.nova-prod:9090/api/v1/query' \
  --data-urlencode 'query=rate(http_requests_total{status=~"5.."}[1m])'

# 3. Check external dependencies
kubectl get events -n nova-prod -o wide
```

**Step 3: Decision (5-10 min)**
- **If root cause found & fixable**: Fix it
- **If root cause unknown or unfixable**: Proceed to **Step 4**

**Step 4: Rollback (if needed)**
```bash
# Rollback to previous version
kubectl rollout undo deployment/video-ranking-service -n nova-prod

# Verify rollback successful
kubectl rollout status deployment/video-ranking-service -n nova-prod
curl http://video-ranking-service.nova-prod/api/v1/health
```

**Step 5: Post-Incident (after stabilization)**
1. Document what happened
2. Create blameless RCA
3. Implement fixes to prevent recurrence
4. Update runbook if needed

---

### High Latency Incident (P95 > 1000ms)

**Immediate Response:**
```bash
# 1. Check database
kubectl exec -it <postgres-pod> -n nova-prod -- \
  psql -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname"

# 2. Scale up if CPU-bound
kubectl scale deployment video-ranking-service -n nova-prod --replicas=8

# 3. Check ClickHouse
clickhouse-client --host clickhouse-prod --query \
  "SELECT query_duration_ms FROM system.query_log ORDER BY event_time DESC LIMIT 5"

# 4. Check cache
redis-cli -h redis-prod --latency-latest
```

---

## Maintenance Procedures

### Daily Maintenance (30 minutes, Low risk)
```bash
# 1. Check metrics
kubectl top nodes
kubectl top pods -n nova-prod

# 2. Review errors in last 24h
kubectl logs deployment/video-ranking-service -n nova-prod --since=24h | grep -i error | wc -l

# 3. Check alert history
# View Alertmanager: http://alertmanager.nova-prod:9093
```

### Weekly Maintenance (1 hour, Low-Medium risk)
```bash
# 1. Database maintenance
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c "VACUUM ANALYZE"

# 2. Cache analysis
redis-cli -h redis-prod --scan --pattern "feed:*" | wc -l

# 3. Log rotation
# Verify logs are being rotated: journalctl -u kubelet --disk-usage

# 4. Update dependencies (if needed)
# Check for security updates in base image
```

### Monthly Maintenance (2 hours, Medium risk - schedule in low-traffic time)
```bash
# 1. Database reindex (if needed)
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c \
  "REINDEX DATABASE nova"

# 2. ClickHouse optimization
clickhouse-client --host clickhouse-prod --query \
  "OPTIMIZE TABLE video_ranking_signals_1h FINAL"

# 3. Certificate rotation (if expiring soon)
kubectl get secret tls-cert -n nova-prod -o json | \
  jq '.data."tls.crt"' -r | base64 -d | openssl x509 -text -noout | grep -A 2 Validity

# 4. Dependency updates
# Check for critical security updates
docker scout cves docker.io/nova/video-ranking-service:latest
```

---

## Performance Tuning

### Optimization Guidelines

#### Cache Optimization
```bash
# Current TTL: 1 hour
# If cache hit rate < 90%: Increase TTL to 2 hours
# If memory usage high: Decrease cache size via max-keys

# Check current cache performance
redis-cli -h redis-prod INFO stats
```

#### Database Optimization
```bash
# Add index for frequently queried columns
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c \
  "CREATE INDEX IF NOT EXISTS idx_video_ranking_signals_user_id ON video_ranking_signals(user_id)"

# Check query plans
EXPLAIN ANALYZE SELECT * FROM video_ranking_signals WHERE user_id = 'xyz'
```

#### Ranking Algorithm Tuning
```bash
# Current weights:
# Freshness: 15%
# Completion: 40%
# Engagement: 25%
# Affinity: 15%
# Deep Learning: 5%

# Adjust weights via ConfigMap
kubectl edit configmap ranking-weights -n nova-prod
```

---

## Emergency Procedures

### Complete Service Failure (All pods down)

```bash
# 1. Check Kubernetes cluster health
kubectl cluster-info
kubectl get nodes

# 2. Check if pods are pending
kubectl get pods -n nova-prod -o wide

# 3. Manually restart deployment
kubectl rollout restart deployment/video-ranking-service -n nova-prod

# 4. If still down, check events
kubectl describe deployment video-ranking-service -n nova-prod

# 5. If infrastructure issue, contact platform team
# - Check: AWS/GCP/Azure console for cluster status
# - Contact: Platform engineering team
```

### Database Unavailable

```bash
# 1. Check if database is accepting connections
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c "SELECT 1"

# 2. If connection fails:
#    - Check database service status
#    - Check network connectivity
#    - Check database logs

# 3. Fallback: Switch to read-only cache mode
kubectl set env deployment/video-ranking-service \
  FALLBACK_MODE=cache-only -n nova-prod

# 4. Notify users of degraded service
# Update status page
```

### Cache (Redis) Unavailable

```bash
# 1. Check Redis cluster status
redis-cli -h redis-prod cluster info

# 2. If unavailable:
#    - Check Redis logs
#    - Restart Redis node
#    - Fail over to replica

# 3. API will automatically degrade to direct database queries
# (slower but functional)
```

---

## 📞 Escalation Protocol

### Level 1: On-Call Engineer
- **Response Time**: 5 minutes
- **Handles**: Non-critical issues, standard troubleshooting
- **Contact**: [On-call Slack bot] or PagerDuty

### Level 2: Team Lead
- **Response Time**: 15 minutes
- **Handles**: Critical issues, requires decision making
- **Trigger**: Error rate > 5% OR Uptime < 99%
- **Contact**: Page [Team Lead]

### Level 3: Manager
- **Response Time**: 30 minutes
- **Handles**: Major incidents, customer communication
- **Trigger**: Extended outage (> 30 min) OR data loss risk
- **Contact**: Page [Manager] → Incident Commander

---

## 📊 Key Dashboards

- **Main Dashboard**: http://grafana-prod:3000/d/video-ranking-overview
- **System Health**: http://grafana-prod:3000/d/system-health
- **Business Metrics**: http://grafana-prod:3000/d/business-metrics
- **Prometheus**: http://prometheus-prod:9090

---

## 📚 Additional Resources

- Deployment Guide: `backend/DEPLOYMENT_GUIDE.md`
- Quick Reference: `backend/PRODUCTION_QUICK_REFERENCE.md`
- Production Checklist: `backend/PRODUCTION_DEPLOYMENT_CHECKLIST.md`
- Architecture: `backend/PHASE4_IMPLEMENTATION_SUMMARY.md`

---

**Version**: 1.0.0
**Last Updated**: 2025-10-19
**Next Review**: 2025-11-19

