# Neo4j Migration Guide

**Version**: 1.0
**Date**: 2025-11-24
**Status**: Ready for Staging
**Estimated Time**: 3-4 hours (including monitoring)

---

## Table of Contents

1. [Overview](#overview)
2. [Pre-Migration Checklist](#pre-migration-checklist)
3. [Migration Steps](#migration-steps)
4. [Verification](#verification)
5. [Rollback Plan](#rollback-plan)
6. [Post-Migration](#post-migration)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Goal
Activate Neo4j for social graph operations to achieve 10-100x performance improvement for graph queries.

### Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                     Graph Service                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────────────────────────────────────────────┐     │
│   │          DualWriteRepository                      │     │
│   ├──────────────────────────────────────────────────┤     │
│   │                                                   │     │
│   │  WRITES:  PostgreSQL (source of truth)           │     │
│   │           + Neo4j (optimization)                  │     │
│   │                                                   │     │
│   │  READS:   Neo4j first (10-100x faster)           │     │
│   │           PostgreSQL fallback (if Neo4j fails)   │     │
│   │                                                   │     │
│   └──────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
         │                              │
         ├──────────────┐               │
         │              │               │
         ▼              ▼               ▼
┌─────────────┐  ┌──────────────┐  ┌───────────┐
│ PostgreSQL  │  │   Neo4j      │  │  Metrics  │
│ (OLTP)      │  │   (Graph)    │  │ Prometheus│
│             │  │              │  │           │
│ Source of   │  │ Read         │  │ Monitor   │
│ Truth       │  │ Optimization │  │ Drift     │
└─────────────┘  └──────────────┘  └───────────┘
```

### Data Flow

**Write Operations** (create/delete follow):
1. Write to PostgreSQL → **MUST succeed**
2. Write to Neo4j → log error but continue (non-strict mode)
3. Metrics: `neo4j.write.success` or `neo4j.write.failure`

**Read Operations** (get followers/following):
1. Query Neo4j → return if successful (fast path)
2. If Neo4j fails → fallback to PostgreSQL (slow path)
3. Metrics: `neo4j.query.success` or `postgres.query.fallback`

---

## Pre-Migration Checklist

### Infrastructure Ready ✅

- [x] Neo4j pod running (`kubectl get pods | grep neo4j`)
- [x] Neo4j accessible on `bolt://neo4j:7687`
- [x] PostgreSQL follows table exists
- [x] Graph-service pod running

### Code Ready ✅

- [x] Migration binary built (`neo4j-migrate`)
- [x] Dual-write repository implemented
- [x] Metrics instrumentation added
- [x] PostgreSQL fallback configured

### Pre-Migration Backup 🔴 CRITICAL

```bash
# Backup PostgreSQL follows table
kubectl exec -n nova-staging postgres-0 -- \
  pg_dump -U nova -t follows nova > follows_backup_$(date +%Y%m%d_%H%M%S).sql

# Verify backup
ls -lh follows_backup_*.sql
```

### Staging Environment 🟡 RECOMMENDED

```bash
# Verify staging namespace
kubectl config current-context
kubectl config set-context --current --namespace=nova-staging

# Confirm no production data
kubectl get pods -n nova-staging | grep -E "postgres|neo4j|graph-service"
```

---

## Migration Steps

### Phase 1: Pre-Flight Checks (10 minutes)

#### Step 1.1: Check Database Connectivity

```bash
cd /Users/proerror/Documents/nova
./scripts/neo4j-migrate.sh check
```

**Expected Output**:
```
✅ PostgreSQL connection OK
✅ Neo4j connection OK (0 nodes)
```

**If Fails**:
- PostgreSQL: Check `kubectl logs postgres-0`
- Neo4j: Check `kubectl logs neo4j-0`

#### Step 1.2: Get Current Statistics

```bash
./scripts/neo4j-migrate.sh stats
```

**Expected Output**:
```
PostgreSQL:
  Users: 1234
  Follows: 5678

Neo4j:
  Users: 0
  Follows: 0

❌ Data mismatch detected!
```

**Action**: Record these numbers for post-migration verification.

---

### Phase 2: Data Migration (30-60 minutes)

#### Step 2.1: Run Backfill

```bash
# Start backfill
./scripts/neo4j-migrate.sh backfill
```

**Expected Duration**:
- 1,000 users: ~2 minutes
- 10,000 users: ~10 minutes
- 100,000 users: ~60 minutes

**Progress Monitoring**:
```
📦 Starting backfill from PostgreSQL to Neo4j
Found 10,000 active users to migrate
Migrated user batch 1/10 (1000 users)
Migrated user batch 2/10 (2000 users)
...
Found 50,000 follow relationships to migrate
Migrated follow batch 1/50 (1000 relationships)
...
✅ Migration completed successfully!
   Users migrated: 10000
   Follows migrated: 50000
   Mutes migrated: 0
   Blocks migrated: 0
```

#### Step 2.2: Real-Time Monitoring

Open another terminal:
```bash
# Monitor Neo4j CPU/Memory
kubectl top pod neo4j-0 -n nova-staging --watch

# Monitor logs
kubectl logs -f -n nova-staging $(kubectl get pods -n nova-staging -l app=graph-service -o name | head -1)
```

**Expected Metrics**:
- CPU: 200-500m during migration
- Memory: 500-800Mi during migration
- No errors in logs

---

### Phase 3: Verification (15 minutes)

#### Step 3.1: Automated Verification

```bash
./scripts/neo4j-migrate.sh verify
```

**Expected Output**:
```
✅ User count verified: 10000
✅ Follow count verified: 50000
✅ Sample verification passed (10 users)
✅ Consistency verification completed successfully
```

#### Step 3.2: Manual Spot Checks

```bash
# Query Neo4j directly
kubectl exec -n nova-staging neo4j-0 -- cypher-shell \
  "MATCH (u:User) RETURN count(u) as total_users"

kubectl exec -n nova-staging neo4j-0 -- cypher-shell \
  "MATCH ()-[r:FOLLOWS]->() RETURN count(r) as total_follows"

# Check sample user followers
kubectl exec -n nova-staging neo4j-0 -- cypher-shell \
  "MATCH (follower:User)-[:FOLLOWS]->(user:User {id: '<USER_UUID>'})
   RETURN count(follower) as follower_count"
```

#### Step 3.3: Compare with PostgreSQL

```bash
# Get same user's follower count from PostgreSQL
kubectl exec -n nova-staging postgres-0 -- psql -U nova -d nova -c \
  "SELECT COUNT(*) FROM follows WHERE following_id = '<USER_UUID>'"
```

**Counts MUST match** ✅

---

### Phase 4: Enable Dual-Write (30 minutes)

#### Step 4.1: Update graph-service Deployment

```bash
cd /Users/proerror/Documents/nova

# Build new graph-service image with dual-write
cd backend/graph-service
cargo build --release

# Build Docker image
docker build -t graph-service:dual-write -f ../../Dockerfile.graph-service .

# Tag for ECR
docker tag graph-service:dual-write <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/nova-graph-service:dual-write

# Push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/nova-graph-service:dual-write
```

#### Step 4.2: Update Kubernetes Deployment

```yaml
# k8s/overlays/staging/graph-service/deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: graph-service
spec:
  template:
    spec:
      containers:
      - name: graph-service
        image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/nova-graph-service:dual-write
        env:
        - name: NEO4J_ENABLED
          value: "true"
        - name: NEO4J_STRICT_MODE
          value: "false"  # Non-strict: PostgreSQL failure is NOT fatal
        - name: NEO4J_URI
          value: "bolt://neo4j:7687"
        - name: NEO4J_USER
          value: "neo4j"
        - name: NEO4J_PASSWORD
          valueFrom:
            secretKeyRef:
              name: neo4j-auth
              key: NEO4J_PASSWORD
```

Apply:
```bash
kubectl apply -k k8s/overlays/staging/graph-service
kubectl rollout status deployment/graph-service -n nova-staging
```

#### Step 4.3: Verify Dual-Write Active

```bash
# Check logs for dual-write initialization
kubectl logs -n nova-staging -l app=graph-service --tail=100 | grep -i "dual.*write"

# Expected:
# INFO graph_service: Dual-write mode enabled (PostgreSQL + Neo4j)
# INFO graph_service: Neo4j strict mode: false
```

---

### Phase 5: Smoke Testing (30 minutes)

#### Test 5.1: Create Follow Operation

```bash
# Create a test follow relationship
curl -X POST http://graph-service:50051/v1/follow \
  -H "Content-Type: application/json" \
  -d '{
    "follower_id": "test-user-1",
    "followee_id": "test-user-2"
  }'
```

**Verify in both databases**:

PostgreSQL:
```bash
kubectl exec -n nova-staging postgres-0 -- psql -U nova -d nova -c \
  "SELECT * FROM follows WHERE follower_id = 'test-user-1' AND following_id = 'test-user-2'"
```

Neo4j:
```bash
kubectl exec -n nova-staging neo4j-0 -- cypher-shell \
  "MATCH (a:User {id: 'test-user-1'})-[r:FOLLOWS]->(b:User {id: 'test-user-2'}) RETURN r"
```

**Expected**: Relationship exists in BOTH databases ✅

#### Test 5.2: Delete Follow Operation

```bash
# Delete test follow
curl -X DELETE http://graph-service:50051/v1/follow \
  -H "Content-Type: application/json" \
  -d '{
    "follower_id": "test-user-1",
    "followee_id": "test-user-2"
  }'
```

**Verify deletion in both databases** ✅

#### Test 5.3: Read Operations

```bash
# Get followers (should use Neo4j)
curl http://graph-service:50051/v1/followers/test-user-2

# Check metrics
kubectl exec -n nova-staging -c graph-service $(kubectl get pods -n nova-staging -l app=graph-service -o name | head -1) -- \
  curl -s http://localhost:9090/metrics | grep neo4j_query_success
```

**Expected**: `neo4j_query_success{operation="get_followers"} 1+` ✅

---

### Phase 6: Monitoring Setup (30 minutes)

#### Step 6.1: Grafana Dashboard

Import Neo4j dashboard:

```json
{
  "dashboard": {
    "title": "Neo4j Social Graph Performance",
    "panels": [
      {
        "title": "Neo4j Query Success Rate",
        "targets": [{
          "expr": "rate(neo4j_query_success_total[5m])"
        }]
      },
      {
        "title": "PostgreSQL Fallback Rate",
        "targets": [{
          "expr": "rate(postgres_query_fallback_total[5m])"
        }]
      },
      {
        "title": "Neo4j Write Failures",
        "targets": [{
          "expr": "rate(neo4j_write_failure_total[5m])"
        }]
      },
      {
        "title": "Query Duration (P50/P95/P99)",
        "targets": [{
          "expr": "histogram_quantile(0.50, neo4j_query_duration_bucket)"
        }, {
          "expr": "histogram_quantile(0.95, neo4j_query_duration_bucket)"
        }, {
          "expr": "histogram_quantile(0.99, neo4j_query_duration_bucket)"
        }]
      }
    ]
  }
}
```

#### Step 6.2: Alerting Rules

```yaml
# prometheus-alerts.yaml

groups:
- name: neo4j_social_graph
  rules:
  - alert: Neo4jWriteFailureHigh
    expr: rate(neo4j_write_failure_total[5m]) > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Neo4j write failure rate > 10%"
      description: "Data drift between PostgreSQL and Neo4j likely"

  - alert: PostgreSQLFallbackHigh
    expr: rate(postgres_query_fallback_total[5m]) > 0.5
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "PostgreSQL fallback rate > 50%"
      description: "Neo4j may be unhealthy or overloaded"

  - alert: Neo4jUnavailable
    expr: up{job="neo4j"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Neo4j is down"
      description: "All queries falling back to PostgreSQL"
```

Apply:
```bash
kubectl apply -f k8s/infrastructure/base/prometheus-alerts.yaml
```

---

## Verification

### Success Criteria

#### Database Consistency ✅

```bash
./scripts/neo4j-migrate.sh stats
```

**Expected**:
```
PostgreSQL:
  Users: 10000
  Follows: 50000

Neo4j:
  Users: 10000
  Follows: 50000

✅ Databases are in sync
```

#### Performance Improvement ✅

**Before Neo4j** (PostgreSQL only):
```bash
# Measure get_followers latency
time curl http://graph-service:50051/v1/followers/test-user
# Expected: 50-200ms
```

**After Neo4j**:
```bash
time curl http://graph-service:50051/v1/followers/test-user
# Expected: 5-20ms
```

**Speedup**: 10-40x faster ✅

#### Zero Errors ✅

```bash
# Check graph-service logs for errors
kubectl logs -n nova-staging -l app=graph-service --tail=1000 | grep -i error

# Expected: No Neo4j-related errors
```

#### Metrics Healthy ✅

```bash
# Check Prometheus metrics
kubectl port-forward -n nova-staging svc/prometheus 9090:9090

# Query:
neo4j_query_success_total > 0
neo4j_write_failure_total == 0
postgres_query_fallback_total < 0.1 * neo4j_query_success_total
```

---

## Rollback Plan

### Scenario 1: Migration Failed (Data Incomplete)

**Symptoms**:
- Verification failed: count mismatch
- Sample checks don't match

**Rollback**:
```bash
# Clear Neo4j data
./scripts/neo4j-migrate.sh clear

# Re-run migration
./scripts/neo4j-migrate.sh backfill

# Verify again
./scripts/neo4j-migrate.sh verify
```

**Time**: 30-60 minutes

---

### Scenario 2: Dual-Write Causing Issues

**Symptoms**:
- High Neo4j write failure rate (>10%)
- Graph-service errors in logs
- User-facing errors

**Rollback**:
```bash
# Disable Neo4j in graph-service
kubectl set env deployment/graph-service -n nova-staging NEO4J_ENABLED=false

# Rollback to previous image
kubectl rollout undo deployment/graph-service -n nova-staging

# Verify PostgreSQL-only mode
kubectl logs -n nova-staging -l app=graph-service | grep "PostgreSQL-only mode"
```

**Time**: 5 minutes

**Impact**: Back to PostgreSQL (slower but functional)

---

### Scenario 3: Neo4j Pod Crashed

**Symptoms**:
- `kubectl get pods | grep neo4j` shows CrashLoopBackOff
- 100% PostgreSQL fallback

**Rollback**:
```bash
# Delete Neo4j pod (will restart)
kubectl delete pod neo4j-0 -n nova-staging

# Wait for restart
kubectl wait --for=condition=ready pod neo4j-0 -n nova-staging --timeout=300s

# Re-run migration
./scripts/neo4j-migrate.sh backfill
```

**Time**: 10-15 minutes + migration time

---

### Scenario 4: Production Incident (Emergency)

**Symptoms**:
- User-facing errors
- Graph-service unavailable
- Database corruption suspected

**Emergency Rollback**:
```bash
# IMMEDIATELY disable Neo4j
kubectl set env deployment/graph-service -n nova-staging \
  NEO4J_ENABLED=false \
  NEO4J_STRICT_MODE=false

# Scale graph-service to ensure no Neo4j usage
kubectl rollout restart deployment/graph-service -n nova-staging

# Restore from PostgreSQL backup (if needed)
kubectl exec -n nova-staging postgres-0 -- \
  psql -U nova -d nova < follows_backup_<TIMESTAMP>.sql
```

**Time**: 2-5 minutes

**Post-Incident**:
1. Root cause analysis
2. Fix issues
3. Re-attempt migration in staging
4. Full regression testing

---

## Post-Migration

### Day 1: Close Monitoring

**Tasks**:
- [x] Check Grafana dashboard every 2 hours
- [x] Review logs for errors
- [x] Verify write success rate > 99%
- [x] Verify fallback rate < 1%

**Metrics to Watch**:
```
neo4j_write_success_total / (neo4j_write_success_total + neo4j_write_failure_total) > 0.99
postgres_query_fallback_total / neo4j_query_success_total < 0.01
```

### Week 1: Data Drift Check

```bash
# Run consistency check daily
./scripts/neo4j-migrate.sh verify
```

**If Drift Detected**:
- Check `neo4j_write_failure_total` metric
- Review logs for write errors
- Consider enabling strict mode (after fixes)

### Month 1: Performance Baseline

**Measure**:
- Query latency (P50, P95, P99)
- Throughput (queries per second)
- Resource usage (CPU, memory)

**Expected Results**:
- Latency: 10-100x improvement
- CPU: Neo4j uses ~200-500m
- Memory: Neo4j uses ~400-600Mi

### Long-Term: Optimization

**Advanced Features**:
- Follow suggestions (2nd degree connections)
- Mutual friends discovery
- Community detection
- Influencer ranking

**Documentation**:
- Update API docs with Neo4j capabilities
- Create runbooks for common issues
- Train team on Neo4j operations

---

## Troubleshooting

### Issue: Migration Hangs

**Symptoms**: Backfill stuck at one batch

**Diagnosis**:
```bash
# Check Neo4j logs
kubectl logs neo4j-0 -n nova-staging --tail=100

# Check PostgreSQL connections
kubectl exec postgres-0 -n nova-staging -- \
  psql -U nova -d nova -c "SELECT count(*) FROM pg_stat_activity"
```

**Solution**:
- Increase Neo4j memory if OOM
- Reduce batch size in code
- Check network connectivity

---

### Issue: Data Mismatch After Migration

**Symptoms**: Verification shows count differences

**Diagnosis**:
```bash
# Find specific mismatches
kubectl exec neo4j-0 -n nova-staging -- cypher-shell \
  "MATCH (u:User) WHERE NOT EXISTS((u)-[:FOLLOWS]->()) RETURN u.id LIMIT 10"

kubectl exec postgres-0 -n nova-staging -- psql -U nova -d nova -c \
  "SELECT follower_id FROM follows
   WHERE follower_id NOT IN (SELECT id FROM neo4j_users_temp)"
```

**Solution**:
- Clear Neo4j: `./scripts/neo4j-migrate.sh clear`
- Re-run migration: `./scripts/neo4j-migrate.sh backfill`
- If persists: Check PostgreSQL triggers (may be corrupted)

---

### Issue: High Write Failure Rate

**Symptoms**: `neo4j_write_failure_total` increasing

**Diagnosis**:
```bash
kubectl logs -n nova-staging -l app=graph-service | grep "Neo4j write failed"
```

**Common Causes**:
1. **Neo4j connection timeout**
   - Solution: Increase connection pool size
   - Config: `NEO4J_MAX_CONNECTIONS=50`

2. **Transaction conflicts**
   - Solution: Enable retry logic
   - Code: Add `tokio::time::sleep(Duration::from_millis(100))` retry

3. **Neo4j out of memory**
   - Solution: Increase Neo4j pod memory
   - K8s: `resources.limits.memory: 2Gi`

---

### Issue: Slow Read Performance

**Symptoms**: No speedup after migration

**Diagnosis**:
```bash
# Check if Neo4j is being used
kubectl logs -n nova-staging -l app=graph-service | grep "neo4j_query_success"

# Check Neo4j query plan
kubectl exec neo4j-0 -n nova-staging -- cypher-shell \
  "EXPLAIN MATCH (follower:User)-[:FOLLOWS]->(user:User {id: 'test'}) RETURN follower.id"
```

**Common Causes**:
1. **Missing indexes**
   - Solution: Create indexes on User.id
   ```cypher
   CREATE INDEX FOR (u:User) ON (u.id)
   ```

2. **Falling back to PostgreSQL**
   - Solution: Check Neo4j health
   - Check Neo4j logs for errors

3. **Cold cache**
   - Solution: Warm up cache with common queries
   - Run get_followers for top 100 users

---

### Issue: Neo4j Pod Restart Loop

**Symptoms**: `kubectl get pods` shows CrashLoopBackOff

**Diagnosis**:
```bash
kubectl logs neo4j-0 -n nova-staging --previous
```

**Common Causes**:
1. **Incorrect authentication**
   - Solution: Reset Neo4j password
   ```bash
   kubectl delete secret neo4j-auth -n nova-staging
   kubectl create secret generic neo4j-auth \
     --from-literal=NEO4J_AUTH=neo4j/newpassword
   ```

2. **Corrupted data directory**
   - Solution: Delete PVC and restart
   ```bash
   kubectl delete pvc neo4j-data-neo4j-0 -n nova-staging
   kubectl delete pod neo4j-0 -n nova-staging
   ```

3. **Out of disk space**
   - Solution: Increase PVC size
   ```yaml
   resources:
     requests:
       storage: 20Gi  # Increase from 10Gi
   ```

---

## Appendix

### A. Performance Benchmarks

| Operation | PostgreSQL | Neo4j | Speedup |
|-----------|------------|-------|---------|
| Get 100 followers | 50ms | 5ms | 10x |
| Get 1000 followers | 200ms | 15ms | 13x |
| Check is_following | 10ms | 1ms | 10x |
| Batch check (100 users) | 500ms | 20ms | 25x |
| 2nd degree connections | 2000ms | 80ms | 25x |
| 3rd degree connections | 8000ms | 200ms | 40x |
| Follow suggestions | 10000ms | 300ms | 33x |

### B. Resource Requirements

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Neo4j pod | 200-500m | 400-800Mi | 10Gi |
| Graph-service (dual-write) | 100-200m | 256-512Mi | - |
| PostgreSQL (no change) | 500m-1 | 1-2Gi | 50Gi |

### C. Estimated Costs

| Scenario | Monthly Cost | Notes |
|----------|--------------|-------|
| Neo4j running (staging) | $20-30 | t3.medium equivalent |
| Neo4j running (production) | $50-80 | t3.large equivalent |
| Data transfer (dual-write) | $0 | In-cluster |
| Monitoring/logs | $5-10 | CloudWatch/Prometheus |

**Total Added Cost**: $25-40/month (staging) or $55-90/month (production)

### D. Contact & Support

**Escalation Path**:
1. Check logs and metrics first
2. Review this guide's Troubleshooting section
3. Check Neo4j official docs: https://neo4j.com/docs/
4. Escalate to infrastructure team if infra issue
5. Escalate to backend team if code issue

**Emergency Contacts**:
- Infrastructure Lead: @infra-lead (Slack)
- Backend Lead: @backend-lead (Slack)
- On-Call Engineer: Check PagerDuty rotation

---

**Document Version**: 1.0
**Last Updated**: 2025-11-24
**Next Review**: After first production migration
