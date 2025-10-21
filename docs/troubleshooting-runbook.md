# Troubleshooting Runbook

## Overview

This runbook provides step-by-step procedures for diagnosing and resolving common issues in Nova Streaming platform. Each section contains a specific scenario, diagnostic steps, and remediation procedures.

## Quick Reference

| Symptom | Likely Cause | Runbook |
|---------|-------------|---------|
| API returns 502/503 | Service down or overloaded | Scenario 1 |
| WebSocket connections drop | Network issues or service restart | Scenario 2 |
| RTMP broadcasts failing | RTMP server or firewall issues | Scenario 3 |
| Database query timeouts | Connection pool exhausted or slow queries | Scenario 4 |
| High memory usage | Memory leak or cache bloat | Scenario 5 |
| Prometheus metrics missing | Metrics collection disabled or exporter down | Metrics Troubleshooting |
| High error rates after deployment | Version incompatibility | Deployment Troubleshooting |

---

## Diagnostic Commands Quick Reference

```bash
# Health checks
curl http://localhost:8081/health | jq .
kubectl get nodes -o wide
kubectl get pods --all-namespaces | grep -v Running

# Logs
kubectl logs deployment/user-service -f
kubectl logs deployment/user-service --previous  # Previous pod logs
docker-compose logs -f user-service

# Metrics
curl http://localhost:8081/metrics | grep nova_streaming
prometheus query: rate(nova_http_errors_total[5m])

# Database
psql -h $DB_HOST -U $DB_USER -c "SELECT 1;"
psql -h $DB_HOST -U $DB_USER -c "SELECT count(*) FROM pg_stat_activity;"

# Network
curl -v https://api.nova-social.io/health
telnet $RTMP_HOST 1935
redis-cli -h $REDIS_HOST ping

# Kubernetes
kubectl get all -n production
kubectl describe pod <pod-name> -n production
kubectl exec -it <pod-name> -- bash
```

---

# Scenario 1: API Service Degradation or Unavailability

## Symptom

- API endpoints return 502/503 errors
- Response times exceed 5 seconds
- "Connection refused" errors
- Repeated error messages in logs

## Diagnostic Steps

### Step 1.1: Check Service Status

```bash
# Check if pods are running
kubectl get pods -n production -l app=user-service

# Expected output:
# user-service-xxxxxx  1/1  Running  0  5m

# If status is not Running:
# - Check events: kubectl describe pod <pod-name> -n production
# - Check logs: kubectl logs <pod-name> -n production
```

### Step 1.2: Verify Resource Availability

```bash
# Check node status
kubectl get nodes
# Expected: All nodes Ready

# Check resource requests are available
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
# Expected: CPU and memory available

# If nodes not ready or low on resources:
# - Cause: Node failure or resource exhaustion
# - Solution: See "Node Failure" section
```

### Step 1.3: Check Service Logs

```bash
# View recent logs
kubectl logs deployment/user-service -n production --tail=50 -f

# Look for:
# - "panic: " - service crashed
# - "thread 'main' panicked" - thread panic
# - "Error" entries - application errors
# - "database connection refused" - database down
# - "address already in use" - port conflict
```

### Step 1.4: Check Database Connectivity

```bash
# Verify database is responding
psql -h prod-db.nova-social.io -U nova_admin -c "SELECT version();"

# Check active connections
psql -h prod-db.nova-social.io -U nova_admin \
  -c "SELECT count(*) as active_connections FROM pg_stat_activity;"

# Expected: < 90% of max_connections
# If == max_connections: Connection pool exhausted (see Scenario 4)
```

### Step 1.5: Check Load Balancer

```bash
# Verify load balancer is routing traffic
kubectl get svc user-service -n production -o wide
# Expected: EXTERNAL-IP assigned, endpoints listed

# Test direct pod access
POD_IP=$(kubectl get pod <pod-name> -n production \
  -o jsonpath='{.status.podIP}')
curl http://$POD_IP:8081/health

# If pod responds but service doesn't:
# - Cause: Load balancer or network policy issue
# - Solution: Check network policies and load balancer rules
```

## Remediation Procedures

### If Service Not Running

```bash
# Check pod restart count
kubectl get pods -n production -l app=user-service \
  -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'

# If high restart count (> 5 in 1 hour):
# Service is crashing repeatedly
# 1. Check logs for panic messages: kubectl logs --previous <pod-name>
# 2. Check recent code changes: git log -5 --oneline
# 3. Rollback if recent deployment: kubectl rollout undo deployment/user-service

# If restart count normal but pod not running:
# 1. Check node has resources: kubectl describe nodes
# 2. Check pod events: kubectl describe pod <pod-name>
# 3. If "CrashLoopBackOff": fix application error and redeploy
```

### If High CPU Usage

```bash
# Check CPU usage
kubectl top pods -n production -l app=user-service

# If CPU > 80%:

# Option 1: Scale horizontally
kubectl scale deployment user-service -n production --replicas=5

# Option 2: Identify slow endpoints
curl -s http://localhost:8081/metrics | grep nova_http_request_duration_seconds_bucket | tail -20

# Option 3: Profile the service
# Enable profiling in code, then:
curl http://localhost:8081/debug/pprof/profile > profile.prof
go tool pprof profile.prof

# Option 4: Reduce load by circuit breaking
# Implement rate limiting or fail-fast for dependent services
```

### If High Memory Usage

```bash
# Check memory usage
kubectl top pods -n production -l app=user-service

# If memory > 80% of limit:

# Option 1: Increase memory limit (temporary)
kubectl set resources deployment user-service \
  -n production --limits=memory=2Gi

# Option 2: Find memory leak
# Check logs for growing collections
# Restart pod to reset baseline
kubectl rollout restart deployment/user-service -n production

# Option 3: Check for goroutine leaks
# Enable pprof metrics:
curl http://localhost:8081/debug/pprof/goroutine > goroutines.txt
sort goroutines.txt | uniq -c | sort -rn | head -20

# Option 4: Reduce concurrent connections
# Implement connection pooling limits
```

### Recovery Steps

```bash
# 1. Assess impact
echo "Current error rate:"
curl -s "http://prometheus:9090/api/v1/query?query=rate(nova_http_errors_total%5B5m%5D)" | jq '.data.result'

# 2. Apply fix
# - If deployment issue: kubectl rollout undo deployment/user-service
# - If resource issue: kubectl scale deployment user-service --replicas=5
# - If database issue: diagnose separately (Scenario 4)

# 3. Verify recovery
sleep 30
curl -s "http://prometheus:9090/api/v1/query?query=rate(nova_http_errors_total%5B5m%5D)" | jq '.data.result'
# Expected: error rate declining

# 4. Notify team
# "API service recovered. Current status: [OK/DEGRADED]. Root cause: [cause]"
```

---

# Scenario 2: WebSocket Connection Issues

## Symptom

- Viewers see "WebSocket disconnected" errors
- Connections drop randomly
- Reconnection attempts fail
- "Connection refused" or "Connection reset by peer"

## Diagnostic Steps

### Step 2.1: Verify WebSocket Service

```bash
# Test WebSocket endpoint directly
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  'ws://localhost:8081/api/v1/streams/test-stream/ws?token=test'

# Expected response:
# HTTP/1.1 101 Switching Protocols
# Upgrade: websocket
# Connection: Upgrade

# If not 101:
# - 400: Invalid stream ID or missing token
# - 401: Invalid or expired token
# - 404: Stream not found
# - 500: Service error (check logs)
```

### Step 2.2: Check WebSocket Handler Status

```bash
# Check if WebSocket handler is accepting connections
kubectl logs deployment/user-service -n production \
  | grep -i websocket | tail -20

# Look for:
# - "WebSocket connection established" - normal
# - "WebSocket connection closed" - possibly high churn
# - "connection reset by peer" - client disconnect
# - "panicked" - handler panic
```

### Step 2.3: Monitor Active Connections

```bash
# Check number of active WebSocket connections
curl -s http://localhost:8081/metrics | grep websocket_connections

# Expected: matches number of connected viewers
# If 0 while viewers trying to connect: service issue
# If very high and growing: possible connection leak
```

### Step 2.4: Check Network Connectivity

```bash
# Test network path to service
traceroute api.nova-social.io

# Check firewall rules
# - Port 443 (HTTPS/WSS) should be open
# - Port 8081 (local HTTP/WS) should be accessible within cluster

# If using load balancer, verify:
# - Load balancer configured for WebSocket upgrades
# - Keep-alive configured (should be > 30 seconds)
# - Idle timeout configured (should be > 1 hour for persistent connections)
```

### Step 2.5: Analyze Disconnection Patterns

```bash
# Check for sudden disconnection spikes
curl -s 'http://prometheus:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(websocket_disconnects_total[5m])' \
  --data-urlencode 'start=1697900000' \
  --data-urlencode 'end=1697903600' \
  --data-urlencode 'step=60'

# If spike at specific time:
# - Check deployment timeline
# - Check service restart logs
# - Check network configuration changes
```

## Remediation Procedures

### Connection Refused

```bash
# Cause: Service not listening on port
# Solution:

# 1. Verify service is running
kubectl get pods -n production -l app=user-service

# 2. Check port binding
kubectl exec -it <pod-name> -n production -- netstat -tln | grep 8081

# 3. If not listening, restart service
kubectl rollout restart deployment/user-service -n production

# 4. Verify port is open in load balancer
kubectl get svc user-service -n production -o yaml | grep -A 10 "ports:"
```

### Connection Resets During Active Session

```bash
# Cause: Typically network issue, service restart, or idle timeout

# 1. Check service stability
kubectl get pods -n production -l app=user-service \
  -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
# If > 1 in past hour: service restarting

# 2. Check network policy
kubectl get networkpolicies -n production

# 3. Check load balancer timeout settings
# WebSocket requires:
# - Idle timeout: > 1 hour
# - Keep-alive: enabled (30 second pings recommended)

# 4. Implement client-side retry logic
# with exponential backoff:
// JavaScript
const MAX_RETRIES = 5;
let retries = 0;
ws.addEventListener('close', () => {
  if (retries < MAX_RETRIES) {
    const delay = 1000 * Math.pow(2, retries);
    setTimeout(() => { ws.connect(); }, delay);
    retries++;
  }
});
```

### High Connection Churn

```bash
# Cause: Many clients connecting/disconnecting

# 1. Check connection spike timing
curl -s 'http://prometheus:9090/api/v1/query_range' \
  --data-urlencode 'query=websocket_connections' \
  --data-urlencode 'start=1697900000' \
  --data-urlencode 'end=1697903600' \
  --data-urlencode 'step=60' | jq .

# 2. If correlated with deployment:
# - Client may be restarting
# - Implement gradual rollout to reduce reconnections

# 3. If random churn:
# - May indicate client-side issues
# - Check client logs for errors

# 4. Increase performance
# - Add more WebSocket handler threads
# - Scale service horizontally
```

### Memory Leak in WebSocket Handler

```bash
# Symptom: Memory grows over time as connections come and go

# 1. Check memory trend
kubectl top pod <pod-name> -n production --containers
# Run for 10 minutes, watch for growth

# 2. If memory growing:
# - Check for goroutine leak
curl http://localhost:8081/debug/pprof/goroutine > goroutines.txt
# Count goroutines before and after connections

# 3. Temporary solution: restart pods
kubectl rollout restart deployment/user-service -n production

# 4. Long-term solution:
# - Fix goroutine leak in code
# - Add connection pool cleanup
# - Add resource limits
```

---

# Scenario 3: RTMP Broadcasting Failures

## Symptom

- RTMP broadcasts fail to connect
- Stream creation fails
- "RTMP connection refused" errors
- FFmpeg exits with "Connection timed out"

## Diagnostic Steps

### Step 3.1: Verify RTMP Server

```bash
# Check if Nginx-RTMP is running
docker ps | grep nginx-rtmp
kubectl get pods -n production -l app=nginx-rtmp

# Test RTMP port
telnet localhost 1935
# Expected: connection successful, "RTMP" banner appears

# Or use nc
nc -zv localhost 1935
```

### Step 3.2: Check RTMP Server Logs

```bash
# Check Nginx-RTMP logs
docker-compose logs nginx-rtmp | tail -50
# Or:
kubectl logs deployment/nginx-rtmp -n production -f

# Look for:
# - "bind() to 0.0.0.0:1935 failed" - port conflict
# - "upstream timed out" - backend timeout
# - "connect() failed" - cannot connect to backend
```

### Step 3.3: Verify Backend Connectivity

```bash
# From RTMP pod, verify can reach user-service
kubectl exec -it <nginx-rtmp-pod> -n production -- \
  curl http://user-service:8081/health

# If fails: network connectivity issue
# Check network policies:
kubectl get networkpolicies -n production
```

### Step 3.4: Test RTMP Connection

```bash
# Using FFmpeg, attempt connection
ffmpeg -rtmp_live live -i rtmp://localhost:1935/live/test \
  -c:v libx264 -preset fast -b:v 2000k \
  -f lavfi -i color=blue:s=1280x720:d=5 2>&1 | head -30

# Expected: Successful connection, frames being sent
# If fails: Check error message

# Common errors:
# "Connection refused" - RTMP server not listening
# "Connection timed out" - Network/firewall issue
# "403 Forbidden" - Authentication failed
```

### Step 3.5: Verify Firewall Rules

```bash
# Check inbound rules allow RTMP (port 1935)
aws ec2 describe-security-groups --filters Name=group-name,Values=nova-production

# Check egress rules allow response
# RTMP should be able to receive data from broadcasters

# Test from external machine:
# (Replace IP with actual Nginx-RTMP server)
ffmpeg -rtmp_live live -i rtmp://api.nova-social.io:1935/live/test \
  -c:v libx264 -f lavfi -i color=blue:s=1280x720:d=5 2>&1 | head -10
```

## Remediation Procedures

### RTMP Server Not Responding

```bash
# 1. Check if running
docker ps | grep nginx-rtmp
# If not running: docker-compose up -d nginx-rtmp

# 2. Check port binding
docker port nginx-rtmp | grep 1935
# Expected: 0.0.0.0:1935

# 3. Check logs for startup errors
docker logs nginx-rtmp | tail -50

# 4. If still failing, restart
docker restart nginx-rtmp
docker logs nginx-rtmp -f
```

### Connection Timeout

```bash
# Cause: Network path blocked or service behind firewall

# 1. Check if reachable from client
ping api.nova-social.io
traceroute api.nova-social.io

# 2. Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxxxx

# 3. Add inbound rule if missing
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxx \
  --protocol tcp \
  --port 1935 \
  --cidr 0.0.0.0/0

# 4. Test again
ffmpeg -rtmp_live live -i rtmp://api.nova-social.io:1935/live/test ...
```

### RTMP Error 403 (Authentication)

```bash
# Cause: Token invalid or expired

# 1. Generate new token
JWT_TOKEN=$(curl -X POST https://auth.nova-social.io/token \
  -d 'grant_type=password&username=user&password=pass' \
  | jq -r '.access_token')

# 2. Use token in RTMP URL
# Most RTMP servers support token in URL:
rtmp://api.nova-social.io:1935/live/test?token=$JWT_TOKEN

# Or in RTMP connect command (OBS):
Connect: rtmp://api.nova-social.io:1935/live
Stream Key: test?token=$JWT_TOKEN

# 3. Verify token expiry
curl -X POST https://auth.nova-social.io/validate \
  -H "Authorization: Bearer $JWT_TOKEN" | jq .
```

### Stream Not Created Automatically

```bash
# Cause: RTMP connects but stream not created in database

# 1. Check application logs
kubectl logs deployment/user-service -n production | grep -i "stream.*created"

# 2. Verify API health
curl http://localhost:8081/health | jq .

# 3. Check database connection
psql -h $DB_HOST -U nova_admin -c "SELECT 1;"

# 4. Manually create stream
curl -X POST http://localhost:8081/api/v1/streams \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test", "description": ""}'

# 5. Verify RTMP then creates connections to this stream
# Check logs for stream ID references
```

---

# Scenario 4: Database Issues

## Symptom

- Database queries timeout
- "Connection refused" or "too many connections"
- Slow API responses (> 5 seconds)
- Database locked errors

## Diagnostic Steps

### Step 4.1: Verify Database Connectivity

```bash
# Test database connection
psql -h prod-db.nova-social.io -U nova_user -d nova_streaming -c "SELECT 1;"

# Expected: "1" returned immediately

# If connection refused:
# - Database not running
# - Wrong hostname/port
# - Network access denied
```

### Step 4.2: Check Connection Pool Status

```bash
# Count active connections
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT datname, usename, count(*) FROM pg_stat_activity GROUP BY datname, usename;"

# Check against max_connections setting
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SHOW max_connections;"

# If active connections > 80% of max:
# - Connection pool may be exhausted soon
# - Check for connection leaks in application
```

### Step 4.3: Identify Long-Running Queries

```bash
# Find queries running > 5 seconds
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT query, now() - query_start as duration FROM pg_stat_activity WHERE query_start < now() - interval '5 seconds';"

# Kill long-running query if needed
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query_start < now() - interval '10 minutes';"
```

### Step 4.4: Check Database Lock Status

```bash
# Find blocked queries
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT * FROM pg_locks WHERE NOT granted;"

# Find lock holders and waiters
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT l1.pid, l1.usename, l2.pid, l2.usename FROM pg_locks l1 JOIN pg_locks l2 ON l1.locktype = l2.locktype AND l1.waiters WHERE l1.granted AND NOT l2.granted;"
```

### Step 4.5: Check Query Performance

```bash
# Enable query logging (temporarily)
psql -h prod-db.nova-social.io -U nova_admin -c \
  "ALTER SYSTEM SET log_min_duration_statement = 1000;"
# Restart database to apply

# Monitor slow query log
tail -f /var/log/postgresql/postgresql.log | grep "duration:"

# Analyze slow queries
psql -h prod-db.nova-social.io -U nova_admin -c \
  "EXPLAIN ANALYZE SELECT * FROM streams WHERE status = 'active';"
```

## Remediation Procedures

### Connection Pool Exhausted

```bash
# Cause: Connection leak in application or too many connections

# Temporary solution:
# 1. Increase max_connections
psql -h prod-db.nova-social.io -U nova_admin -c \
  "ALTER SYSTEM SET max_connections = 200;"

# 2. Restart database
sudo systemctl restart postgresql
# Or for RDS:
# aws rds modify-db-instance --db-instance-identifier nova-prod --apply-immediately

# 3. Restart application to reset connection pool
kubectl rollout restart deployment/user-service -n production

# Long-term solution:
# 1. Fix connection leak in code
# 2. Implement connection pool monitoring
# 3. Set proper pool size limits
```

### Slow Query Performance

```bash
# 1. Identify slow query
SLOW_QUERY="SELECT * FROM streams WHERE status = 'active';"

# 2. Analyze query plan
psql -h prod-db.nova-social.io -U nova_admin -c \
  "EXPLAIN ANALYZE $SLOW_QUERY;"

# Look for:
# - Sequential scans (should be index scan)
# - High cost estimates
# - Many rows returned

# 3. Add index if needed
psql -h prod-db.nova-social.io -U nova_admin -c \
  "CREATE INDEX idx_streams_status ON streams(status);"

# 4. Analyze table
psql -h prod-db.nova-social.io -U nova_admin -c \
  "ANALYZE streams;"

# 5. Retry query
time psql -h prod-db.nova-social.io -U nova_admin -c "$SLOW_QUERY;"
# Should be faster now
```

### Database Lock Contention

```bash
# 1. Identify locked table
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT relation::regclass, mode, granted FROM pg_locks WHERE NOT granted;"

# 2. Find lock holder
# From earlier query identifying blocked PIDs

# 3. Kill blocking query (CAREFULLY)
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = 12345;"

# 4. Wait for application to recover
sleep 10

# 5. Check if locked queries completed
psql -h prod-db.nova-social.io -U nova_admin -c \
  "SELECT * FROM pg_locks WHERE NOT granted;"
# Expected: empty result
```

---

# Scenario 5: High Memory Consumption

## Symptom

- Service OOM killed
- Memory usage > 90% of limit
- Kubernetes pod evicted due to memory pressure
- Service performance degrading

## Diagnostic Steps

### Step 5.1: Check Current Memory Usage

```bash
# Check pod memory
kubectl top pods -n production -l app=user-service

# Expected: < 70% of limit (e.g., 700MB of 1Gi)

# Check node memory
kubectl top nodes

# Expected: < 80% of available
```

### Step 5.2: Identify Memory Trend

```bash
# Query Prometheus for memory growth
curl -s 'http://prometheus:9090/api/v1/query_range' \
  --data-urlencode 'query=container_memory_working_set_bytes{pod="user-service"}' \
  --data-urlencode 'start=1697900000' \
  --data-urlencode 'end=1697903600' \
  --data-urlencode 'step=60' | jq '.data.result[0].values | tail -20'

# If memory grows linearly: memory leak suspected
# If memory stable: normal operation
```

### Step 5.3: Analyze Memory Profile

```bash
# Enable Go pprof profiling
curl http://localhost:8081/debug/pprof/heap > heap.prof

# Analyze heap profile
go tool pprof -http=:6060 heap.prof
# Visit http://localhost:6060/ui/ in browser

# Look for:
# - Allocations in specific functions
# - Unreleased allocations (red nodes)
# - Large object retention
```

### Step 5.4: Check for Goroutine Leaks

```bash
# Get goroutine count
curl http://localhost:8081/debug/pprof/goroutine?debug=1 | grep "goroutine"

# Expected: ~ 50-100 goroutines (stable)
# If > 1000 and growing: likely goroutine leak

# Detailed goroutine profile
curl http://localhost:8081/debug/pprof/goroutine?debug=2 > goroutines.txt

# Find goroutines stuck in specific state
grep "goroutine" goroutines.txt | sort | uniq -c | sort -rn | head -10
```

### Step 5.5: Analyze Heap Objects

```bash
# Dump heap objects
curl http://localhost:8081/debug/pprof/heap?debug=2 > heap_dump.txt

# Find top allocations
grep "alloc_objects" heap_dump.txt | sort -rn | head -20

# Or using go tool
go tool pprof -alloc_objects http://localhost:8081/debug/pprof/heap
# (pprof) top
# (pprof) list functionName
```

## Remediation Procedures

### Immediate Memory Pressure

```bash
# 1. Restart pod to reset memory
kubectl rollout restart deployment/user-service -n production

# 2. Monitor memory after restart
kubectl top pods -n production -l app=user-service --watch

# 3. If memory grows again quickly: memory leak
# Otherwise: transient memory spike (normal)
```

### Memory Leak in Code

```bash
# 1. Identify leaking function from heap profile
go tool pprof heap.prof
# (pprof) list functionName

# 2. Fix common issues:
# - Goroutines not exiting: ensure defer calls cleanup
# - Slices not cleared: s = s[:0] to clear slice
# - Maps not cleared: delete from map
# - Connections not closed: ensure Close() called

# 3. Add memory test
// Test memory remains stable under load
#[test]
fn test_memory_stability() {
    for _ in 0..1000 {
        let stream = create_stream();
        drop(stream);
    }
    // Memory should not grow significantly
}

# 4. Redeploy with fix
docker build -t nova/user-service:v1.2.5 .
kubectl set image deployment/user-service \
  user-service=nova/user-service:v1.2.5

# 5. Verify memory stabilizes
kubectl top pods -n production -l app=user-service --watch
```

### Cache Bloat

```bash
# 1. Check Redis/cache size
redis-cli -h $REDIS_HOST INFO memory

# 2. If cache_used > 80% of cache_size:
redis-cli -h $REDIS_HOST FLUSHDB
# Warning: This clears all cache data

# 3. Verify cache clearing helped
redis-cli -h $REDIS_HOST INFO memory
# Should show low used memory now

# 4. Verify application still works
curl http://localhost:8081/health | jq .

# 5. Check cache growth rate
# If growing quickly, cache TTL may be too long
# Configure shorter TTL: EXPIRE key 300 (5 min)
```

### Increase Memory Limit

```bash
# If memory usage legitimate (not a leak):

# 1. Analyze peak memory usage
kubectl top pods -n production -l app=user-service

# 2. Increase limit to peak + 20%
# E.g., if peak is 800MB, set limit to 960MB
kubectl set resources deployment/user-service \
  -n production --limits=memory=960Mi

# 3. Monitor for OOM kills
kubectl get events -n production | grep "OOMKilled"

# 4. If still OOMing, increase further
# Otherwise, memory is appropriately sized

# 5. Long-term: optimize memory usage
# - Profile the service
# - Reduce object allocations
# - Implement cache eviction
# - Add data structure compression
```

---

## Additional Troubleshooting

### Metrics Troubleshooting

**Problem**: Prometheus metrics not appearing

```bash
# 1. Verify metrics endpoint
curl http://localhost:8081/metrics | head -20

# Expected: Prometheus format metrics

# 2. If empty response:
# - Metrics collection may be disabled
# - Check config: ENABLE_METRICS=true

# 3. Verify ServiceMonitor configured
kubectl get servicemonitor -n production
kubectl get servicemonitor prometheus-operator -n monitoring -o yaml | grep "user-service"

# 4. Check Prometheus scrape configuration
curl http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="nova-streaming")'

# 5. If target unhealthy:
# - Check service port: kubectl get svc user-service
# - Check network policy: kubectl get networkpolicy
# - Check firewall: check egress rules from Prometheus pod
```

### Deployment Troubleshooting

**Problem**: High error rate after deployment

```bash
# 1. Check deployment logs
kubectl logs deployment/user-service -n production | grep -i error | tail -20

# 2. Check recent code changes
git log -5 --oneline
git show HEAD | head -50

# 3. Compare metrics before/after
# Before:  error_rate < 0.1%
# After:   error_rate > 5%

# 4. Options:
# - Rollback: kubectl rollout undo deployment/user-service
# - Fix forward: fix code error and redeploy
# - Canary: route 10% traffic to new version first

# 5. If rollback chosen
kubectl rollout undo deployment/user-service -n production
kubectl rollout status deployment/user-service -n production

# 6. Verify error rate recovers
watch -n 5 'curl -s "http://prometheus:9090/api/v1/query?query=rate(nova_http_errors_total%5B5m%5D)" | jq .'
```

---

## Escalation Path

```
Issue Detected
    │
    ├─ Severity: CRITICAL (API down, data loss)
    │   └─ → IMMEDIATE: Page on-call engineer
    │       → Execute emergency rollback
    │       → Open war room
    │
    ├─ Severity: HIGH (Errors > 5%, performance degraded)
    │   └─ → Page senior engineer
    │       → Investigate root cause (max 30 min)
    │       → Prepare fix or rollback
    │
    ├─ Severity: MEDIUM (Errors 1-5%, some impact)
    │   └─ → Alert platform team
    │       → Investigate during business hours
    │       → Fix in next release
    │
    └─ Severity: LOW (Errors < 1%, no impact)
        └─ → Log issue for future analysis
            → No immediate action required
```

---

## Support Contact

For issues not covered in this runbook:

- **On-call Engineer**: [Page on-call]
- **Platform Team**: #nova-platform Slack
- **GitHub Issues**: [Nova Repository Issues]
- **Documentation**: [Nova Docs]
- **Post-Mortems**: [Post-Mortem Repository]

---

## Runbook Updates

This runbook should be updated when:

- New issues discovered in production
- Procedures become outdated
- Team learns new diagnostic techniques
- Architecture changes

Last Updated: $(date)
Next Review: $(date -d "3 months")
