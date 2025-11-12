# PgBouncer Migration Guide

**Target:** Gradual migration of all microservices from direct PostgreSQL to PgBouncer  
**Timeline:** 2-3 days (phased approach)  
**Risk Level:** Low (can rollback at any time)

## Phase Overview

```
Phase 1 (Day 1): Deploy PgBouncer
  ├─ Set up PgBouncer infrastructure
  ├─ Verify connectivity
  └─ Configure monitoring

Phase 2 (Day 1-2): Pilot Services
  ├─ Migrate low-traffic services
  ├─ Monitor for issues
  └─ Verify database connection usage

Phase 3 (Day 2): Core Services
  ├─ Migrate medium-traffic services
  ├─ Extend monitoring
  └─ Verify performance

Phase 4 (Day 3): Critical Services
  ├─ Migrate high-traffic services
  ├─ Full system testing
  └─ Production validation
```

## Detailed Steps

### Phase 1: PgBouncer Deployment (Day 1 Morning)

**Objective:** Deploy PgBouncer without traffic

#### Step 1.1: Generate Credentials

```bash
cd backend/infrastructure/pgbouncer

# Generate SCRAM-SHA-256 hashes
PGBOUNCER_NOVA_USER_PASS="securepass123!" \
PGBOUNCER_ADMIN_PASS="adminpass456!" \
PGBOUNCER_STATS_USER_PASS="statspass789!" \
./generate_userlist.sh

# Verify output
cat userlist.txt
```

Expected output:
```
; PgBouncer User List with SCRAM-SHA-256 Hashes
"nova_user" "SCRAM-SHA-256$4096$..."
"admin" "SCRAM-SHA-256$4096$..."
"stats_user" "SCRAM-SHA-256$4096$..."
```

#### Step 1.2: Create Kubernetes Secret

```bash
# Create the secret
kubectl create secret generic pgbouncer-userlist \
  --from-file=userlist.txt=./userlist.txt \
  -n nova

# Verify creation
kubectl describe secret pgbouncer-userlist -n nova

# Check content
kubectl get secret pgbouncer-userlist -n nova -o jsonpath='{.data.userlist\.txt}' | base64 -d
```

#### Step 1.3: Deploy PgBouncer

```bash
# Apply all Kubernetes configurations
kubectl apply -f k8s/infrastructure/pgbouncer/

# Verify deployment
kubectl get all -n nova -l app=pgbouncer

# Check pod status
kubectl get pods -n nova -l app=pgbouncer -w

# Wait for "2/2 Ready"
# Expected output:
# NAME                        READY   STATUS    RESTARTS
# pgbouncer-abc123           2/2     Running   0
# pgbouncer-xyz789           2/2     Running   0
```

**Troubleshooting:** If pods fail to start:
```bash
kubectl logs deployment/pgbouncer -n nova
kubectl describe pod <pod-name> -n nova
```

#### Step 1.4: Verify Connectivity

```bash
# Port-forward to test locally
kubectl port-forward svc/pgbouncer 6432:6432 -n nova

# In another terminal, test connection
psql postgresql://nova_user:securepass123!@localhost:6432/nova -c "SELECT version()"

# Expected: PostgreSQL version information

# Check pool status
psql postgresql://admin:adminpass456!@localhost:6432/pgbouncer -c "SHOW POOLS"

# Expected output:
#  database |   user   | cl_active | cl_waiting | sv_active | sv_idle | sv_used | sv_tested | sv_login | maxwait
# ----------+----------+-----------+------------+-----------+---------+---------+-----------+----------+---------
#  nova     | nova_user|     0     |      0     |     0     |    10   |    0    |     0     |     0    |   0
```

**Key Metrics at This Point:**
- `sv_idle = 10` ✓ (min_pool_size reached)
- `sv_active = 0` ✓ (no active connections)
- `cl_active = 0` ✓ (no clients yet)

#### Step 1.5: Prepare Service Configurations

Before Phase 2, prepare DATABASE_URL changes for all services:

```bash
# Update all service deployments (don't deploy yet)
# For each service: sed -i 's/postgres:5432/pgbouncer:6432/g' k8s/*/deployment.yaml

# Example for one service:
# Before: DATABASE_URL=postgresql://user:pass@postgres:5432/nova
# After:  DATABASE_URL=postgresql://user:pass@pgbouncer:6432/nova
```

### Phase 2: Pilot Services (Day 1 Afternoon)

**Objective:** Migrate low-traffic services to validate the setup

**Services to Migrate (in order):**
1. `identity-service` (1 replica, lowest traffic)
2. `notification-service` (1 replica)
3. `cdn-service` (3 replicas)

#### Step 2.1: Migrate identity-service

```bash
# Update deployment
kubectl set env deployment/identity-service \
  DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
  -n nova

# Wait for rollout
kubectl rollout status deployment/identity-service -n nova

# Check that service is ready (pod should be Running, 2/2 Ready)
kubectl get pods -n nova -l app=identity-service
```

#### Step 2.2: Monitor Pool Status (5 minutes)

```bash
# Every 30 seconds for 5 minutes, check:
kubectl exec -it svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# Expected progression:
# Time: 0s   -> sv_active=3, sv_idle=7 (identity pods connecting)
# Time: 30s  -> sv_active=0, sv_idle=10 (transactions completed, connections returned)
# Time: 5m   -> sv_active=0, sv_idle=10 (steady state)

# Check for errors in logs
kubectl logs deployment/pgbouncer -n nova | grep -i error
```

#### Step 2.3: Verify Application Health

```bash
# Check pod logs for errors
kubectl logs deployment/identity-service -n nova | tail -20

# Verify service is working
kubectl exec deployment/identity-service -n nova -- \
  curl http://localhost:8000/health 2>/dev/null | jq .

# Expected: {"status": "healthy"}
```

#### Step 2.4: Repeat for notification-service

Same as Step 2.1-2.3, but for `notification-service`.

#### Step 2.5: Rollout cdn-service (3 replicas)

```bash
# Deploy all 3 replicas at once (low traffic service)
kubectl set env deployment/cdn-service \
  DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
  -n nova

# Monitor pool
kubectl exec -it svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# Expected: sv_active=0-3, sv_idle=7-10 (depends on request traffic)
```

**Decision Point:** If all 3 services are healthy after 30 minutes:
- ✓ Continue to Phase 3
- ✗ Rollback and debug issues (see troubleshooting)

### Phase 3: Core Services (Day 2)

**Objective:** Migrate medium-traffic services

**Services to Migrate:**
1. `auth-service` (3 replicas, medium traffic)
2. `messaging-service` (3 replicas, medium traffic)
3. `events-service` (1 replica)
4. `communication-service` (1 replica)

#### Step 3.1: Migrate auth-service

```bash
# Deploy with rolling update (one pod at a time)
kubectl set env deployment/auth-service \
  DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
  -n nova

# Watch rollout
kubectl rollout status deployment/auth-service -n nova --timeout=5m

# Monitor pool (should see spike when pods connect)
watch -n 5 "kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c 'SHOW POOLS'"

# Expected behavior:
# - sv_active jumps to 3-5 during rolling update
# - Stabilizes back to 0-2 after update completes
# - No errors in logs
```

#### Step 3.2: Monitoring Dashboard

Set up Grafana dashboard to monitor:

```bash
# Port-forward Prometheus (if available)
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Query pool metrics:
# pgbouncer_pools_servers_active
# pgbouncer_pools_clients_active
# pgbouncer_pools_clients_waiting
```

Alert thresholds:
- `pgbouncer_pools_clients_waiting > 0` → Check pool_size
- `pgbouncer_pools_servers_active > 40` → Check PostgreSQL capacity
- `pgbouncer_query_time > 5000ms` → Check for slow queries

#### Step 3.3: Migrate messaging-service

```bash
kubectl set env deployment/messaging-service \
  DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
  -n nova

kubectl rollout status deployment/messaging-service -n nova --timeout=5m
```

Continue with events-service and communication-service in same manner.

**Decision Point:** After 4 hours, check:
- ✓ All 4 services healthy, no errors
- ✓ Connection pool stable
- ✓ No degradation in response times
- Then → Continue to Phase 4

### Phase 4: Critical Services (Day 3)

**Objective:** Migrate remaining high-traffic services

**Services to Migrate:**
1. `feed-service` (3 replicas, HIGH traffic)
2. `content-service` (3 replicas, HIGH traffic)
3. `user-service` (3 replicas, HIGH traffic)
4. `graphql-gateway` (3 replicas, CRITICAL)
5. `search-service` (3 replicas, HIGH traffic)
6. `video-service` (3 replicas)
7. `social-service` (3 replicas)
8. `streaming-service` (3 replicas)
9. `media-service` (3 replicas)

#### Step 4.1: Migrate feed-service (highest traffic)

```bash
# Deploy with slow rolling update
kubectl set env deployment/feed-service \
  DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
  -n nova

# Monitor during deployment
kubectl rollout status deployment/feed-service -n nova --timeout=10m

# Check pool during peak traffic
watch -n 2 "kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c 'SHOW POOLS'"

# Expected: sv_active = 20-40 during peak traffic (normal for high-traffic service)
```

#### Step 4.2: Monitor for Issues

```bash
# Check PgBouncer logs
kubectl logs deployment/pgbouncer -n nova -f

# Check for "query_timeout" errors
kubectl logs deployment/pgbouncer -n nova | grep query_timeout

# Check PostgreSQL connection count
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity"
```

Expected PostgreSQL connections: 50 (from PgBouncer) ± 2 (management)

#### Step 4.3: Batch Migrate Remaining Services

```bash
# All remaining services at once (low risk at this point)
for svc in content-service user-service search-service \
           video-service social-service streaming-service media-service; do
  kubectl set env deployment/$svc \
    DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
    -n nova
done

# Wait for all rollouts
for svc in content-service user-service search-service \
           video-service social-service streaming-service media-service; do
  kubectl rollout status deployment/$svc -n nova --timeout=5m
done
```

#### Step 4.4: Migrate graphql-gateway (LAST - critical)

```bash
# Deploy with monitor
kubectl set env deployment/graphql-gateway \
  DATABASE_URL="postgresql://nova_user:securepass123!@pgbouncer:6432/nova" \
  -n nova

# Watch carefully
kubectl rollout status deployment/graphql-gateway -n nova --timeout=10m

# Verify API is still responsive
curl http://$(kubectl get svc graphql-gateway -n nova -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):4000/graphql/health
```

### Phase 5: Verification & Cleanup (Day 3)

#### Step 5.1: Full System Verification

```bash
# Check all services are running
kubectl get pods -n nova | grep -E '(Running|Pending)' | wc -l

# Verify no pods are CrashLooping
kubectl get pods -n nova | grep -i crash

# Check PostgreSQL connection count (should be ~50)
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"

# Check PgBouncer pool (should be at capacity)
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"
```

#### Step 5.2: Performance Baseline

```bash
# Run performance test
kubectl run -it --rm perf-test --image=postgres:16 --restart=Never -n nova -- \
  pgbench -U nova_user -d nova -h pgbouncer -c 100 -j 10 -t 10000

# Record results:
# - Transactions per second (TPS)
# - Latency (avg, max)
# - Success rate
```

#### Step 5.3: Documentation

```bash
# Save final state
kubectl get all -n nova -l app=pgbouncer > pgbouncer-final-state.txt
kubectl describe deployment pgbouncer -n nova > pgbouncer-deployment-details.txt

# Update documentation
echo "Migration completed: $(date)" >> MIGRATION_HISTORY.md
```

## Rollback Procedure

If issues occur, rollback is simple:

```bash
# Revert all services to direct PostgreSQL
for svc in identity-service notification-service cdn-service \
           auth-service messaging-service events-service \
           communication-service feed-service content-service \
           user-service graphql-gateway search-service \
           video-service social-service streaming-service media-service; do
  kubectl set env deployment/$svc \
    DATABASE_URL="postgresql://nova_user:password@postgres:5432/nova" \
    -n nova
done

# Wait for rollout
kubectl rollout status deployment --all -n nova

# Verify connectivity
kubectl exec deployment/identity-service -n nova -- \
  psql -c "SELECT 1"
```

## Post-Migration

### Decommissioning Old Connection Pools

Once all services are using PgBouncer (48+ hours), you can:

1. Reduce application-level `max_connections` from 16 to 4-8
   - Applications no longer need to maintain their own connection pool
   - PgBouncer handles pooling

2. Example Rust update:
   ```rust
   // OLD: max_connections(16) - for direct PostgreSQL
   // NEW: max_connections(4) - PgBouncer handles multiplexing
   let pool = PgPoolOptions::new()
       .max_connections(4)  // Reduced from 16
       .connect(&database_url)
       .await?;
   ```

3. Scale down PostgreSQL replicas if applicable (you now have headroom)

## Monitoring Checklist

After each phase, verify:

- [ ] Pod is `Running` and `Ready`
- [ ] No errors in pod logs
- [ ] PgBouncer pool shows idle connections
- [ ] Application health checks passing
- [ ] Database queries executing normally
- [ ] No connection timeouts
- [ ] Response times normal (within 10% of baseline)
- [ ] Error rate normal (0%)

## Troubleshooting

### Connection Refused

**Symptom:** `psql: error: could not connect to server`

**Solution:**
```bash
# Check PgBouncer is running
kubectl get pods -n nova -l app=pgbouncer

# Check service is accessible
kubectl get svc pgbouncer -n nova

# Test from pod
kubectl run debug --image=postgres:16 -it --rm -- \
  psql postgresql://nova_user:password@pgbouncer:6432/nova -c "SELECT 1"
```

### High Latency

**Symptom:** Response times 5-10x slower than before

**Solution:**
```bash
# Check pool saturation
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# If cl_waiting > 0: increase default_pool_size
# Edit configmap and restart: kubectl rollout restart deployment/pgbouncer
```

### Authentication Failures

**Symptom:** `auth failed for user "nova_user"`

**Solution:**
```bash
# Verify Secret is mounted
kubectl describe pod <pgbouncer-pod> -n nova | grep pgbouncer-userlist

# Check Secret content
kubectl get secret pgbouncer-userlist -n nova -o yaml

# Verify PostgreSQL has same user
kubectl exec postgres -n nova -- \
  psql -c "\du" | grep nova_user
```

See `TROUBLESHOOTING.md` for more issues.
