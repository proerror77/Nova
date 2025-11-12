# PgBouncer Deployment Guide

## Pre-Deployment Checklist

- [ ] PostgreSQL running with `max_connections = 200`
- [ ] PostgreSQL version 10+ (SCRAM-SHA-256 support)
- [ ] Kubernetes cluster available and configured
- [ ] `kubectl` configured for nova namespace
- [ ] All microservices existing (optional, for validation)

## Step 1: Prepare Credentials

```bash
cd backend/infrastructure/pgbouncer

# Generate secure passwords
NOVA_PASS=$(openssl rand -base64 32)
ADMIN_PASS=$(openssl rand -base64 32)
STATS_PASS=$(openssl rand -base64 32)

echo "Passwords generated:"
echo "nova_user: $NOVA_PASS"
echo "admin: $ADMIN_PASS"
echo "stats_user: $STATS_PASS"

# Generate userlist.txt
PGBOUNCER_NOVA_USER_PASS="$NOVA_PASS" \
PGBOUNCER_ADMIN_PASS="$ADMIN_PASS" \
PGBOUNCER_STATS_USER_PASS="$STATS_PASS" \
./generate_userlist.sh

# Save passwords securely
# Store in 1Password, AWS Secrets Manager, Vault, etc.
# Do NOT commit to Git!
```

## Step 2: Create PostgreSQL User

```bash
# Create nova_user in PostgreSQL with same password as above
kubectl exec postgres -n nova -- \
  psql -c "CREATE USER nova_user WITH PASSWORD '$NOVA_PASS' CREATEDB"

# Verify user created
kubectl exec postgres -n nova -- \
  psql -c "\du"

# Grant privileges
kubectl exec postgres -n nova -- \
  psql -d nova -c "GRANT ALL PRIVILEGES ON SCHEMA public TO nova_user"
```

## Step 3: Create Kubernetes Secret

```bash
# Create secret from generated userlist.txt
kubectl create secret generic pgbouncer-userlist \
  --from-file=userlist.txt=./userlist.txt \
  -n nova

# Verify secret created
kubectl describe secret pgbouncer-userlist -n nova

# Verify content (base64 decoded)
kubectl get secret pgbouncer-userlist -n nova \
  -o jsonpath='{.data.userlist\.txt}' | base64 -d
```

## Step 4: Deploy PgBouncer

### Option A: Using kubectl apply

```bash
# Apply all configurations
kubectl apply -f k8s/infrastructure/pgbouncer/

# Verify all resources created
kubectl get all -n nova -l app=pgbouncer

# Watch pod startup
kubectl get pods -n nova -l app=pgbouncer -w

# Expected output:
# NAME                        READY   STATUS    RESTARTS
# pgbouncer-abc123           2/2     Running   0
# pgbouncer-xyz789           2/2     Running   0
```

### Option B: Using helm (if available)

```bash
# Create Helm chart values
cat > pgbouncer-values.yaml << 'HELM_EOF'
replicaCount: 2
image:
  repository: pgbouncer/pgbouncer
  tag: "1.21"
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
HELM_EOF

# Install (requires Helm chart to be created)
# helm install pgbouncer ./pgbouncer -f pgbouncer-values.yaml -n nova
```

## Step 5: Verify Deployment

### Check Pod Status

```bash
# Get pod details
kubectl get pods -n nova -l app=pgbouncer -o wide

# Check pod logs for errors
kubectl logs deployment/pgbouncer -n nova

# Describe pod (shows events)
kubectl describe pod <pod-name> -n nova
```

### Test Connectivity

```bash
# Port-forward to test locally
kubectl port-forward svc/pgbouncer 6432:6432 -n nova

# In another terminal, test
psql postgresql://nova_user:$NOVA_PASS@localhost:6432/nova -c "SELECT 1"

# Expected: 1 (success)
```

### Check Pool Status

```bash
# Connect to admin console
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# Expected output:
#  database |   user   | cl_active | cl_waiting | sv_active | sv_idle | sv_used | sv_tested | sv_login | maxwait
# ----------+----------+-----------+------------+-----------+---------+---------+-----------+----------+---------
#  nova     | nova_user|     0     |      0     |     0     |    10   |    0    |     0     |     0    |   0

# Key points:
# - sv_idle = 10 (min_pool_size reached) ✓
# - sv_active = 0 (no active connections) ✓
# - cl_active = 0 (no clients) ✓
```

### Verify PostgreSQL Connections

```bash
# Check how many connections PostgreSQL sees from PgBouncer
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'pgbouncer'"

# Expected: 10 (min_pool_size)
```

## Step 6: Monitor Deployment

### Set Up Prometheus Scraping

Update Prometheus config to scrape PgBouncer exporter:

```yaml
# prometheus.yml
scrape_configs:
- job_name: pgbouncer
  static_configs:
  - targets: ['pgbouncer-exporter:9127']
  interval: 30s
```

### Import Grafana Dashboard

```bash
# Import dashboard template (create custom or use community)
# Available at: https://grafana.com/grafana/dashboards/?search=pgbouncer

# Key metrics to monitor:
# - pgbouncer_pools_servers_active
# - pgbouncer_pools_clients_active
# - pgbouncer_pools_clients_waiting
# - pgbouncer_pools_query_time_avg
```

### Set Up Alerts

```yaml
# Prometheus alerts (alert.rules.yml)
groups:
- name: pgbouncer
  rules:
  
  # Alert if clients waiting for connections
  - alert: PgBouncerClientsWaiting
    expr: pgbouncer_pools_clients_waiting > 0
    for: 5m
    annotations:
      summary: "PgBouncer: clients waiting for connections"
  
  # Alert if pool exhausted
  - alert: PgBouncerPoolExhausted
    expr: pgbouncer_pools_servers_active > 45
    for: 5m
    annotations:
      summary: "PgBouncer: connection pool nearly exhausted"
  
  # Alert if high latency
  - alert: PgBouncerHighLatency
    expr: pgbouncer_pools_query_time_avg > 5000
    for: 5m
    annotations:
      summary: "PgBouncer: high query latency ({{ $value }}ms)"
```

## Step 7: Update Microservices

### Prepare Updates

Update each service's `DATABASE_URL`:

```bash
# Docker: environment variable
DATABASE_URL=postgresql://nova_user:password@pgbouncer:6432/nova

# Kubernetes: update deployment
kubectl set env deployment/<service> \
  DATABASE_URL="postgresql://nova_user:$NOVA_PASS@pgbouncer:6432/nova" \
  -n nova
```

### Gradual Rollout

Start with low-traffic services, monitor, then increase:

```bash
# Service priority order:
# 1. identity-service (low traffic)
# 2. notification-service (low traffic)
# 3. cdn-service (medium traffic)
# 4. auth-service (medium traffic)
# 5. ... (remaining services)
# Last: graphql-gateway (critical)

# Update service
kubectl set env deployment/identity-service \
  DATABASE_URL="postgresql://nova_user:$NOVA_PASS@pgbouncer:6432/nova" \
  -n nova

# Monitor for errors
kubectl logs deployment/identity-service -n nova -f

# Wait 10 minutes, verify no issues, then continue
```

## Step 8: Optimize Application Configuration

### Reduce Application Connection Pool

After all services migrated to PgBouncer:

```rust
// Before (direct PostgreSQL)
let pool = PgPoolOptions::new()
    .max_connections(16)  // Direct connections
    .connect(&database_url)
    .await?;

// After (via PgBouncer)
let pool = PgPoolOptions::new()
    .max_connections(4)   // PgBouncer multiplexes
    .connect(&database_url)
    .await?;
```

Benefits:
- Reduced memory per application pod
- Faster startup (fewer connections to establish)
- Lower overhead from connection management

## Step 9: Performance Validation

### Run Baseline Test

```bash
# Before migration (direct PostgreSQL)
# Record TPS, latency, error rate

# After migration (via PgBouncer)
./benchmark.sh

# Compare results
# Should see similar or slightly better performance
```

### Production Validation

```bash
# Monitor production traffic for 24 hours
# Check:
# - Error rate (should be 0%)
# - Response latency (should be ±10% of baseline)
# - Database query count (should be same)
# - Connection count (should drop significantly)

# Example monitoring commands:
# Response latency
kubectl logs deployment/user-service -n nova | \
  grep "duration" | awk '{sum+=$NF; count++} END {print sum/count " ms"}'

# Error count
kubectl logs deployment/user-service -n nova | grep -i error | wc -l

# PostgreSQL connections (should be ~50)
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity"
```

## Rollback Procedure

If issues occur:

```bash
# 1. Update service back to direct PostgreSQL
kubectl set env deployment/user-service \
  DATABASE_URL="postgresql://nova_user:password@postgres:5432/nova" \
  -n nova

# 2. Wait for pods to restart
kubectl rollout status deployment/user-service -n nova

# 3. Verify connectivity
kubectl exec deployment/user-service -n nova -- \
  psql -c "SELECT 1"

# 4. If needed, delete PgBouncer deployment
kubectl delete -f k8s/infrastructure/pgbouncer/
```

## Post-Deployment Maintenance

### Regular Tasks

```bash
# Daily: Check pool health
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# Weekly: Review logs for errors
kubectl logs deployment/pgbouncer -n nova | grep -i error

# Monthly: Review metrics, adjust configuration if needed
# - Connection pool utilization
# - Query latency trends
# - Memory usage
```

### Configuration Updates

If you need to adjust settings:

```bash
# Edit ConfigMap
kubectl edit configmap pgbouncer-config -n nova

# Changes automatically picked up on pod restart
# Option 1: Wait for rolling update
# Option 2: Force rollout restart
kubectl rollout restart deployment/pgbouncer -n nova
```

## Troubleshooting Deployment

### Pod fails to start

```bash
# Check logs
kubectl logs <pod-name> -n nova

# Common errors and fixes:
# "auth_file not found" → Secret not mounted
# "listen address already in use" → Port conflict
# "Cannot connect to postgres" → PostgreSQL not ready
```

### Services can't connect

```bash
# Test from a pod
kubectl run debug --image=postgres:16 --rm -it -- \
  psql postgresql://nova_user:$NOVA_PASS@pgbouncer:6432/nova -c "SELECT 1"

# If failed, check:
# 1. PgBouncer is running
# 2. Network policies allow traffic
# 3. Secret is correctly mounted
```

## Success Criteria

Deployment is successful when:

- ✓ All PgBouncer pods are `Running` and `2/2 Ready`
- ✓ PostgreSQL connection count is ~50 (min_pool_size * replicas)
- ✓ All services can connect without errors
- ✓ Query latency is within 10% of baseline
- ✓ Error rate is 0%
- ✓ Pool shows healthy status: `SHOW POOLS`
- ✓ Monitoring and alerts are active

Once these criteria are met, migration is complete and PgBouncer is in production!
