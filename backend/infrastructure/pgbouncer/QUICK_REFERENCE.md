# PgBouncer Quick Reference Card

## One-Page Cheat Sheet

### Connection Strings

```bash
# Your application code
DATABASE_URL=postgresql://nova_user:password@pgbouncer:6432/nova
```

### Container Commands

```bash
# Docker: Start PgBouncer + PostgreSQL
docker-compose up -d

# Docker: Check pool
docker exec nova-pgbouncer psql -U admin pgbouncer -c "SHOW POOLS"

# Docker: View logs
docker logs nova-pgbouncer
```

### Kubernetes Commands

```bash
# Deploy
kubectl apply -f k8s/infrastructure/pgbouncer/

# Check status
kubectl get pods -n nova -l app=pgbouncer

# View logs
kubectl logs deployment/pgbouncer -n nova

# Check pool
kubectl exec svc/pgbouncer -n nova -- \
  psql -h 127.0.0.1 -p 6432 -U admin pgbouncer -c "SHOW POOLS"

# Check PostgreSQL connections (should be ~50)
kubectl exec postgres -n nova -- \
  psql -c "SELECT count(*) FROM pg_stat_activity"
```

### Admin Console

```bash
# Connect
psql postgresql://admin:password@pgbouncer:6432/pgbouncer

# Key commands inside admin console
SHOW POOLS              # Pool status
SHOW CLIENTS           # Connected clients
SHOW SERVERS           # Backend connections
SHOW STATS             # Statistics
RELOAD                 # Reload config
PAUSE                  # Pause (drain connections)
RESUME                 # Resume
```

### Testing

```bash
# Test basic connection
psql postgresql://nova_user:password@localhost:6432/nova -c "SELECT 1"

# Test with timing
time psql postgresql://nova_user:password@localhost:6432/nova -c "SELECT 1"

# Benchmark
./benchmark.sh

# Generate users
PGBOUNCER_NOVA_USER_PASS="pass" ./generate_userlist.sh
```

### Configuration Files

**Location:** `/etc/pgbouncer/pgbouncer.ini`

**Key Settings:**
```ini
pool_mode = transaction         # Mode (session/transaction/statement)
max_client_conn = 500           # Max clients (total)
default_pool_size = 50          # Connections per pool
min_pool_size = 10              # Keep-alive connections
server_idle_timeout = 600       # Return to pool after (sec)
query_timeout = 60              # Kill query after (sec)
```

### Pool Calculation

```
Total backend connections needed:
  = min(# replicas × default_pool_size, PostgreSQL max_connections)
  = min(2 × 50, 200)
  = 100 connections ✓

Client capacity:
  = max_client_conn × # replicas
  = 500 × 2 = 1000+ concurrent clients
```

### Performance Targets

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| TPS | >10k | <8k | <5k |
| Latency (avg) | <10ms | >20ms | >50ms |
| Latency (p99) | <100ms | >200ms | >500ms |
| Pool utilization | 50-80% | >90% | 100% |
| Waiting clients | 0 | >5 | >100 |

### Troubleshooting Matrix

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Connection refused | PgBouncer not running | `kubectl get pods -l app=pgbouncer` |
| Auth failed | Password mismatch | Regenerate userlist with `generate_userlist.sh` |
| High latency | Pool exhausted | Increase `default_pool_size` |
| Waiting clients | Not enough connections | Increase `default_pool_size` or `max_client_conn` |
| Memory growing | Too many idle connections | Reduce `min_pool_size` or `server_idle_timeout` |
| Query timeout | Query too slow | Increase `query_timeout` or optimize query |
| PostgreSQL limit | Too many backend connections | Reduce `default_pool_size` |

### Log Levels

```ini
verbose = 0  # Warnings only
verbose = 1  # + Connection events
verbose = 2  # + Server info (default)
verbose = 3  # + Useful info
verbose = 4  # + Full SQL
verbose = 5  # + SQL data
```

### Metrics to Monitor

**Prometheus Queries:**
```
# Pool utilization
pgbouncer_pools_servers_active / pgbouncer_pools_servers_idle

# Connection wait time
increase(pgbouncer_pools_client_connections_waiting_total[5m])

# Query latency
rate(pgbouncer_pools_query_duration_seconds_sum[5m]) / 
rate(pgbouncer_pools_query_duration_seconds_count[5m])

# Connection churn
rate(pgbouncer_pools_client_connections_closed_total[5m])
```

### Common Tasks

**Reload configuration without restart:**
```bash
psql -h pgbouncer -p 6432 -U admin pgbouncer -c "RELOAD"
```

**Pause new connections (maintenance):**
```bash
psql -h pgbouncer -p 6432 -U admin pgbouncer -c "PAUSE"
sleep 30  # Wait for connections to drain
# Do maintenance
psql -h pgbouncer -p 6432 -U admin pgbouncer -c "RESUME"
```

**Check which service is slow:**
```bash
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c \
  "SELECT application_name, count(*) as connections FROM pg_stat_activity \
   GROUP BY application_name"
```

**Get PgBouncer version:**
```bash
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SELECT 'PgBouncer version' as info"
```

## File Structure

```
backend/infrastructure/pgbouncer/
├── pgbouncer.ini              # Main configuration
├── userlist.txt.template      # User list template
├── generate_userlist.sh       # Generate SCRAM-SHA-256 hashes
├── docker-compose.yml         # Docker development setup
├── benchmark.sh               # Performance benchmark
├── README.md                  # Full documentation
├── MIGRATION_GUIDE.md         # Step-by-step migration
├── TROUBLESHOOTING.md         # Common issues
└── QUICK_REFERENCE.md         # This file

k8s/infrastructure/pgbouncer/
├── deployment.yaml            # Kubernetes Deployment
├── service.yaml               # Services
├── configmap.yaml             # Configuration
├── secret.yaml                # Secrets template
├── rbac.yaml                  # RBAC + NetworkPolicy
└── prometheus-exporter.yaml   # Monitoring
```

## Connection String Examples

**Rust/Tokio (sqlx):**
```rust
let url = "postgresql://nova_user:password@pgbouncer:6432/nova";
let pool = PgPoolOptions::new()
    .max_connections(4)  // Reduced from 16
    .connect(&url)
    .await?;
```

**Node.js (pg):**
```javascript
const pool = new Pool({
  user: 'nova_user',
  host: 'pgbouncer',
  port: 6432,
  password: 'password',
  database: 'nova'
});
```

**Python (psycopg2):**
```python
conn = psycopg2.connect(
  host="pgbouncer",
  port=6432,
  database="nova",
  user="nova_user",
  password="password"
)
```

**Java (JDBC):**
```java
String url = "jdbc:postgresql://pgbouncer:6432/nova";
Properties props = new Properties();
props.setProperty("user", "nova_user");
props.setProperty("password", "password");
```

## Migration Checklist

- [ ] Generate userlist with `generate_userlist.sh`
- [ ] Create Kubernetes Secret: `kubectl create secret generic pgbouncer-userlist ...`
- [ ] Deploy PgBouncer: `kubectl apply -f k8s/infrastructure/pgbouncer/`
- [ ] Test connection from pod
- [ ] Check pool status: `SHOW POOLS`
- [ ] Verify PostgreSQL connection count is ~50
- [ ] Update first service DATABASE_URL to use pgbouncer:6432
- [ ] Wait 5 minutes, verify no errors
- [ ] Update remaining services
- [ ] Monitor for 24 hours
- [ ] Reduce application max_connections from 16 to 4-8
- [ ] Document baseline metrics

## Important Notes

⚠️ **Security:**
- Never commit `userlist.txt` with passwords
- Use Kubernetes Secrets or vault
- Rotate passwords regularly
- Restrict Secret access with RBAC

⚠️ **Performance:**
- Increase `default_pool_size` if latency increases
- Reduce it if PostgreSQL hits connection limit
- Monitor both PgBouncer and PostgreSQL metrics

⚠️ **Backward Compatibility:**
- Pool mode must be `transaction` for microservices
- Application pool_size should be much smaller (4-8)
- Connection strings change to port 6432
