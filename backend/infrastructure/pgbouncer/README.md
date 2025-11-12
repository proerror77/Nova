# PgBouncer - PostgreSQL Connection Pool Proxy

**Version:** 1.21  
**Status:** Production Ready  
**Last Updated:** 2025-11-11

## Overview

This directory contains complete PgBouncer deployment configuration for solving PostgreSQL connection pool exhaustion in the Nova microservices architecture.

### Problem Statement

- **Current Setup:** 12+ microservices × 3 replicas × 16 connections per pool = **576 total connections**
- **PostgreSQL Limit:** `max_connections = 200`
- **Result:** Connection exhaustion, failed deployments, cascading failures

### Solution

Deploy PgBouncer (transaction mode) to multiplex 500+ client connections to 50 PostgreSQL backend connections.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│  12 Microservices (576 connections)                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
    ┌─────────┐   ┌─────────┐   ┌─────────┐
    │ PgBouncer    │ PgBouncer    │ PgBouncer  (replicas)
    │ 250 clients  │ 250 clients  │ 250 clients
    │ 25 conn pool │ 25 conn pool │ 25 conn pool
    └────┬────┘   └────┬────┘   └────┬────┘
         │             │             │
         └─────────────┼─────────────┘
                       │
              ┌────────▼────────┐
              │  PostgreSQL     │
              │  50 connections │
              │  max_conn = 200 │
              └─────────────────┘
```

## Features

✅ **Transaction-mode pooling** - optimal for microservices  
✅ **SCRAM-SHA-256 authentication** - secure password handling  
✅ **High availability** - 2 replicas with anti-affinity  
✅ **Health checks** - liveness, readiness, startup probes  
✅ **Graceful shutdown** - drains connections before restart  
✅ **Prometheus metrics** - complete observability  
✅ **Network policies** - security-first networking  
✅ **Production hardened** - resource limits, security context, etc.

## Quick Start

### Development (Docker Compose)

```bash
cd backend/infrastructure/pgbouncer

# Generate user list with SCRAM-SHA-256 hashes
PGBOUNCER_NOVA_USER_PASS="nova_password" \
PGBOUNCER_ADMIN_PASS="admin_password" \
./generate_userlist.sh

# Start PgBouncer and PostgreSQL
docker-compose up -d

# Test connection
psql postgresql://nova_user:nova_password@localhost:6432/nova -c "SELECT 1"

# Check pool status
psql postgresql://admin:admin_password@localhost:6432/pgbouncer -c "SHOW POOLS"
```

### Production (Kubernetes)

```bash
# 1. Generate user list
cd backend/infrastructure/pgbouncer
PGBOUNCER_NOVA_USER_PASS="..." \
PGBOUNCER_ADMIN_PASS="..." \
./generate_userlist.sh

# 2. Create Kubernetes Secret
kubectl create secret generic pgbouncer-userlist \
  --from-file=userlist.txt=./userlist.txt \
  -n nova

# 3. Deploy PgBouncer
kubectl apply -f k8s/infrastructure/pgbouncer/

# 4. Verify deployment
kubectl get pods -n nova -l app=pgbouncer
kubectl logs -f deployment/pgbouncer -n nova

# 5. Test connection from a pod
kubectl run -it --rm debug --image=postgres:16 --restart=Never -n nova -- \
  psql postgresql://nova_user:password@pgbouncer:6432/nova -c "SELECT 1"
```

## Configuration Files

| File | Purpose |
|------|---------|
| `pgbouncer.ini` | Main configuration (pools, timeouts, auth) |
| `userlist.txt.template` | User authentication template |
| `generate_userlist.sh` | Script to generate SCRAM-SHA-256 hashes |
| `docker-compose.yml` | Docker development setup |
| `k8s/deployment.yaml` | Kubernetes Deployment |
| `k8s/service.yaml` | Kubernetes Services |
| `k8s/configmap.yaml` | Configuration as ConfigMap |
| `k8s/secret.yaml` | Secret storage template |
| `k8s/rbac.yaml` | RBAC and network policies |
| `k8s/prometheus-exporter.yaml` | Prometheus metrics exporter |

## Key Parameters

### Pool Configuration

```ini
[pgbouncer]
# Per-pool settings
min_pool_size = 10        # Maintain at least 10 connections
default_pool_size = 50    # Target pool size
max_client_conn = 500     # Max client connections (total)
reserve_pool_size = 5     # Emergency pool
reserve_pool_timeout = 3  # Seconds to reach reserve
```

### Connection Timeouts

```ini
# Client-side
client_idle_timeout = 900      # Close idle clients after 15 min
login_timeout = 15             # Connection timeout

# Server-side
server_idle_timeout = 600      # Return connections to pool after 10 min
server_lifetime = 3600         # Max connection age (1 hour)
server_connect_timeout = 15    # Connection attempt timeout
```

### Query Limits

```ini
# Safety limits
query_timeout = 60            # Abort queries > 60 seconds
query_wait_timeout = 120      # Log queries > 120 seconds
```

## Authentication Setup

### Generate User List

```bash
# Create SCRAM-SHA-256 hashes
PGBOUNCER_NOVA_USER_PASS="secure_password_here" \
PGBOUNCER_ADMIN_PASS="secure_admin_password" \
PGBOUNCER_STATS_USER_PASS="stats_password" \
./generate_userlist.sh
```

The script generates `userlist.txt` with SCRAM-SHA-256 hashes:

```
"nova_user" "SCRAM-SHA-256$4096$<salt>$<storedkey>$<serverkey>"
"admin" "SCRAM-SHA-256$4096$<salt>$<storedkey>$<serverkey>"
"stats_user" "SCRAM-SHA-256$4096$<salt>$<storedkey>$<serverkey>"
```

### Security Notes

⚠️ **CRITICAL:**
- Never commit `userlist.txt` with real passwords to Git!
- Use Kubernetes Secrets or environment-based Secret storage
- Store passwords in a secure vault (HashiCorp Vault, AWS Secrets Manager, etc.)
- Rotate passwords regularly

## Connection String Format

### Application Microservices

Change from direct PostgreSQL connection to PgBouncer:

```bash
# OLD (direct PostgreSQL)
DATABASE_URL=postgresql://nova_user:password@postgres:5432/nova

# NEW (via PgBouncer)
DATABASE_URL=postgresql://nova_user:password@pgbouncer:6432/nova
```

### Rust/Tokio Applications

```rust
use sqlx::postgres::PgPoolOptions;

let database_url = "postgresql://nova_user:password@pgbouncer:6432/nova";

let pool = PgPoolOptions::new()
    .max_connections(16)  // Keep this unchanged
    .connect(&database_url)
    .await?;
```

Note: Application-level `max_connections` stays the same. PgBouncer handles multiplexing.

## Monitoring & Observability

### Health Checks

```bash
# Check PgBouncer status
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW POOLS"

# View client connections
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW CLIENTS"

# View server connections
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW SERVERS"

# View statistics
psql postgresql://admin:password@pgbouncer:6432/pgbouncer -c "SHOW STATS"
```

### Prometheus Metrics

PgBouncer exporter exposes metrics on port 9127:

- `pgbouncer_pools_clients_active` - Active client connections
- `pgbouncer_pools_clients_waiting` - Waiting client connections
- `pgbouncer_pools_servers_active` - Active server connections
- `pgbouncer_pools_servers_idle` - Idle server connections
- `pgbouncer_pools_queries_received` - Total queries received
- `pgbouncer_pools_query_time_avg` - Average query time

### Grafana Dashboard

Import dashboard template: `grafana-dashboard.json` (provided separately)

Key metrics to monitor:
- Connection pool utilization
- Query latency
- Connection wait time
- Server connection health

## Performance Tuning

### For High Throughput (>10k TPS)

```ini
[pgbouncer]
pool_mode = transaction
default_pool_size = 100      # Increase from 50
max_client_conn = 1000        # Increase from 500
pkt_buf = 8192                # Larger buffer
query_timeout = 120           # Longer timeout
```

### For Low Latency

```ini
[pgbouncer]
pool_mode = session           # More costly but lower latency
server_idle_timeout = 300     # Close idle connections faster
min_pool_size = 20            # Keep more warm connections
```

### For Memory Efficiency

```ini
[pgbouncer]
pool_mode = transaction       # Default, most efficient
default_pool_size = 25        # Reduce from 50
max_client_conn = 200         # Reduce from 500
server_idle_timeout = 300     # Close idle faster
```

## Troubleshooting

### Connection Refused

```bash
# Check PgBouncer is running
kubectl get pods -n nova -l app=pgbouncer

# Check logs
kubectl logs deployment/pgbouncer -n nova

# Verify service is exposed
kubectl get svc pgbouncer -n nova
```

### High Latency

```bash
# Check query time
psql -c "SHOW STATS" postgresql://admin:pass@pgbouncer:6432/pgbouncer

# Check pool saturation
psql -c "SHOW POOLS" postgresql://admin:pass@pgbouncer:6432/pgbouncer

# If many "waiting" clients: increase default_pool_size
```

### Memory Usage Growing

```bash
# Check connections
psql -c "SHOW POOLS" postgresql://admin:pass@pgbouncer:6432/pgbouncer

# Check for idle connections
psql -c "SHOW SERVERS" postgresql://admin:pass@pgbouncer:6432/pgbouncer

# Reduce timeout to close idle connections faster
# Or reduce default_pool_size
```

## Migration Guide

See `MIGRATION_GUIDE.md` for step-by-step migration instructions.

## Troubleshooting Guide

See `TROUBLESHOOTING.md` for common issues and solutions.

## References

- [PgBouncer Official Documentation](https://www.pgbouncer.org/)
- [PostgreSQL Connection Pooling](https://wiki.postgresql.org/wiki/Number_Of_Database_Connections)
- [Transaction vs Session Pooling](https://www.pgbouncer.org/usage.html)

## Support

For issues or questions:
1. Check `TROUBLESHOOTING.md`
2. Review logs: `kubectl logs deployment/pgbouncer -n nova`
3. Check health: `psql postgresql://admin:pass@pgbouncer:6432/pgbouncer -c "SHOW POOLS"`
