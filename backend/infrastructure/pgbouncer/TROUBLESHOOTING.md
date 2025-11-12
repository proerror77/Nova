# PgBouncer Troubleshooting Guide

## Quick Diagnostics

### Is PgBouncer Running?

```bash
# Check pods
kubectl get pods -n nova -l app=pgbouncer

# Expected: 2 pods in "Running" state, "2/2 Ready"

# If not running:
kubectl describe pod <pod-name> -n nova
kubectl logs <pod-name> -n nova
```

### Can You Connect to PgBouncer?

```bash
# From your machine
psql postgresql://nova_user:password@localhost:6432/nova -c "SELECT 1"

# From a Kubernetes pod
kubectl run debug --image=postgres:16 -it --rm -- \
  psql postgresql://nova_user:password@pgbouncer:6432/nova -c "SELECT 1"

# Expected: "1" output

# If connection fails:
# 1. Check credentials in userlist.txt
# 2. Check network connectivity
# 3. Check firewall/security groups
```

### What's the Pool Status?

```bash
# Connect to PgBouncer admin console
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW POOLS"

# Read the output:
# cl_active   = currently connected clients
# cl_waiting  = clients waiting for a connection
# sv_active   = active server connections
# sv_idle     = idle server connections in pool
```

---

## Common Issues

### Issue 1: Connection Refused

**Symptom:**
```
ERROR: could not connect to server: Connection refused
```

**Root Causes & Solutions:**

#### 1.1: PgBouncer Not Running

```bash
# Check pod status
kubectl get pods -n nova -l app=pgbouncer

# If pod is not running:
kubectl describe pod <pod-name> -n nova

# Check logs for startup errors
kubectl logs <pod-name> -n nova | head -50
```

**Common startup errors:**
- `auth_file not found` → Verify Secret is mounted
- `listen address already in use` → Kill process on port 6432
- `invalid configuration` → Check pgbouncer.ini syntax

#### 1.2: Service Not Exposed

```bash
# Verify service exists
kubectl get svc pgbouncer -n nova

# Check endpoints
kubectl get endpoints pgbouncer -n nova

# If endpoints empty, pods aren't ready:
kubectl get pods -n nova -l app=pgbouncer
kubectl logs <pod-name> -n nova
```

#### 1.3: Network/Firewall Issues

```bash
# Test from a pod in the cluster
kubectl run debug --image=alpine --rm -it -- \
  sh -c 'echo test | nc -v pgbouncer.nova.svc.cluster.local 6432'

# Expected: "Connection successful"

# If failed:
# 1. Check NetworkPolicy
#    kubectl get networkpolicies -n nova
# 2. Verify DNS resolution
#    kubectl run debug --image=alpine --rm -it -- \
#      nslookup pgbouncer.nova.svc.cluster.local
```

**Solution:**
```bash
# Open firewall
kubectl port-forward svc/pgbouncer 6432:6432 -n nova

# Then connect to localhost:6432
psql postgresql://nova_user:password@localhost:6432/nova -c "SELECT 1"
```

### Issue 2: Authentication Failures

**Symptom:**
```
FATAL: auth failed for user "nova_user"
DETAIL: Incorrect password or invalid credentials
```

**Root Causes & Solutions:**

#### 2.1: Password Mismatch

```bash
# Verify password in Secret
kubectl get secret pgbouncer-userlist -n nova -o jsonpath='{.data.userlist\.txt}' | base64 -d

# The password hash should match what PostgreSQL has:
kubectl exec postgres -n nova -- \
  psql -c "SELECT usename, usesuper FROM pg_user WHERE usename = 'nova_user'"

# Regenerate userlist.txt if passwords don't match
cd backend/infrastructure/pgbouncer
PGBOUNCER_NOVA_USER_PASS="..." ./generate_userlist.sh

# Update Secret
kubectl delete secret pgbouncer-userlist -n nova
kubectl create secret generic pgbouncer-userlist \
  --from-file=userlist.txt=./userlist.txt -n nova

# Restart PgBouncer
kubectl rollout restart deployment/pgbouncer -n nova
```

#### 2.2: User Doesn't Exist in PostgreSQL

```bash
# Check PostgreSQL users
kubectl exec postgres -n nova -- psql -c "\du"

# If nova_user is missing, create it
kubectl exec postgres -n nova -- \
  psql -c "CREATE USER nova_user WITH PASSWORD 'password' CREATEDB"

# Then regenerate userlist.txt with same password
cd backend/infrastructure/pgbouncer
PGBOUNCER_NOVA_USER_PASS="password" ./generate_userlist.sh
```

#### 2.3: Auth Type Mismatch

```bash
# Check auth type in pgbouncer.ini
kubectl get configmap pgbouncer-config -n nova -o jsonpath='{.data.pgbouncer\.ini}' | grep auth_type

# If it says "scram-sha-256", user hashes must be SCRAM-SHA-256 format:
# "username" "SCRAM-SHA-256$4096$<base64-salt>$<base64-key>$<base64-sig>"

# If connecting with plain password fails, regenerate userlist:
./generate_userlist.sh
```

### Issue 3: High Latency

**Symptom:** Database queries taking 1-5+ seconds

**Root Causes & Solutions:**

#### 3.1: Connection Pool Exhausted

```bash
# Check pool status
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW POOLS"

# If `cl_waiting > 0`: clients are waiting for connections

# Increase pool size:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_DEFAULT_POOL_SIZE=100 -n nova

# Or edit ConfigMap:
kubectl edit configmap pgbouncer-config -n nova
# Change: default_pool_size = 100
# Then restart: kubectl rollout restart deployment/pgbouncer -n nova
```

#### 3.2: Slow PostgreSQL Queries

```bash
# Check slow query log
kubectl exec postgres -n nova -- \
  psql -c "SELECT query, mean_exec_time FROM pg_stat_statements \
           ORDER BY mean_exec_time DESC LIMIT 10"

# If queries are slow, optimize them:
# 1. Add indexes
# 2. Analyze query plans: EXPLAIN ANALYZE
# 3. Check PostgreSQL resource usage
```

#### 3.3: PgBouncer Query Timeout

```bash
# Check query_timeout setting
kubectl get configmap pgbouncer-config -n nova -o jsonpath='{.data.pgbouncer\.ini}' | grep query_timeout

# Default: 60 seconds

# If queries exceed timeout, increase it:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_QUERY_TIMEOUT=120 -n nova
```

**Diagnostic Query:**
```bash
# From admin console, check query wait time
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW STATS"

# If avg_query_time > 5000ms, something is slow
```

### Issue 4: Connection Leaks

**Symptom:** Connection count grows over time, eventually hits limit

**Root Causes & Solutions:**

#### 4.1: Application Not Closing Connections

```bash
# Check which application is holding connections
kubectl exec postgres -n nova -- \
  psql -c "SELECT pid, application_name, state, query FROM pg_stat_activity \
           WHERE state != 'idle' ORDER BY backend_start"

# Look for long-running queries or abandoned connections
```

**Solution:**
```rust
// Ensure connections are properly closed
// Using sqlx connection pool (best practice):
let pool = PgPoolOptions::new()
    .max_connections(4)
    .acquire_timeout(Duration::from_secs(5))
    .idle_timeout(Duration::from_secs(300))
    .connect(&database_url)
    .await?;

// Use `acquire()` correctly:
let conn = pool.acquire().await?;  // ✓ Automatically returned to pool

// Use `pool.execute()` for simple queries:
sqlx::query("SELECT 1")
    .execute(&pool)
    .await?;  // ✓ Automatically returns
```

#### 4.2: Idle Connections Not Being Closed

```bash
# Check server_idle_timeout setting
kubectl get configmap pgbouncer-config -n nova -o jsonpath='{.data.pgbouncer\.ini}' | grep server_idle_timeout

# Default: 600 seconds (10 minutes)

# Reduce to close idle connections faster:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_SERVER_IDLE_TIMEOUT=300 -n nova  # 5 minutes instead
```

### Issue 5: "Too many connections" Error

**Symptom:**
```
ERROR: too many connections for database "nova"
```

**Root Causes & Solutions:**

#### 5.1: Application Pool Size Too Large

```bash
# Check application configuration
kubectl get deployment <service-name> -n nova -o jsonpath='{.spec.template.spec.containers[].env[] | select(.name=="DATABASE_URL") | .value}'

# If max_connections > 4-8: reduce it
# Old (for direct PostgreSQL): max_connections=16
# New (with PgBouncer): max_connections=4-8 (PgBouncer multiplexes)

# Update application deployment:
kubectl set env deployment/<service-name> \
  MAX_DB_CONNECTIONS=4 -n nova
```

#### 5.2: PgBouncer Default Pool Size Too Large

```bash
# Check PgBouncer default_pool_size
kubectl get configmap pgbouncer-config -n nova -o jsonpath='{.data.pgbouncer\.ini}' | grep default_pool_size

# Reduce if PostgreSQL can't handle it:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_DEFAULT_POOL_SIZE=50 -n nova
```

#### 5.3: PostgreSQL max_connections Too Small

```bash
# Check PostgreSQL limit
kubectl exec postgres -n nova -- \
  psql -c "SHOW max_connections"

# Increase if needed:
kubectl exec postgres -n nova -- \
  psql -c "ALTER SYSTEM SET max_connections = 300"

# Then restart PostgreSQL
kubectl rollout restart deployment/postgres -n nova
```

### Issue 6: Memory Usage Growing

**Symptom:** PgBouncer pod memory usage increasing over time

**Root Causes & Solutions:**

#### 6.1: Too Many Idle Connections

```bash
# Check idle connections
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW SERVERS"

# If sv_idle > 50: reduce it
# Lower min_pool_size and server_idle_timeout:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_MIN_POOL_SIZE=5 \
  PGBOUNCER_SERVER_IDLE_TIMEOUT=300 -n nova
```

#### 6.2: Client Connection Accumulation

```bash
# Check client connections
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW CLIENTS"

# If connections not being closed, check:
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'pgbouncer'"

# Each should be idle, not holding locks
```

### Issue 7: Configuration Not Reloading

**Symptom:** Changes to pgbouncer.ini not taking effect

**Root Causes & Solutions:**

#### 7.1: ConfigMap Updated, But Pod Hasn't Reloaded

```bash
# Option 1: Restart PgBouncer pods
kubectl rollout restart deployment/pgbouncer -n nova

# Option 2: Reload configuration without restarting
# Connect to admin console and run:
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "RELOAD"

# Verify reload (or restart if needed)
kubectl logs deployment/pgbouncer -n nova | grep -i "reload\|restart"
```

#### 7.2: Syntax Error in pgbouncer.ini

```bash
# Check logs for syntax errors
kubectl logs deployment/pgbouncer -n nova | grep -i "error\|invalid"

# Fix the ConfigMap
kubectl edit configmap pgbouncer-config -n nova

# Restart to pick up changes
kubectl rollout restart deployment/pgbouncer -n nova

# Verify startup
kubectl logs deployment/pgbouncer -n nova | tail -20
```

### Issue 8: Connection Timeout

**Symptom:**
```
ERROR: timeout while trying to connect to server
```

**Root Causes & Solutions:**

#### 8.1: PostgreSQL Connection Timeout

```bash
# Check PostgreSQL is running
kubectl get pods -n nova -l app=postgres

# Check PostgreSQL is accepting connections
kubectl exec postgres -n nova -- \
  psql -c "SELECT 1"

# If slow, check resource usage
kubectl top pod <postgres-pod> -n nova
```

#### 8.2: Network Latency

```bash
# Check network latency
kubectl exec pgbouncer -n nova -- \
  ping postgres-service -c 5

# High latency (>100ms) indicates network issue
```

#### 8.3: Firewall/Security Group

```bash
# Verify connectivity from PgBouncer to PostgreSQL
kubectl exec <pgbouncer-pod> -n nova -- \
  telnet postgres-service 5432

# Expected: "Connected to postgres-service"
# Or: socket connection successful
```

### Issue 9: Clients Waiting for Connections

**Symptom:**
```bash
$ psql postgresql://nova_user:password@pgbouncer:6432/nova
waiting for a connection...
```

**Root Causes & Solutions:**

#### 9.1: All Pool Connections In Use

```bash
# Check which applications are holding connections
kubectl exec postgres -n nova -- \
  psql -c "SELECT datname, usename, count(*) FROM pg_stat_activity \
           GROUP BY datname, usename"

# If one service is using all connections:
# 1. Check if it has slow queries: EXPLAIN ANALYZE
# 2. Increase pool_size in pgbouncer.ini
# 3. Reduce connection timeout on client side
```

#### 9.2: PostgreSQL Connection Limit Reached

```bash
# Check PostgreSQL connections
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity"

# If near max_connections (200):
# 1. Check for idle connections: SELECT * FROM pg_stat_activity WHERE state = 'idle'
# 2. Terminate old idle: SELECT pg_terminate_backend(pid) FROM ...
# 3. Or increase PostgreSQL max_connections
```

#### 9.3: Reduce client_idle_timeout

```bash
# Set lower client_idle_timeout to free up connections:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_CLIENT_IDLE_TIMEOUT=300 -n nova  # 5 minutes
```

---

## Advanced Diagnostics

### Enable Verbose Logging

```bash
# Increase verbosity
kubectl set env deployment/pgbouncer \
  PGBOUNCER_VERBOSE=5 -n nova

# Check logs
kubectl logs deployment/pgbouncer -n nova -f

# Turn off when done:
kubectl set env deployment/pgbouncer \
  PGBOUNCER_VERBOSE=2 -n nova
```

### Query PgBouncer Statistics

```bash
# Connect to PgBouncer admin console
psql postgresql://admin:password@pgbouncer:6432/pgbouncer

# Useful commands:
SHOW POOLS;          # Connection pool status
SHOW CLIENTS;        # Connected clients
SHOW SERVERS;        # Server connections
SHOW STATS;          # Statistics (queries, connections)
SHOW DATABASES;      # Database configuration
SHOW USERS;          # Users
SHOW CONFIG;         # Current configuration

# Example:
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW STATS" | head -20
```

### Monitor PostgreSQL Backend Connections

```bash
# See what PgBouncer connections are doing in PostgreSQL
kubectl exec postgres -n nova -- \
  psql -c "SELECT application_name, count(*) FROM pg_stat_activity \
           WHERE application_name = 'pgbouncer' \
           GROUP BY application_name"

# Expected: 10-50 connections (depends on configuration)
```

---

## Health Check Commands

```bash
#!/bin/bash
# Comprehensive health check

echo "=== PgBouncer Pods ==="
kubectl get pods -n nova -l app=pgbouncer

echo "\n=== Service ==="
kubectl get svc pgbouncer -n nova

echo "\n=== Pool Status ==="
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

echo "\n=== PostgreSQL Connections ==="
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity"

echo "\n=== Recent Errors ==="
kubectl logs deployment/pgbouncer -n nova | grep -i error | tail -10

echo "\n=== PgBouncer Stats ==="
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW STATS"
```

---

## Getting Help

1. **Check logs first:**
   ```bash
   kubectl logs deployment/pgbouncer -n nova
   ```

2. **Gather diagnostics:**
   ```bash
   kubectl describe pod <pgbouncer-pod> -n nova
   kubectl get events -n nova | grep pgbouncer
   ```

3. **Review configuration:**
   ```bash
   kubectl get configmap pgbouncer-config -n nova -o yaml
   ```

4. **Check network:**
   ```bash
   kubectl get networkpolicies -n nova
   kubectl get svc -n nova
   ```
