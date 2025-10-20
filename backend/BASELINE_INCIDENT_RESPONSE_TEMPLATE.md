# Baseline Collection Incident Response Template
## Emergency Procedures for 24-Hour Staging Baseline (2025-10-20 to 2025-10-21)

**Purpose**: Provide rapid incident response procedures during baseline collection
**Owner**: Ops Team / On-Call Engineer
**Timeline**: 2025-10-20 10:00 UTC to 2025-10-21 10:00 UTC
**Escalation**: L1 (5 min) → L2 (15 min) → L3 (30 min) → L4 (60 min)

---

## 🔴 Critical Incidents (Immediate Action Required)

### INCIDENT TYPE 1: Complete Service Outage

**Symptoms**:
- Service endpoint unreachable (HTTP 503/504)
- All pods down or CrashLoopBackOff state
- 100% error rate for >1 minute
- Baseline collection blocked

**Severity**: CRITICAL
**Response Time Target**: <5 minutes
**Escalation Level**: L1 immediately

#### Step 1: Immediate Triage (L1 - 5 min)
```bash
# Check pod status
kubectl get pods -n nova-staging -o wide
kubectl describe pod deployment/video-ranking-deployment -n nova-staging

# Check service status
kubectl get svc -n nova-staging
kubectl get endpoints -n nova-staging video-ranking-service

# Check logs
kubectl logs -n nova-staging -l app=video-ranking --tail=100 | tail -50
kubectl logs -n nova-staging -l app=video-ranking --previous

# Check events
kubectl get events -n nova-staging --sort-by='.lastTimestamp' | tail -20
```

#### Step 2: Root Cause Analysis (L1 - 10 min)
```bash
# Check common issues:

# 1. Resource exhaustion?
kubectl top nodes
kubectl top pods -n nova-staging

# 2. Database connectivity?
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  psql -h postgres -U nova_user -d nova_db -c "SELECT 1;" 2>&1

# 3. Redis connectivity?
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis PING 2>&1

# 4. ClickHouse connectivity?
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  clickhouse-client -h clickhouse -q "SELECT 1" 2>&1

# 5. Config/secrets?
kubectl get secrets -n nova-staging
kubectl get configmap -n nova-staging
```

#### Step 3: Escalate to L2 if L1 cannot resolve in 5 minutes

**L2 Decision Point** (15 min mark):
- [ ] Issue resolved → Document and proceed with baseline (if <2 hours in)
- [ ] Issue identified but requires changes → Apply fix and restart
- [ ] Undetermined cause → Escalate to L3

#### Step 4: Emergency Rollback (if needed)
```bash
# If issue was recent code change:
kubectl rollout history deployment/video-ranking-deployment -n nova-staging

# Rollback to previous version
kubectl rollout undo deployment/video-ranking-deployment -n nova-staging

# Verify rollback
kubectl rollout status deployment/video-ranking-deployment -n nova-staging
```

#### Step 5: Reschedule Baseline if Necessary
```
If time ≤ 2 hours into baseline:
  → Fix issue and restart from Phase 1 (warm-up)

If time > 2 hours into baseline:
  → Consult with tech lead
  → May need to extend baseline collection to next day

If unresolvable:
  → Escalate to project leadership
  → Consider staging deployment revision
```

---

### INCIDENT TYPE 2: High Error Rate (>1%)

**Symptoms**:
- API error rate exceeds 1% for >3 minutes
- HTTP 5xx responses increasing
- Specific endpoint showing high errors
- Baseline metrics corrupted

**Severity**: CRITICAL
**Response Time Target**: <10 minutes
**Escalation Level**: L1 → L2

#### Step 1: Identify Error Pattern (L1 - 5 min)
```bash
# Check error rate
kubectl logs -n nova-staging -l app=video-ranking --tail=1000 | grep -i error | wc -l

# Get error breakdown
kubectl logs -n nova-staging -l app=video-ranking --tail=500 | grep ERROR | \
  awk '{print $NF}' | sort | uniq -c | sort -rn | head -10

# Check specific endpoints
for endpoint in reels search trending creators; do
  echo "=== $endpoint ==="
  kubectl logs -n nova-staging -l app=video-ranking | grep "$endpoint" | grep ERROR | head -5
done

# Check application logs
kubectl logs -n nova-staging deployment/video-ranking-deployment -f --tail=100 | grep -E "ERROR|panic|fatal"
```

#### Step 2: Determine Root Cause (L1 - 10 min)
```bash
# Is it a specific endpoint?
# Check recent code changes related to that endpoint

# Is it database-related?
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  psql -h postgres -U nova_user -d nova_db -c "SELECT datname, numbackends FROM pg_stat_database;" | grep nova_db

# Is it Redis-related?
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis INFO stats | grep -E "total_commands_processed|rejected_connections"

# Is it ClickHouse-related?
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  clickhouse-client -h clickhouse -q "SELECT * FROM system.query_log ORDER BY event_time DESC LIMIT 10;"

# Check system resources
kubectl top pods -n nova-staging
kubectl top nodes
```

#### Step 3: Apply Remediation (L1 or L2)

**If Database Connection Pool Exhausted**:
```bash
# Scale up replicas to distribute load
kubectl scale deployment video-ranking-deployment -n nova-staging --replicas=5

# Monitor recovery
kubectl get pods -n nova-staging -w
```

**If Memory Leak or Resource Leak Detected**:
```bash
# Restart pods in rolling fashion
kubectl rollout restart deployment/video-ranking-deployment -n nova-staging

# Monitor
kubectl rollout status deployment/video-ranking-deployment -n nova-staging
```

**If Specific Endpoint Failing**:
```bash
# Check if endpoint handler has recent issue
# Review code changes from git
git log --oneline backend/user-service/src/handlers/reels.rs | head -5

# If critical bug found:
# Either apply hotfix or disable endpoint temporarily
```

#### Step 4: Monitor Recovery
- [ ] Error rate back to <0.5% for >5 minutes
- [ ] No additional errors appearing
- [ ] Pods healthy and responsive
- [ ] Database connections normal

---

### INCIDENT TYPE 3: Complete Cache Failure

**Symptoms**:
- Cache hit rate drops to 0% suddenly
- Redis pod down or unresponsive
- All feed requests slow (>1 second)
- Baseline cache metrics invalid

**Severity**: CRITICAL
**Response Time Target**: <5 minutes
**Escalation Level**: L1 → L2

#### Step 1: Verify Cache Status (L1 - 2 min)
```bash
# Check Redis pod
kubectl get pods -n nova-staging -l app=redis
kubectl describe pod -n nova-staging -l app=redis

# Test Redis connectivity
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis --latency-history

# Check Redis memory
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis INFO memory | head -20

# Check Redis key count
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis DBSIZE
```

#### Step 2: Remediate (L1)

**If Redis Pod Down**:
```bash
# Delete pod to trigger recreation
kubectl delete pod -n nova-staging -l app=redis

# Wait for new pod
kubectl wait --for=condition=ready pod -l app=redis -n nova-staging --timeout=300s

# Verify recovery
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis PING
```

**If Redis Out of Memory**:
```bash
# Check current usage
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis INFO memory | grep "used_memory_human"

# Flush old keys (careful!)
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  redis-cli -h redis EVAL "return redis.call('del', unpack(redis.call('keys', ARGV[1])))" 0 "*:old-*"

# Or restart Redis
kubectl delete pod -n nova-staging -l app=redis
```

#### Step 3: Restart Cache Warming
```bash
# Kick off cache warm-up script
kubectl exec -it deployment/video-ranking-deployment -n nova-staging -- \
  curl -X POST http://localhost:8080/admin/cache/warm

# Monitor cache hit rate recovery
# Should go from 0% → 90%+ over 5-10 minutes
```

---

## 🟠 Major Incidents (Important Issues)

### INCIDENT TYPE 4: High Latency (P95 > 300ms)

**Symptoms**:
- API response time P95 > 300ms for >5 minutes
- Baseline performance baseline compromised
- Not a complete outage but significant degradation

**Severity**: MAJOR
**Response Time Target**: <15 minutes
**Escalation Level**: L1 → L2

#### Triage Checklist
```bash
# Check current latency
kubectl logs -n nova-staging -l app=video-ranking | grep latency_ms | tail -20

# Identify slow endpoints
# (grep for specific endpoint + duration)

# Check database query performance
# Slow queries accumulate in logs

# Check if it's cache-related
# Cache miss latency > cache hit latency
```

#### Common Remedies
```bash
# 1. Database slow queries
# Check PostgreSQL query logs
SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;

# 2. ClickHouse slow aggregations
# Check ClickHouse query log for slow queries

# 3. External API delays
# Check if trending/recommendations calls are slow

# 4. Resource contention
# Scale up if CPU/memory high
kubectl scale deployment video-ranking-deployment -n nova-staging --replicas=6

# 5. Cache inefficiency
# Check cache hit rate and TTL
```

---

### INCIDENT TYPE 5: Memory/CPU Spike

**Symptoms**:
- Memory usage >80% of limit
- CPU usage >1000m sustained
- Pod throttling or OOM kills
- Performance degradation

**Severity**: MAJOR
**Response Time Target**: <15 minutes
**Escalation Level**: L1 → L2

#### Response
```bash
# Check which pod is problematic
kubectl top pods -n nova-staging

# Check if leak detected
# Compare memory over time in Grafana

# If memory leak:
# Restart pods (rolling restart)
kubectl rollout restart deployment/video-ranking-deployment -n nova-staging

# If sustained high usage (legitimate):
# Scale up
kubectl scale deployment video-ranking-deployment -n nova-staging --replicas=5

# Increase resource limits if persistent
kubectl edit deployment video-ranking-deployment -n nova-staging
# Update spec.containers[0].resources.limits.memory
```

---

## 🟡 Minor Incidents (Watch & Monitor)

### INCIDENT TYPE 6: Single Pod Failure

**Symptoms**:
- One pod in CrashLoopBackOff
- Other pods healthy
- Service still responding
- Degraded capacity

**Severity**: MINOR
**Response Time Target**: <30 minutes
**Escalation Level**: L1

```bash
# Investigate pod logs
kubectl logs -n nova-staging pod-name --previous

# Delete and let controller restart
kubectl delete pod -n nova-staging pod-name

# Monitor for recurrence
kubectl get pods -n nova-staging -w

# If recurs: Escalate to L2
```

### INCIDENT TYPE 7: One Endpoint Slow

**Symptoms**:
- Specific endpoint slow (e.g., /api/v1/reels/search)
- Other endpoints normal
- Intermittent or consistent

**Severity**: MINOR
**Response Time Target**: <30 minutes
**Escalation Level**: L1

```bash
# Identify the endpoint
kubectl logs -n nova-staging -l app=video-ranking | grep search | grep latency

# Is it query-dependent? (certain queries slow)
# Add query analysis

# Escalate if persists >10 minutes
```

---

## 📋 Incident Response Checklist

For **any** incident, follow this checklist:

- [ ] **Time**: Log incident start time
- [ ] **Severity**: Determine severity level (Critical/Major/Minor)
- [ ] **Symptoms**: Document exact symptoms
- [ ] **Investigation**: Run diagnostics (see sections above)
- [ ] **Root Cause**: Identify root cause
- [ ] **Remediation**: Apply fix
- [ ] **Verification**: Confirm resolution
- [ ] **Duration**: Record total incident duration
- [ ] **Documentation**: Log to incident tracking
- [ ] **Communication**: Update stakeholders
- [ ] **Follow-up**: Schedule post-mortem if critical

---

## 🚨 Emergency Contact & Escalation

### Escalation Path

| Level | Role | Time | Action |
|-------|------|------|--------|
| L1 | On-Call Engineer | Immediate | Triage + quick fix attempts |
| L2 | Senior Engineer | +15 min | Deep investigation + fix |
| L3 | Platform Team | +30 min | Architecture-level issues |
| L4 | Tech Lead | +60 min | Major rollback/escalation |

### Communication Channels

- **Slack**: #staging-incidents
- **PagerDuty**: Automatic escalation
- **Email**: ops-team@example.com
- **Emergency**: @on-call

### Escalation Template

```
🚨 INCIDENT ESCALATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Severity: [CRITICAL/MAJOR/MINOR]
Time Since Start: [X minutes]
Component: [Which service/system]
Symptoms: [What's happening]
Attempted Fixes: [What was tried]
Current Status: [Still investigating/Fix applied/Waiting for verification]
Requesting: [What L2/L3 expertise needed]
Contact: [Your name/Slack handle]
```

---

## 🔍 Monitoring During Baseline

### Hourly Health Checks

Every hour during the 24-hour baseline:

```bash
# Quick health check
echo "=== Baseline Health Check $(date) ==="
echo "Pod Status:"
kubectl get pods -n nova-staging
echo ""
echo "Recent Errors:"
kubectl logs -n nova-staging -l app=video-ranking --tail=50 | grep ERROR | tail -5
echo ""
echo "Resource Usage:"
kubectl top pods -n nova-staging
```

### Dashboard Monitoring

- Watch **System Health** dashboard for resource spikes
- Watch **API Performance** dashboard for latency increases
- Watch **Cache Performance** dashboard for hit rate drops
- Watch **Alerts** dashboard for firing alerts

### Automatic Alerts

The following should trigger automatic PagerDuty alerts:
- Error rate > 1%
- Cache hit rate < 80%
- P95 latency > 500ms
- Pod restart
- Node CPU > 80%
- Pod memory > 90%

---

## 📝 Incident Log Template

```markdown
## Incident Report - [Date/Time]

**Incident ID**: BL-2025-1019-001
**Duration**: [start time] - [end time] (X minutes)
**Severity**: Critical/Major/Minor

### Summary
[Brief description of what happened]

### Root Cause
[What caused the issue]

### Timeline
- [Time] - Issue detected
- [Time] - Diagnosis completed
- [Time] - Fix applied
- [Time] - Service recovered

### Impact
- Duration: X minutes
- Baseline collection: [Affected/Not affected]
- Data loss: [Yes/No]
- Users affected: [Estimated number]

### Remediation
1. [First action taken]
2. [Second action taken]
3. [Follow-up action]

### Lessons Learned
[What could be improved]

### Follow-up Items
- [ ] Action item 1
- [ ] Action item 2
```

---

## 📞 Additional Resources

- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Prometheus Query Help**: http://prometheus:9090/graph
- **Grafana Dashboards**: http://grafana:3000
- **PostgreSQL Logs**: Check pod logs
- **Redis CLI**: `redis-cli help`
- **ClickHouse Queries**: https://clickhouse.com/docs/

**Last Updated**: 2025-10-19
**Version**: 1.0

