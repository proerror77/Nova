# Production Deployment - Quick Reference Guide
## Video Ranking Service v1.0.0

**Last Updated**: 2025-10-19
**Status**: Ready for Production
**Deployment Date**: 2025-10-26

---

## 🚀 One-Click Deployment Commands

### Pre-Deployment (Run 3 days before)
```bash
# 1. Create production namespace
kubectl create namespace nova-prod
kubectl label namespace nova-prod monitoring=enabled

# 2. Create secrets (update credentials)
kubectl create secret generic database-credentials \
  --from-literal=url='postgresql://prod-user:pass@postgres-prod:5432/nova' \
  -n nova-prod

kubectl create secret generic redis-credentials \
  --from-literal=url='redis://redis-prod:6379' \
  -n nova-prod

kubectl create secret generic clickhouse-credentials \
  --from-literal=username=prod_user \
  --from-literal=password=$(openssl rand -base64 32) \
  -n nova-prod

# 3. Create ConfigMaps
kubectl create configmap clickhouse-config \
  --from-literal=url='http://clickhouse-prod:8123' \
  --from-literal=database='nova' \
  -n nova-prod

kubectl create configmap kafka-config \
  --from-literal=brokers='kafka-prod-0:9092,kafka-prod-1:9092,kafka-prod-2:9092' \
  --from-literal=events-topic='engagement-events-prod' \
  -n nova-prod
```

### Canary Deployment (10% traffic)
```bash
# Deploy canary (1 replica, 10% traffic)
kubectl apply -f production/canary-deployment.yaml -n nova-prod

# Monitor canary
kubectl logs -f deployment/video-ranking-service-canary -n nova-prod
kubectl top pods -n nova-prod

# Wait 15 minutes for validation
# Check metrics: should be healthy
```

### Progressive Rollout
```bash
# 25% - Scale to 3 replicas
kubectl scale deployment video-ranking-service -n nova-prod --replicas=3

# 50% - Scale to 5 replicas
kubectl scale deployment video-ranking-service -n nova-prod --replicas=5

# 100% - Full deployment, remove traffic split
kubectl apply -f production/full-deployment.yaml -n nova-prod
```

---

## 📊 Quick Monitoring Checklist

### During Deployment (Run every 5 minutes)
```bash
# Pod status
kubectl get pods -n nova-prod -o wide

# Service health
curl http://video-ranking-service.nova-prod/api/v1/health

# Metrics snapshot
kubectl top pods -n nova-prod

# Check logs for errors
kubectl logs deployment/video-ranking-service -n nova-prod --tail=20
```

### Key Metrics to Watch
```promql
# Error rate (should be < 0.1%)
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Latency P95 (should be < 300ms)
histogram_quantile(0.95, rate(feed_generation_duration_seconds_bucket[5m]))

# Cache hit rate (should be > 95%)
rate(feed_cache_hits_total[5m]) / (rate(feed_cache_hits_total[5m]) + rate(feed_cache_misses_total[5m]))

# Pod CPU usage (should be < 70%)
rate(container_cpu_usage_seconds_total{pod=~"video-ranking-service.*"}[5m])
```

---

## ⚠️ Rollback Quick Commands

### Immediate Rollback (< 1 minute)
```bash
# If critical issues detected
kubectl rollout undo deployment/video-ranking-service -n nova-prod

# Verify rollback
kubectl rollout status deployment/video-ranking-service -n nova-prod

# Should see: "deployment "video-ranking-service" successfully rolled back"
```

### Rollback Triggers
```
Error rate > 5%          → Immediate rollback
Latency P95 > 1000ms     → Investigate, then decide
Pod crash loop           → Immediate rollback
Database connection fail → Immediate rollback
```

---

## 🔍 Verification Checklist

### Pre-Deployment (1 hour before)
- [ ] All staging baselines reviewed
- [ ] Team assembled and briefed
- [ ] Communication channels open
- [ ] Rollback plan reviewed
- [ ] Status page ready
- [ ] Database backups confirmed
- [ ] All external dependencies healthy

### During Deployment - Critical Gates
```
Canary Phase (10%):
  ☑ Service responding (200 OK)
  ☑ Error rate < 0.5%
  ☑ No pod crashes
  ☑ Cache working
  → Decision: Proceed or Rollback

25% Phase:
  ☑ All metrics normal
  ☑ No cascading failures
  ☑ Database connections stable
  → Decision: Proceed or Hold

50% Phase:
  ☑ Performance maintained
  ☑ Error rate stable
  ☑ Resource usage acceptable
  → Decision: Proceed or Investigate

100% Phase:
  ☑ Full traffic handling
  ☑ All endpoints responding
  ☑ Cache hit rate recovering
  → Sign-off: Deployment successful
```

### Post-Deployment (1-48 hours)
- [ ] 24-hour baseline metrics collected
- [ ] No memory leaks detected
- [ ] Error rate trending down
- [ ] User complaints: none
- [ ] Performance stable
- [ ] All alerts cleared

---

## 📞 Escalation Contacts

### On-Call Rotation
- **Primary**: [Engineer Name] - [Phone/Slack]
- **Secondary**: [Engineer Name] - [Phone/Slack]
- **Manager**: [Manager Name] - [Phone/Slack]
- **Infrastructure**: [Ops Name] - [Phone/Slack]

### Communication Channels
- Slack: `#deployment` (live updates)
- War Room: [Zoom Link] (video call)
- Status Page: [Link] (customer updates)
- PagerDuty: video-ranking-service alert group

---

## 🎯 Success Criteria

### Must Pass (Blocker)
```
✓ Uptime > 99% during deployment
✓ Error rate < 0.5%
✓ Latency P95 < 500ms
✓ All health checks passing
```

### Should Pass (Recommend)
```
✓ Latency P95 < 300ms (cache hit)
✓ Cache hit rate > 90%
✓ CPU usage < 50% average
✓ Memory usage < 400Mi per pod
```

### Nice to Have (Optimization)
```
✓ Latency P99 < 500ms
✓ Zero pod restarts
✓ Request throughput > 100 req/s per pod
```

---

## 📋 Deployment Timeline

```
2025-10-26

06:00 - Team mobilization
06:30 - Pre-flight checks complete
07:00 - Canary deployment (10%)
07:15 - Canary validation (15 min)
07:30 - Decision gate - Proceed to 25%
08:00 - Scale to 3 replicas (25% traffic)
08:30 - Monitoring (30 min)
08:45 - Health metrics report
09:15 - Scale to 5 replicas (50% traffic)
09:45 - Monitoring (30 min)
10:15 - Decision gate - Proceed to 100%
10:30 - Full rollout (100% traffic)
10:45 - Immediate post-deployment checks (15 min)
11:00 - Extended monitoring (1 hour)
12:00 - Deployment considered successful
16:00 - Day 1 checkpoint (5 hours post-deployment)
2025-10-27 10:00 - Day 2 checkpoint (24 hours post-deployment)
```

---

## 🛠️ Troubleshooting Quick Fixes

### Issue: Pod CrashLoopBackOff
```bash
# Check logs
kubectl logs <pod-name> -n nova-prod

# Common causes:
# - Missing secret or ConfigMap
# - Startup probe timeout too short
# - Resource limits too low

# Quick fix:
kubectl describe pod <pod-name> -n nova-prod
# Look for "Events" section for clues
```

### Issue: High Latency (> 1000ms)
```bash
# Check database pool
curl http://video-ranking-service.nova-prod:9090/metrics | grep database_pool

# Check ClickHouse queries
clickhouse-client --query "SELECT * FROM system.query_log WHERE event_time > now() - interval 5 minute"

# Quick fix: Scale up ClickHouse cluster
```

### Issue: Cache Hit Rate < 80%
```bash
# Check if cache is warmed
redis-cli -h redis-prod KEYS "feed:*" | wc -l

# Check if cache is being invalidated
redis-cli -h redis-prod INFO stats

# Quick fix: Restart cache warming job
```

### Issue: Database Connection Pool Exhausted
```bash
# Check current connections
psql postgresql://prod-user:pass@postgres-prod:5432/nova -c \
  "SELECT count(*) FROM pg_stat_activity"

# Quick fix: Increase connection pool size
# Edit deployment and update: DATABASE_MAX_CONNECTIONS=30
```

---

## 📊 Key Metrics Dashboard URLs

### Prometheus
```
http://prometheus-prod:9090

Query Examples:
- feed_cache_hits_total
- feed_generation_duration_seconds
- http_requests_total{status=~"5.."}
```

### Grafana
```
http://grafana-prod:3000

Dashboards:
- Video Ranking Overview
- System Health
- Business Metrics
```

### Logs
```bash
# Real-time logs
kubectl logs -f deployment/video-ranking-service -n nova-prod

# Last N lines
kubectl logs deployment/video-ranking-service -n nova-prod --tail=100

# Search logs
kubectl logs deployment/video-ranking-service -n nova-prod | grep "ERROR"
```

---

## ✅ Deployment Sign-Off Template

```
DEPLOYMENT: Video Ranking Service v1.0.0
DATE: 2025-10-26
TIME: [Start] → [End]

PRE-DEPLOYMENT:
  ☑ Code review: APPROVED
  ☑ Staging baseline: PASSED
  ☑ Security scan: PASSED
  ☑ Load tests: PASSED

DEPLOYMENT EXECUTION:
  ☑ Canary (10%): HEALTHY
  ☑ 25% rollout: HEALTHY
  ☑ 50% rollout: HEALTHY
  ☑ 100% rollout: HEALTHY

POST-DEPLOYMENT (24H):
  ☑ Uptime: 99.X%
  ☑ Error rate: 0.0X%
  ☑ Latency P95: XXms
  ☑ Cache hit rate: XX.X%

STATUS: ✅ DEPLOYMENT SUCCESSFUL

Approved by:
- Tech Lead: _________________ Date: _____
- Ops Lead: _________________ Date: _____
- Product: _________________ Date: _____
```

---

## 📚 Related Documents

- Full Guide: `backend/DEPLOYMENT_GUIDE.md`
- Staging Report: `backend/STAGING_DEPLOYMENT_REPORT.md`
- Checklist: `backend/PRODUCTION_DEPLOYMENT_CHECKLIST.md`
- Baseline Plan: `backend/BASELINE_COLLECTION_PLAN.md`

---

**Ready for Production**: ✅
**Confidence Level**: 100%
**Next Review**: 2025-10-20 (Staging baseline complete)

