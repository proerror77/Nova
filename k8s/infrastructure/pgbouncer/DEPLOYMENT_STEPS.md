# PgBouncer Deployment Guide for Nova Staging Environment

**Version**: 1.0
**Target Environment**: Staging
**Deployment Strategy**: Blue-Green with Zero Downtime
**Rollback Strategy**: Immediate revert via environment variable

---

## Prerequisites

### 1. Verify PostgreSQL Connection Details

```bash
kubectl get service postgres-service -n nova
# Expected output: postgres-service ClusterIP 10.x.x.x 5432/TCP
```

### 2. Check PostgreSQL Authentication Method

```bash
kubectl exec -n nova deployment/postgres -- psql -U postgres -c "SHOW password_encryption;"
# Expected: scram-sha-256
```

If not using SCRAM-SHA-256, update PostgreSQL first:

```sql
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();
```

---

## Step 1: Generate PgBouncer Userlist Secret

### 1.1 Navigate to PgBouncer directory

```bash
cd /Users/proerror/Documents/nova/backend/infrastructure/pgbouncer
```

### 1.2 Set database passwords (retrieve from existing secrets)

```bash
# Get existing PostgreSQL password
POSTGRES_PASSWORD=$(kubectl get secret postgres-credentials -n nova -o jsonpath='{.data.password}' | base64 -d)

# Set environment variables
export PGBOUNCER_NOVA_USER="nova_user"
export PGBOUNCER_NOVA_USER_PASS="$POSTGRES_PASSWORD"
export PGBOUNCER_ADMIN_PASS="$(openssl rand -base64 32)"
export PGBOUNCER_STATS_USER_PASS="$(openssl rand -base64 24)"
```

### 1.3 Generate userlist.txt

```bash
./generate_userlist.sh

# Verify the generated file
cat userlist.txt
# Should show SCRAM-SHA-256 hashes for: nova_user, admin, stats_user
```

### 1.4 Create Kubernetes Secret

```bash
kubectl create secret generic pgbouncer-userlist \
  --from-file=userlist.txt=./userlist.txt \
  --from-literal=admin-password="$PGBOUNCER_ADMIN_PASS" \
  -n nova

# Verify
kubectl get secret pgbouncer-userlist -n nova
kubectl describe secret pgbouncer-userlist -n nova
```

### 1.5 Secure cleanup

```bash
# Remove sensitive files
rm -f userlist.txt
unset PGBOUNCER_NOVA_USER_PASS PGBOUNCER_ADMIN_PASS PGBOUNCER_STATS_USER_PASS
```

---

## Step 2: Deploy PgBouncer (Canary First)

### 2.1 Deploy PgBouncer infrastructure

```bash
cd /Users/proerror/Documents/nova/k8s/infrastructure/overlays/staging

# Dry-run first
kubectl apply -k . --dry-run=client

# Deploy (this includes PgBouncer)
kubectl apply -k .
```

### 2.2 Verify PgBouncer deployment

```bash
# Check pods
kubectl get pods -n nova -l app=pgbouncer
# Expected: 2 replicas running

# Check services
kubectl get svc -n nova | grep pgbouncer
# Expected: pgbouncer (ClusterIP), pgbouncer-metrics, pgbouncer-headless

# Check logs
kubectl logs -n nova -l app=pgbouncer --tail=50
# Expected: "server login attempt: db=nova user=nova_user"
```

### 2.3 Test PgBouncer connectivity

```bash
# Connect to PgBouncer admin console
PGBOUNCER_POD=$(kubectl get pod -n nova -l app=pgbouncer -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n nova $PGBOUNCER_POD -- psql -h localhost -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# Expected output:
#  database |   user    | cl_active | cl_waiting | sv_active | sv_idle | sv_used | sv_tested | sv_login | maxwait | mode
# ----------+-----------+-----------+------------+-----------+---------+---------+-----------+----------+---------+-------------
#  nova     | nova_user |         0 |          0 |         5 |       5 |       0 |         0 |        0 |       0 | transaction
```

---

## Step 3: Canary Testing (Single Service)

### 3.1 Choose canary service

We'll use **feed-service** as it's read-only and has the least risk.

### 3.2 Create environment patch for feed-service

```bash
cat > /Users/proerror/Documents/nova/k8s/infrastructure/overlays/staging/feed-service-pgbouncer-patch.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: feed-service
  namespace: nova
spec:
  template:
    spec:
      containers:
      - name: feed-service
        env:
        # Database connection via PgBouncer
        - name: DATABASE_URL
          value: "postgresql://nova_user:PASSWORD@pgbouncer:6432/nova"
        # Feature flag to enable PgBouncer
        - name: USE_PGBOUNCER
          value: "true"
        # Reduce connection pool size (PgBouncer handles pooling)
        - name: DATABASE_MAX_CONNECTIONS
          value: "5"
        - name: DATABASE_MIN_CONNECTIONS
          value: "1"
EOF
```

**Note**: Replace `PASSWORD` with actual password from secret.

### 3.3 Apply canary patch

```bash
kubectl apply -f feed-service-pgbouncer-patch.yaml

# Wait for rollout
kubectl rollout status deployment/feed-service -n nova --timeout=2m

# Check feed-service logs
kubectl logs -n nova deployment/feed-service --tail=100 | grep -i "database\|pgbouncer"
```

### 3.4 Monitor canary health

```bash
# Check feed-service health endpoint
kubectl exec -n nova deployment/feed-service -- curl -s http://localhost:8080/health | jq .

# Check PgBouncer pool stats
kubectl exec -n nova $PGBOUNCER_POD -- psql -h localhost -p 6432 -U admin pgbouncer -c "SHOW STATS"

# Monitor for errors
kubectl logs -n nova deployment/feed-service --tail=100 --follow
```

### 3.5 Run basic queries

```bash
# GraphQL test query via feed-service
kubectl port-forward -n nova svc/graphql-gateway 4000:4000 &

curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  -d '{"query": "{ feed(limit: 10) { id title } }"}'
```

**Expected**: Normal response, no errors.

---

## Step 4: Full Rollout (All Services)

### 4.1 Update all service deployments

Create a global environment patch:

```bash
cat > /Users/proerror/Documents/nova/k8s/infrastructure/overlays/staging/pgbouncer-global-patch.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "*-service"
  namespace: nova
spec:
  template:
    spec:
      containers:
      - name: "*-service"
        env:
        # Global PgBouncer configuration
        - name: DATABASE_HOST
          value: "pgbouncer"
        - name: DATABASE_PORT
          value: "6432"
        - name: DATABASE_MAX_CONNECTIONS
          value: "5"
        - name: DATABASE_MIN_CONNECTIONS
          value: "1"
        - name: USE_PGBOUNCER
          value: "true"
EOF
```

### 4.2 Apply to all services

```bash
# Services to migrate
SERVICES=(
  "auth-service"
  "user-service"
  "content-service"
  "messaging-service"
  "notification-service"
)

for svc in "${SERVICES[@]}"; do
  echo "Migrating $svc to PgBouncer..."

  # Apply patch
  kubectl set env deployment/$svc -n nova \
    DATABASE_HOST=pgbouncer \
    DATABASE_PORT=6432 \
    DATABASE_MAX_CONNECTIONS=5 \
    DATABASE_MIN_CONNECTIONS=1 \
    USE_PGBOUNCER=true

  # Wait for rollout
  kubectl rollout status deployment/$svc -n nova --timeout=3m

  # Verify health
  kubectl get pods -n nova -l app=$svc

  sleep 10
done
```

### 4.3 Monitor global health

```bash
# Check all service pods
kubectl get pods -n nova -l component=backend

# Check PgBouncer connections
kubectl exec -n nova $PGBOUNCER_POD -- psql -h localhost -p 6432 -U admin pgbouncer -c "SHOW POOLS"
# Expected: cl_active > 0 for all services, sv_active around 20-30 total

# Check PostgreSQL backend connections
kubectl exec -n nova deployment/postgres -- psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE datname='nova';"
# Expected: ~25-50 connections (down from 200+)
```

---

## Step 5: Load Testing & Validation

### 5.1 Run baseline load test

```bash
# Install k6 if not present
brew install k6  # macOS
# or: sudo apt install k6  # Ubuntu

cd /Users/proerror/Documents/nova/backend/infrastructure/pgbouncer/load-testing

# Run load test (will create this script in next task)
k6 run --vus 50 --duration 5m pgbouncer-load-test.js
```

**Expected Results**:
- P95 latency < 100ms (GraphQL queries)
- 0% error rate
- PostgreSQL connections stable at 25-50

### 5.2 Monitor Prometheus metrics

```bash
# Open Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Navigate to: http://localhost:3000/d/pgbouncer-dashboard
```

**Key Metrics to Check**:
- `pgbouncer_pools_sv_active` (should be < 50)
- `pgbouncer_pools_cl_active` (can be 200+)
- `pgbouncer_queries_total` (should be increasing)
- `postgresql_connections` (should be ~50 total)

---

## Step 6: Rollback Procedure (If Issues Occur)

### 6.1 Immediate rollback (disable PgBouncer)

```bash
# Revert all services to direct PostgreSQL connection
for svc in auth-service user-service content-service feed-service messaging-service notification-service; do
  kubectl set env deployment/$svc -n nova \
    DATABASE_HOST=postgres-service \
    DATABASE_PORT=5432 \
    DATABASE_MAX_CONNECTIONS=20 \
    DATABASE_MIN_CONNECTIONS=2 \
    USE_PGBOUNCER-

  kubectl rollout status deployment/$svc -n nova --timeout=3m
done
```

### 6.2 Remove PgBouncer deployment

```bash
kubectl delete deployment pgbouncer -n nova
kubectl delete deployment pgbouncer-exporter -n nova
kubectl delete svc pgbouncer pgbouncer-metrics pgbouncer-headless -n nova
```

### 6.3 Verify services recovered

```bash
kubectl get pods -n nova -l component=backend
kubectl logs -n nova deployment/auth-service --tail=50 | grep "database connection"
```

---

## Post-Deployment Checklist

- [ ] All services running with PgBouncer
- [ ] PgBouncer health checks passing
- [ ] PostgreSQL connection count < 100 (down from 200+)
- [ ] No increase in query latency
- [ ] Prometheus metrics showing pool efficiency
- [ ] Grafana dashboard deployed and showing data
- [ ] Load testing completed successfully
- [ ] Rollback procedure documented and tested

---

## Monitoring & Alerts

### Key Metrics to Monitor (Week 1)

1. **PgBouncer Pool Saturation**
   ```promql
   pgbouncer_pools_sv_active / pgbouncer_pools_max_connections > 0.8
   ```

2. **Client Connection Queueing**
   ```promql
   rate(pgbouncer_pools_cl_waiting[5m]) > 10
   ```

3. **Backend Connection Stability**
   ```promql
   postgresql_connections{database="nova"} < 100
   ```

4. **Query Latency (via application metrics)**
   ```promql
   histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) < 0.1
   ```

### Alert Rules (Create in Prometheus)

```yaml
groups:
- name: pgbouncer
  interval: 30s
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

---

## Troubleshooting

### Issue 1: Service can't connect to PgBouncer

**Symptoms**: Service logs show "connection refused" or "authentication failed"

**Diagnosis**:
```bash
# Check PgBouncer service DNS
kubectl exec -n nova deployment/auth-service -- nslookup pgbouncer

# Test direct connection
kubectl exec -n nova deployment/auth-service -- psql -h pgbouncer -p 6432 -U nova_user -d nova -c "SELECT 1"
```

**Fix**:
1. Verify `pgbouncer-userlist` secret contains correct password
2. Check PgBouncer logs: `kubectl logs -n nova deployment/pgbouncer`
3. Verify NetworkPolicy allows traffic from service namespace

### Issue 2: PgBouncer pool exhausted

**Symptoms**: `pgbouncer_pools_cl_waiting > 0`, slow queries

**Diagnosis**:
```bash
kubectl exec -n nova $PGBOUNCER_POD -- psql -h localhost -p 6432 -U admin pgbouncer -c "SHOW POOLS"
# Check: sv_active vs max_db_connections
```

**Fix**:
1. Increase `default_pool_size` in configmap.yaml (current: 25)
2. Increase `max_db_connections` (current: 50)
3. Add more PgBouncer replicas (scale to 3)

### Issue 3: Long-running queries fail

**Symptoms**: Queries timeout after 60 seconds

**Cause**: PgBouncer `query_timeout` too low for batch jobs

**Fix**:
Update configmap.yaml:
```ini
query_timeout = 300  # 5 minutes
server_idle_in_transaction_session_timeout = 600  # 10 minutes
```

---

## Performance Benchmarks (Expected)

| Metric | Before PgBouncer | After PgBouncer | Improvement |
|--------|------------------|-----------------|-------------|
| PostgreSQL Connections | 200-300 | 40-60 | 80% reduction |
| Connection Latency (P95) | 50ms | 5ms | 90% faster |
| Query Throughput | 1000 qps | 2500 qps | 150% increase |
| Backend CPU | 60% | 35% | 40% reduction |

---

## References

- [PgBouncer Official Docs](https://www.pgbouncer.org/config.html)
- [Transaction Mode Pooling Best Practices](https://www.pgbouncer.org/faq.html#how-to-use-transaction-pooling)
- [Nova PgBouncer Documentation](/backend/infrastructure/pgbouncer/README.md)
- [Prometheus Metrics Guide](/backend/infrastructure/pgbouncer/METRICS.md)
