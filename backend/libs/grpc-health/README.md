# gRPC Health Check Library

Production-ready health check implementation for Kubernetes liveness and readiness probes. Implements the standard `grpc.health.v1` protocol using tonic-health.

## Features

- ✅ **Standard Protocol**: Implements `grpc.health.v1.Health` service
- ✅ **Built-in Checks**: PostgreSQL, Redis, and Kafka health checks
- ✅ **Background Monitoring**: Periodic health check execution
- ✅ **Easy Integration**: Builder pattern for quick setup
- ✅ **Kubernetes Ready**: Works with gRPC probes in Kubernetes 1.24+
- ✅ **Extensible**: Custom health checks via `HealthCheck` trait

## Quick Start

Add to your service's `Cargo.toml`:

```toml
[dependencies]
grpc-health = { path = "../libs/grpc-health" }
```

### Basic Usage

```rust
use grpc_health::HealthManagerBuilder;
use std::sync::Arc;
use std::time::Duration;
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize dependencies
    let pg_pool = sqlx::PgPool::connect(&database_url).await?;
    let redis_client = redis::Client::open(redis_url)?
        .get_connection_manager()
        .await?;

    // Create health manager with built-in checks
    let (health_manager, health_service) = HealthManagerBuilder::new()
        .with_postgres(pg_pool.clone())
        .with_redis(redis_client.clone())
        .with_kafka("localhost:9092")
        .build()
        .await;

    // Start background health checks (every 10 seconds)
    let health_manager = Arc::new(tokio::sync::Mutex::new(health_manager));
    grpc_health::HealthManager::start_background_check(
        health_manager.clone(),
        Duration::from_secs(10),
    );

    // Add health service to your gRPC server
    Server::builder()
        .add_service(health_service)  // Add BEFORE your other services
        .add_service(your_service)
        .serve(addr)
        .await?;

    Ok(())
}
```

## Built-in Health Checks

### PostgreSQL
Executes `SELECT 1` to verify database connectivity.

```rust
use grpc_health::PostgresHealthCheck;
use sqlx::PgPool;

let pool = PgPool::connect(&database_url).await?;
let check = PostgresHealthCheck::new(pool);
```

### Redis
Sends `PING` command to verify cache connectivity.

```rust
use grpc_health::RedisHealthCheck;

let client = redis::Client::open(redis_url)?;
let manager = client.get_connection_manager().await?;
let check = RedisHealthCheck::new(manager);
```

### Kafka
Fetches cluster metadata to verify message queue connectivity.

```rust
use grpc_health::KafkaHealthCheck;

let check = KafkaHealthCheck::new("localhost:9092,localhost:9093");
```

## Custom Health Checks

Implement the `HealthCheck` trait:

```rust
use grpc_health::{HealthCheck, HealthCheckError, Result};
use async_trait::async_trait;

struct MyCustomCheck {
    // Your dependencies
}

#[async_trait]
impl HealthCheck for MyCustomCheck {
    async fn check(&self) -> Result<()> {
        // Your health check logic
        if everything_ok() {
            Ok(())
        } else {
            Err(HealthCheckError::generic("Something is wrong"))
        }
    }
}

// Register it
let (manager, service) = HealthManager::new();
manager.register_check(Box::new(MyCustomCheck { /* ... */ })).await;
```

## Kubernetes Integration

### Deployment Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
spec:
  template:
    spec:
      containers:
      - name: user-service
        image: nova/user-service:latest
        ports:
        - containerPort: 50051
          name: grpc

        # Startup Probe (initial startup check)
        startupProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30  # 30 × 5s = 150s max startup time

        # Liveness Probe (restart if unhealthy)
        livenessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        # Readiness Probe (remove from service if not ready)
        readinessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
```

### Testing Health Checks

Using `grpcurl`:

```bash
# Check overall health
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# Check specific service (if you set service-specific health)
grpcurl -plaintext -d '{"service":"user_service.UserService"}' \
  localhost:50051 grpc.health.v1.Health/Check

# Watch health status changes (streaming)
grpcurl -plaintext -d '{"service":""}' \
  localhost:50051 grpc.health.v1.Health/Watch
```

## Advanced Usage

### Manual Health Check Control

```rust
let (mut manager, service) = HealthManager::new();

// Register checks
manager.register_check(Box::new(PostgresHealthCheck::new(pool))).await;

// Manual check and update
manager.check_and_update().await;

// Execute checks without updating status
let result = manager.execute_checks().await;
match result {
    Ok(()) => println!("All healthy"),
    Err(e) => println!("Health check failed: {}", e),
}
```

### Background Check Configuration

```rust
use std::time::Duration;

// Check every 5 seconds
let handle = HealthManager::start_background_check(
    Arc::new(Mutex::new(manager)),
    Duration::from_secs(5),
);

// Later, stop background checks if needed
handle.abort();
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│             HealthManager                        │
│  ┌──────────────────────────────────────────┐  │
│  │  HealthReporter (tonic-health)           │  │
│  │  - set_service_status()                  │  │
│  │  - Manages gRPC health service           │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  Registered HealthChecks                 │  │
│  │  - PostgresHealthCheck                   │  │
│  │  - RedisHealthCheck                      │  │
│  │  - KafkaHealthCheck                      │  │
│  │  - Custom checks...                      │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌──────────────────────────────────────────┐  │
│  │  Background Task                         │  │
│  │  - Periodic execution                    │  │
│  │  - Status updates                        │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  gRPC Health Service  │
        │  (grpc.health.v1)     │
        └───────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │  Kubernetes Probes    │
        │  - Startup            │
        │  - Liveness           │
        │  - Readiness          │
        └───────────────────────┘
```

## Error Handling

All health checks return `Result<()>` with typed errors:

```rust
pub enum HealthCheckError {
    Database(String),      // PostgreSQL errors
    Cache(String),         // Redis errors
    MessageQueue(String),  // Kafka errors
    Generic(String),       // Custom check errors
}
```

## Testing

```bash
# Run all tests
cargo test -p grpc-health

# Run specific test
cargo test -p grpc-health test_health_manager_creation
```

## Performance Considerations

- **Connection Pools**: Health checks use existing connection pools (no extra connections)
- **Timeouts**: All checks have built-in timeouts (5 seconds for external calls)
- **Background Frequency**: Default 10 seconds, adjust based on your needs
- **Blocking Operations**: Kafka check runs in `spawn_blocking` to avoid blocking async runtime

## Troubleshooting

### Health checks always fail

1. **Check credentials**: Ensure connection strings are correct
2. **Network access**: Verify services are reachable from your pod
3. **Timeouts**: May need to increase timeout for slow connections

```rust
// Example: Increase background check interval
HealthManager::start_background_check(
    manager,
    Duration::from_secs(30),  // Check every 30s instead of 10s
);
```

### Pod keeps restarting

- **Liveness probe too aggressive**: Increase `failureThreshold` or `periodSeconds`
- **Startup time too long**: Use `startupProbe` with higher `failureThreshold`
- **Check logs**: `kubectl logs <pod> --previous` to see errors

### Service marked as not ready

- **Dependencies not available**: Check if PostgreSQL/Redis/Kafka are running
- **Readiness probe too strict**: Increase `failureThreshold`
- **Manual check**: Use `grpcurl` to debug health status

## Best Practices

1. **Use separate probes**: Startup for initialization, liveness for crashes, readiness for traffic
2. **Set realistic timeouts**: Account for slow database queries or network delays
3. **Monitor health metrics**: Export health status to Prometheus
4. **Graceful degradation**: Consider partial health (e.g., read-only mode if cache is down)
5. **Test in staging**: Verify probe configuration before production

## License

MIT
