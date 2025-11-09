# Database Connection Pool

Unified PostgreSQL connection pool management with automatic Prometheus metrics monitoring.

## Features

- **Automatic pool sizing** - Pre-configured limits for each service based on traffic patterns
- **Connection health checks** - Test connections before use to prevent stale connection errors
- **Timeout protection** - Configurable timeouts for connection acquisition and verification
- **Prometheus metrics** - Built-in metrics for pool utilization, latency, and errors
- **Background monitoring** - Automatic metrics updates every 30 seconds

## Quick Start

```rust
use db_pool::{create_pool, DbConfig, acquire_with_metrics};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create pool with service-specific configuration
    let pool = create_pool(DbConfig::for_service("auth-service")).await?;

    // Use pool for queries
    let result = sqlx::query("SELECT * FROM users")
        .fetch_all(&pool)
        .await?;

    Ok(())
}
```

## Configuration

### Service-Specific Pools

Use `DbConfig::for_service()` for optimized connection limits:

```rust
let config = DbConfig::for_service("auth-service");
// Returns: max=16, min=5 (high-traffic service)

let config = DbConfig::for_service("video-service");
// Returns: max=4, min=1 (light-traffic service)
```

**Supported Services**:
- **High-traffic** (16-18 max): `auth-service`, `user-service`, `content-service`
- **Medium-high** (12 max): `feed-service`, `search-service`
- **Medium** (8 max): `media-service`, `notification-service`, `events-service`
- **Light** (3-4 max): `video-service`, `streaming-service`, `cdn-service`

### Environment Variable Overrides

```bash
export DATABASE_URL="postgres://user:pass@localhost/db"
export DB_MAX_CONNECTIONS=50
export DB_MIN_CONNECTIONS=10
export DB_ACQUIRE_TIMEOUT_SECS=5
export DB_CONNECT_TIMEOUT_SECS=3
export DB_IDLE_TIMEOUT_SECS=300
export DB_MAX_LIFETIME_SECS=1800
```

```rust
let config = DbConfig::from_env("my-service")?;
let pool = create_pool(config).await?;
```

### Custom Configuration

```rust
let config = DbConfig {
    service_name: "my-service".to_string(),
    database_url: "postgres://localhost/mydb".to_string(),
    max_connections: 20,
    min_connections: 5,
    connect_timeout_secs: 5,
    acquire_timeout_secs: 10,
    idle_timeout_secs: 600,
    max_lifetime_secs: 1800,
};

let pool = create_pool(config).await?;
```

## Metrics

### Exported Metrics

All metrics are automatically exported to Prometheus when the pool is created.

#### `db_pool_connections{service, state}`
Number of connections by state (active/idle/max).

```promql
# Current utilization
(db_pool_connections{state="active"} / db_pool_connections{state="max"}) * 100

# Services with no idle connections
db_pool_connections{state="idle"} == 0
```

#### `db_pool_acquire_duration_seconds{service}`
Histogram of connection acquisition latency.

```promql
# P95 acquisition latency
histogram_quantile(0.95, rate(db_pool_acquire_duration_seconds_bucket[5m]))

# P99 acquisition latency
histogram_quantile(0.99, rate(db_pool_acquire_duration_seconds_bucket[5m]))
```

#### `db_pool_connection_errors_total{service, error_type}`
Counter of connection errors by type (`timeout`, `closed`, `other`).

```promql
# Error rate by type
rate(db_pool_connection_errors_total[5m])

# Timeout errors only
rate(db_pool_connection_errors_total{error_type="timeout"}[5m])
```

### Using Metrics in Code

Use `acquire_with_metrics()` to track connection acquisition:

```rust
use db_pool::acquire_with_metrics;

// Automatically tracks acquisition latency and errors
let mut conn = acquire_with_metrics(&pool, "my-service").await?;

sqlx::query("SELECT * FROM users")
    .fetch_all(&mut *conn)
    .await?;
```

## Alerting

Pre-configured Prometheus alerts are available in `/prometheus/alerts/database.rules.yml`:

- **Critical**: Pool exhaustion (>90% utilization for 2min)
- **Critical**: Very slow acquisition (P95 > 5s for 1min)
- **Warning**: High utilization (>75% for 5min)
- **Warning**: Slow acquisition (P95 > 1s for 3min)
- **Warning**: Connection errors (>0.01/sec)
- **Info**: No idle connections (for 10min)

## Grafana Dashboard

Import `/prometheus/dashboards/database-pool-dashboard.json` to visualize:

- Connection pool utilization by service
- Active vs idle connections
- Connection acquisition latency (P95/P99)
- Error rates by type
- Top services by connection usage
- Acquisition latency heatmap

## Connection Limits Strategy

**Total PostgreSQL max_connections: 100** (default)

- **Reserved for system**: 20 connections
- **Available for application**: 80 connections
- **Current total allocation**: 111 connections (see optimization note below)

### Why These Limits?

Previous configuration allocated 263 total connections - **far exceeding** PostgreSQL's default 100 connection limit. This caused connection exhaustion in production.

New allocation strategy:
1. Reserve 20% for system overhead
2. Allocate remaining 80 based on traffic patterns
3. Scale per-service limits proportionally

**Note**: Current allocation (111) still exceeds the 80 target. Monitor production usage and reduce per-service limits if needed.

## Best Practices

### ✅ DO

- Use `DbConfig::for_service()` for automatic sizing
- Use `acquire_with_metrics()` to track performance
- Set connection timeouts appropriate for your use case
- Monitor pool utilization and adjust limits based on actual usage
- Test connections before use (enabled by default)

### ❌ DON'T

- Don't set `max_connections` higher than PostgreSQL's limit
- Don't ignore connection timeout errors (indicates pool undersizing)
- Don't use `.unwrap()` on pool operations
- Don't create multiple pools for the same service (wastes connections)
- Don't disable `test_before_acquire` in production

## Troubleshooting

### Connection Timeouts

**Symptom**: `sqlx::Error::PoolTimedOut`

**Causes**:
1. Pool max_connections too low
2. Slow queries holding connections too long
3. Database overloaded

**Solutions**:
1. Check `db_pool_utilization_percent` metric
2. Analyze slow queries with `pg_stat_statements`
3. Increase `max_connections` if sustained high usage
4. Optimize queries to release connections faster

### Slow Acquisition

**Symptom**: P95 > 1s in `db_pool_acquire_duration_seconds`

**Causes**:
1. All connections busy
2. Network latency to database
3. Connection validation taking too long

**Solutions**:
1. Check if pool is near max capacity
2. Reduce `idle_timeout_secs` if connections become stale
3. Monitor `db_pool_connections{state="idle"}` - should be >0

### No Idle Connections

**Symptom**: `db_pool_connections{state="idle"} == 0` for extended period

**Causes**:
1. Sustained high traffic
2. Pool undersized for workload

**Solutions**:
1. Check if this is normal traffic or spike
2. Increase `max_connections` if sustained
3. Consider horizontal scaling if all services affected

## Development

### Running Tests

```bash
cd backend/libs/db-pool
cargo test
```

### Adding New Service

1. Add service name to `for_service()` match statement
2. Assign appropriate connection limits
3. Update total allocation test
4. Document in this README

## License

Same as parent project.
