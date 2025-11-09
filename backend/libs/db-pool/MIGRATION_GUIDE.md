# Migration Guide: Adding Metrics to Existing Services

This guide shows how to update existing services to use the new metrics-enabled connection pool.

## Breaking Change: `DbConfig::from_env()` now requires `service_name`

### Before
```rust
let config = DbConfig::from_env()?;
```

### After
```rust
let config = DbConfig::from_env("my-service")?;
```

## Step-by-Step Migration

### 1. Update `main.rs` or Pool Initialization

#### Option A: Using `for_service()` (Recommended)
```rust
use db_pool::{create_pool, DbConfig};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Automatically gets service-specific limits + service name
    let pool = create_pool(DbConfig::for_service("auth-service")).await?;

    // Metrics are automatically tracked
    // No additional code needed!

    Ok(())
}
```

#### Option B: Using `from_env()`
```rust
use db_pool::{create_pool, DbConfig};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Pass service name explicitly
    let config = DbConfig::from_env("auth-service")?;
    let pool = create_pool(config).await?;

    Ok(())
}
```

### 2. (Optional) Use `acquire_with_metrics()` for Better Tracking

If you want to track connection acquisition performance in specific handlers:

#### Before
```rust
let mut conn = pool.acquire().await?;
```

#### After
```rust
use db_pool::acquire_with_metrics;

let mut conn = acquire_with_metrics(&pool, "auth-service").await?;
```

**Note**: This is **optional**. The pool itself already tracks metrics automatically.

### 3. Add Prometheus Exporter (if not already present)

```toml
# Cargo.toml
[dependencies]
prometheus = "0.13"
actix-web-prometheus = "0.1"  # or your web framework's prometheus integration
```

```rust
use actix_web::{web, App, HttpServer};
use actix_web_prometheus::PrometheusMetricsBuilder;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let pool = create_pool(DbConfig::for_service("auth-service")).await?;

    let prometheus = PrometheusMetricsBuilder::new("auth_service")
        .endpoint("/metrics")
        .build()
        .unwrap();

    HttpServer::new(move || {
        App::new()
            .wrap(prometheus.clone())
            .app_data(web::Data::new(pool.clone()))
            // ... your routes
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
}
```

### 4. Update Prometheus Configuration

Add service to `/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'auth-service'
    static_configs:
      - targets: ['auth-service:8080']
    metrics_path: '/metrics'
```

### 5. Verify Metrics are Exported

```bash
# Check metrics endpoint
curl http://localhost:8080/metrics | grep db_pool

# Expected output:
# db_pool_connections{service="auth-service",state="active"} 5
# db_pool_connections{service="auth-service",state="idle"} 11
# db_pool_connections{service="auth-service",state="max"} 16
# db_pool_acquire_duration_seconds_bucket{service="auth-service",le="0.001"} 42
# ...
```

## Example Service Migrations

### Auth Service

```diff
// backend/auth-service/src/main.rs

- let pool = create_pool(DbConfig::from_env()?).await?;
+ let pool = create_pool(DbConfig::for_service("auth-service")).await?;
```

### User Service

```diff
// backend/user-service/src/main.rs

- let config = DbConfig::from_env()?;
+ let config = DbConfig::from_env("user-service")?;
  let pool = create_pool(config).await?;
```

### Custom Service

```diff
// backend/my-service/src/main.rs

  let config = DbConfig {
+     service_name: "my-service".to_string(),
      database_url: env::var("DATABASE_URL")?,
      max_connections: 20,
      // ... other fields
  };
  let pool = create_pool(config).await?;
```

## Testing Your Migration

### 1. Unit Tests
Ensure your service still compiles and passes tests:
```bash
cargo test
```

### 2. Integration Tests
Start your service locally and verify metrics:
```bash
cargo run

# In another terminal:
curl http://localhost:8080/metrics | grep db_pool_connections
```

### 3. Load Test (Optional)
Use `wrk` or `k6` to verify pool behavior under load:
```bash
# Install wrk
brew install wrk

# Run load test
wrk -t4 -c100 -d30s http://localhost:8080/api/health

# Check metrics during load
watch -n 1 'curl -s http://localhost:8080/metrics | grep db_pool_utilization'
```

## Rollback Plan

If you need to rollback, the old API still works if you:

1. Pin `db-pool` to previous version in `Cargo.toml`:
   ```toml
   db-pool = { path = "../libs/db-pool", version = "0.1.0", rev = "PREVIOUS_COMMIT_HASH" }
   ```

2. Remove `service_name` parameter from `from_env()`:
   ```rust
   let config = DbConfig::from_env()?;  // Old API
   ```

## FAQ

### Q: Do I need to change all `pool.acquire()` calls?
**A**: No. Only if you want fine-grained acquisition metrics. The pool itself already tracks overall metrics.

### Q: What if my service isn't in the pre-configured list?
**A**: Use `DbConfig::from_env("my-service")` or create a custom `DbConfig`. Default limits will apply (max=3, min=1).

### Q: Will metrics impact performance?
**A**: Negligible. Metrics updates happen:
- Every 30 seconds (background task)
- On each connection acquisition (atomic counter increment, ~10ns)

### Q: Can I disable metrics?
**A**: Not currently. Metrics are integral to production monitoring. If needed, you can fork `db-pool` and remove the metrics module.

### Q: How do I add my service to the pre-configured list?
**A**: Edit `backend/libs/db-pool/src/lib.rs`:
```rust
pub fn for_service(service_name: &str) -> Self {
    let (max, min) = match service_name {
        // Add your service here
        "my-service" => (10, 3),
        // ...
    };
    // ...
}
```

## Support

- **Documentation**: See [README.md](./README.md)
- **Issues**: File at https://github.com/your-org/nova/issues
- **Slack**: #database-team
