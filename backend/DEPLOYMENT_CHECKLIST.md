# Nova Backend - Deployment Checklist

**Version:** 1.0
**Last Updated:** 2025-11-06

This checklist ensures zero-downtime, safe deployments following the **Canary Release** strategy.

---

## Pre-Deployment (T-24 hours)

### Code Quality

- [ ] All unit tests pass (`cargo test --lib`)
- [ ] All integration tests pass (`cargo test --test '*'`)
- [ ] No compiler warnings (`cargo clippy -- -D warnings`)
- [ ] Code formatted (`cargo fmt --check`)
- [ ] Security audit clean (`cargo audit`)

### Database

- [ ] Migrations are backward-compatible (no column drops/renames)
- [ ] Migrations tested in staging environment
- [ ] Rollback plan prepared for migrations
- [ ] Database backup completed (production)
- [ ] Migration dry-run successful (`sqlx migrate info`)

### Configuration

- [ ] Environment variables reviewed for all 11 services
- [ ] Secrets updated in vault (AWS Secrets Manager / HashiCorp Vault)
- [ ] JWT keys rotated (if needed, with overlap period)
- [ ] AWS S3 bucket permissions verified
- [ ] Kafka topics exist and have correct retention policies
- [ ] Redis memory limits configured correctly
- [ ] ClickHouse table schemas match code expectations

### Infrastructure

- [ ] Kubernetes cluster capacity checked (CPU, memory)
- [ ] Database connection pool limits reviewed
- [ ] Redis cluster health verified
- [ ] Kafka brokers healthy (no under-replicated partitions)
- [ ] ClickHouse cluster healthy (no failed parts)
- [ ] Elasticsearch indices healthy (no red shards)
- [ ] Load balancer health checks configured

### Monitoring

- [ ] Prometheus scraping all services (check `/targets`)
- [ ] Grafana dashboards accessible
- [ ] AlertManager configured with PagerDuty/Slack
- [ ] Runbook links added to alert annotations
- [ ] On-call engineer identified and notified

### Documentation

- [ ] Release notes prepared (changes, bug fixes, breaking changes)
- [ ] Deployment runbook reviewed
- [ ] Rollback procedure documented
- [ ] Incident response team on standby

---

## Deployment Day (Production)

### Phase 1: Pre-Deployment Verification (T-0 minutes)

- [ ] All pre-deployment checks completed (see above)
- [ ] Staging environment verified with smoke tests
- [ ] No active incidents in production
- [ ] Database read replicas synced (lag < 1 second)
- [ ] Backup window confirmed (no active long-running queries)
- [ ] Communication sent to team (#nova-backend-ops Slack channel)

**Checkpoint:** ✅ All checks passed → Proceed to Phase 2

---

### Phase 2: Database Migrations (T+0 minutes)

⚠️ **Critical:** Run migrations before deploying new code.

**Step 1: Verify Current State**

```bash
# Check current migration version
sqlx migrate info --database-url $DATABASE_URL

# Expected output: List of applied migrations
```

**Step 2: Run Migrations**

```bash
# Dry-run (verify SQL)
cat backend/migrations/*.sql | head -50

# Run migrations
sqlx migrate run --database-url $DATABASE_URL

# Expected output: "Applied migration XXXXX"
```

**Step 3: Verify Migration Success**

```bash
# Check migration table
psql $DATABASE_URL -c "SELECT version, description, success FROM _sqlx_migrations ORDER BY installed_on DESC LIMIT 5;"

# Verify new columns/tables exist
psql $DATABASE_URL -c "\d+ your_new_table"
```

**Rollback Trigger:**
- ❌ Migration fails → STOP deployment
- ❌ Database errors in logs → Revert migration (`sqlx migrate revert`)

**Checkpoint:** ✅ Migrations successful → Proceed to Phase 3

---

### Phase 3: Build and Push Images (T+5 minutes)

**Step 1: Build Docker Images**

```bash
VERSION=v1.0.0  # Update this for each release
REGISTRY=your-registry.example.com

cd backend

# Build all 11 services
for service in auth-service user-service content-service feed-service media-service \
               messaging-service search-service streaming-service notification-service \
               cdn-service events-service; do
  echo "Building $service..."
  docker build \
    --build-arg SERVICE_NAME=$service \
    -f Dockerfile.template \
    -t $REGISTRY/nova-$service:$VERSION \
    -t $REGISTRY/nova-$service:latest \
    ..
done
```

**Step 2: Tag and Push Images**

```bash
for service in auth-service user-service content-service feed-service media-service \
               messaging-service search-service streaming-service notification-service \
               cdn-service events-service; do
  docker push $REGISTRY/nova-$service:$VERSION
  docker push $REGISTRY/nova-$service:latest
done
```

**Step 3: Verify Images in Registry**

```bash
# Check image exists
docker manifest inspect $REGISTRY/nova-auth-service:$VERSION
```

**Checkpoint:** ✅ All images pushed → Proceed to Phase 4

---

### Phase 4: Canary Deployment - 5% Traffic (T+10 minutes)

**Step 1: Deploy Canary (1 replica per service)**

```bash
# Update image tags in manifests
cd k8s/overlays/prod
sed -i "s/newTag: .*/newTag: $VERSION/" kustomization.yaml

# Apply canary deployment (5% traffic)
kubectl apply -k k8s/overlays/prod/canary/

# Verify pods are starting
kubectl get pods -n nova-backend -l version=$VERSION
```

**Step 2: Wait for Pods to be Ready (2-3 minutes)**

```bash
# Watch pod status
watch kubectl get pods -n nova-backend -l version=$VERSION

# Expected: All pods in "Running" state with 1/1 ready
```

**Step 3: Monitor Metrics (15 minutes)**

**Critical Metrics:**

| Metric | Threshold | Action if Exceeded |
|--------|-----------|-------------------|
| Error Rate | < 1% | ROLLBACK |
| P95 Latency | < 500ms | ROLLBACK |
| P99 Latency | < 1000ms | INVESTIGATE |
| CPU Usage | < 80% | MONITOR |
| Memory Usage | < 80% | MONITOR |

**Check Commands:**

```bash
# Grafana dashboard
open http://grafana.nova.app/d/nova-overview

# Prometheus queries
curl -G 'http://prometheus.nova.app/api/v1/query' \
  --data-urlencode 'query=rate(http_requests_total{status=~"5..", version="'$VERSION'"}[5m])'

# Check logs for errors
kubectl logs -n nova-backend -l version=$VERSION --tail=100 | grep -i error
```

**Rollback Trigger:**
- ❌ Error rate > 1% for 5 minutes → ROLLBACK to Phase 9
- ❌ P95 latency > 500ms for 5 minutes → ROLLBACK to Phase 9
- ❌ Any pod crash loop → ROLLBACK to Phase 9

**Checkpoint:** ✅ Metrics healthy for 15 minutes → Proceed to Phase 5

---

### Phase 5: Scale to 50% Traffic (T+25 minutes)

**Step 1: Scale Replicas (50/50 split)**

```bash
# Scale new version to 50%
kubectl scale deployment -n nova-backend --replicas=3 auth-service-$VERSION
# Repeat for all 11 services

# Verify traffic split
kubectl get pods -n nova-backend -o wide | grep auth-service
```

**Step 2: Monitor Metrics (30 minutes)**

**Extended Monitoring:**

```bash
# Compare old vs new version metrics
curl -G 'http://prometheus.nova.app/api/v1/query' \
  --data-urlencode 'query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{version=~"'$VERSION'|v0.9.0"}[5m])) by (version)'
```

**Rollback Trigger:**
- ❌ New version error rate > old version by 2x → ROLLBACK
- ❌ New version latency > old version by 1.5x → ROLLBACK

**Checkpoint:** ✅ Metrics stable for 30 minutes → Proceed to Phase 6

---

### Phase 6: Full Rollout - 100% Traffic (T+55 minutes)

**Step 1: Scale New Version to 100%**

```bash
# Apply full production deployment
kubectl apply -k k8s/overlays/prod/

# Wait for rollout
kubectl rollout status deployment -n nova-backend --timeout=10m
```

**Step 2: Verify All Pods Running New Version**

```bash
# Check all pods
kubectl get pods -n nova-backend -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' | grep $VERSION

# Expected: All services running $VERSION
```

**Step 3: Gracefully Terminate Old Version**

```bash
# Wait 5 minutes for active connections to drain
sleep 300

# Delete old deployment
kubectl delete deployment -n nova-backend -l version=v0.9.0
```

**Checkpoint:** ✅ All traffic on new version → Proceed to Phase 7

---

### Phase 7: Post-Deployment Verification (T+65 minutes)

**Step 1: Health Check All Services**

```bash
# Check all 11 services
for port in 8080 8081 8082 8083 8084 8085 8086 8087 8088 8089 8090; do
  echo "Testing service on port $port:"
  curl -f https://api.nova.app/api/v1/health || echo "FAILED"
done
```

**Step 2: Smoke Tests**

```bash
# User registration (auth-service)
curl -X POST https://api.nova.app/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","username":"testuser","password":"Test123!"}'

# User login (auth-service)
curl -X POST https://api.nova.app/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test123!"}'

# Get feed (feed-service)
TOKEN="..." # From login response
curl -H "Authorization: Bearer $TOKEN" https://api.nova.app/api/v1/feed

# Send message (messaging-service)
curl -X POST https://api.nova.app/api/v1/conversations/xxx/messages \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"Hello!"}'
```

**Step 3: Check Infrastructure Health**

```bash
# PostgreSQL
psql $DATABASE_URL -c "SELECT COUNT(*) FROM users;"

# Redis
redis-cli -h prod-redis.internal INFO keyspace

# ClickHouse
curl "http://prod-clickhouse.internal:8123/?query=SELECT%20COUNT(*)%20FROM%20feed_ranking_events"

# Kafka
kafka-topics --bootstrap-server prod-kafka-1.internal:9092 --list
```

**Checkpoint:** ✅ All smoke tests pass → Proceed to Phase 8

---

### Phase 8: Monitoring and Alerting (T+75 minutes)

**Step 1: Verify Monitoring Stack**

```bash
# Prometheus targets (all services should be "UP")
curl http://prometheus.nova.app/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Expected: No unhealthy targets
```

**Step 2: Verify Alerts**

```bash
# Check no critical alerts firing
curl http://alertmanager.nova.app/api/v2/alerts | jq '.[] | select(.status.state == "firing")'

# Expected: No critical alerts
```

**Step 3: Monitor for 2 Hours**

- [ ] No increase in error rate (< 0.5%)
- [ ] No degradation in latency (P95 < 500ms)
- [ ] No memory leaks (memory usage stable)
- [ ] No database connection pool exhaustion
- [ ] No Kafka consumer lag spikes

**Checkpoint:** ✅ Monitoring stable for 2 hours → Deployment complete

---

## Phase 9: ROLLBACK Procedure (If Needed)

⚠️ **Trigger:** Any checkpoint fails or critical metric exceeds threshold.

### Step 1: Stop Traffic to New Version Immediately

```bash
# Scale new version to 0 replicas
kubectl scale deployment -n nova-backend --replicas=0 auth-service-$VERSION
# Repeat for all services showing issues
```

### Step 2: Scale Old Version Back to 100%

```bash
# Scale old version
kubectl scale deployment -n nova-backend --replicas=3 auth-service-v0.9.0
# Repeat for all 11 services
```

### Step 3: Revert Database Migrations (If Needed)

```bash
# ONLY if new migrations are incompatible with old code
sqlx migrate revert --database-url $DATABASE_URL --target-version 20250101000000
```

### Step 4: Verify Rollback Success

```bash
# Check all services back on old version
kubectl get pods -n nova-backend -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | sort -u

# Run health checks
curl https://api.nova.app/api/v1/health
```

### Step 5: Post-Mortem

- [ ] Document what went wrong
- [ ] Collect logs and metrics from failed deployment
- [ ] File incident report
- [ ] Schedule retrospective meeting

---

## Post-Deployment (T+24 hours)

### Metrics Review

- [ ] Review error rate trend (should be flat or decreasing)
- [ ] Review latency percentiles (P50, P95, P99)
- [ ] Review resource utilization (CPU, memory)
- [ ] Review database query performance (slow query log)
- [ ] Review Kafka consumer lag (should be < 1000)

### Documentation

- [ ] Update CHANGELOG.md with release notes
- [ ] Update API documentation (OpenAPI specs)
- [ ] Announce deployment in #nova-announcements Slack channel
- [ ] Close deployment ticket in Jira/Linear

### Cleanup

- [ ] Delete old Docker images from registry (retain last 3 versions)
- [ ] Archive old Kubernetes manifests (git tag)
- [ ] Clear temporary migration files

---

## Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| **On-call Engineer** | [TBD] | PagerDuty |
| **Database Admin** | [TBD] | Slack: @dba |
| **DevOps Lead** | [TBD] | Slack: @devops |
| **Engineering Manager** | [TBD] | Phone: xxx-xxx-xxxx |

---

## Quick Reference

### Health Check URLs

```
https://api.nova.app/api/v1/health         # Aggregated health
https://api.nova.app/api/v1/health/live    # Liveness probe
https://api.nova.app/api/v1/health/ready   # Readiness probe
```

### Monitoring Dashboards

```
Grafana:       https://grafana.nova.app/d/nova-overview
Prometheus:    https://prometheus.nova.app/graph
AlertManager:  https://alertmanager.nova.app
```

### Common Commands

```bash
# View logs
kubectl logs -f -n nova-backend -l app=auth-service

# Restart service
kubectl rollout restart deployment -n nova-backend auth-service

# Scale service
kubectl scale deployment -n nova-backend auth-service --replicas=5

# Port-forward for debugging
kubectl port-forward -n nova-backend svc/auth-service 8083:8083
```

---

**Status Legend:**

- ✅ **Green:** All checks passed, proceed
- ⚠️ **Yellow:** Warning, investigate but may proceed
- ❌ **Red:** Critical failure, STOP and rollback

**Deployment Decision Tree:**

```
┌─────────────────┐
│ Pre-checks pass?│
└────────┬────────┘
         │
    ✅ Yes │ ❌ No → STOP
         ↓
┌─────────────────┐
│ Migrations OK?  │
└────────┬────────┘
         │
    ✅ Yes │ ❌ No → ROLLBACK
         ↓
┌─────────────────┐
│ Canary healthy? │
└────────┬────────┘
         │
    ✅ Yes │ ❌ No → ROLLBACK (Phase 9)
         ↓
┌─────────────────┐
│ 50% healthy?    │
└────────┬────────┘
         │
    ✅ Yes │ ❌ No → ROLLBACK (Phase 9)
         ↓
┌─────────────────┐
│ Full rollout OK?│
└────────┬────────┘
         │
    ✅ Yes │ ❌ No → ROLLBACK (Phase 9)
         ↓
  ✅ DEPLOYMENT COMPLETE
```

---

**Version History:**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-06 | Initial deployment checklist for Phase 1B |
