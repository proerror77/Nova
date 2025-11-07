# gRPC Patterns and Best Practices

## Connection Management

### GrpcClientPool Pattern (Recommended)
```rust
use grpc_clients::{config::GrpcConfig, AuthClient, GrpcClientPool};
use std::sync::Arc;

// Initialize once per service
let grpc_config = GrpcConfig::from_env()?;
let grpc_pool = Arc::new(GrpcClientPool::new(&grpc_config).await?);

// Create clients from pool
let auth_client = Arc::new(AuthClient::from_pool(grpc_pool.clone()));
```

### Legacy Direct Connection (For Migration)
```rust
use grpc_clients::AuthClient;

// Direct connection (less efficient, but backward compatible)
let auth_client = Arc::new(
    AuthClient::new(&config.auth_service_url).await?
);
```

## Batch API Pattern (N+1 Elimination)

### Problem: N+1 Query Pattern
```rust
// ❌ BAD: Makes N gRPC calls for N users
for user_id in user_ids {
    let exists = auth_client.user_exists(user_id).await?;
    if !exists {
        // mark for cleanup
    }
}
```

### Solution: Batch API
```rust
// ✅ GOOD: Makes 1 gRPC call for up to 100 users
let batch_size = 100;
for chunk in user_ids.chunks(batch_size) {
    let results = auth_client
        .check_users_exist_batch(chunk.to_vec())
        .await?;

    for (user_id, exists) in results {
        if !exists {
            // mark for cleanup
        }
    }
}
```

## Error Handling

### Proper Error Conversion
```rust
// In grpc/mod.rs
let user = auth_client
    .user_exists(user_id)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, user_id = %user_id, "auth-service error");
        error::AppError::GrpcClient(format!("Failed to check user: {}", e))
    })?;
```

### Status Code Mapping
```rust
// In middleware/error_handling.rs
AppError::GrpcClient(_) => (
    "server_error",
    error_types::error_codes::GRPC_CLIENT_ERROR
)
```

## Request Timeouts

### Recommended Timeouts
- **Existence Checks**: 500ms (fast path)
- **User Details**: 1000ms (more data)
- **Batch Operations**: 2000ms (processing multiple records)

```rust
pub struct AuthClient {
    client: TonicAuthServiceClient<Channel>,
    request_timeout: Duration,  // Set based on operation type
}
```

## Correlation ID Propagation

### Server-Side Interceptor
```rust
fn server_interceptor(
    mut req: tonic::Request<()>,
) -> Result<tonic::Request<()>, tonic::Status> {
    if let Some(val) = req.metadata().get("correlation-id") {
        if let Ok(s) = val.to_str() {
            req.extensions_mut().insert::<String>(s.to_string());
        }
    }
    Ok(req)
}

// Register with server
Server::builder()
    .add_service(
        MyServiceServer::with_interceptor(svc, server_interceptor)
    )
    .serve(addr)
    .await?;
```

### Client-Side Interceptor (in grpc-clients middleware)
Automatically adds correlation-id from current context to outgoing requests.

## Health Checks

### Service Registration
```rust
use tonic_health::server::health_reporter;

let (mut health, health_service) = health_reporter();
health
    .set_serving::<MyServiceServer<MyServiceImpl>>()
    .await;

Server::builder()
    .add_service(health_service)
    .add_service(my_service)
    .serve(addr)
    .await?;
```

### Health Check Endpoint
- **URL**: `grpc://service:PORT/grpc.health.v1.Health/Check`
- **Usage**: K8s liveness/readiness probes

## Service Discovery

### Port Convention
- **REST**: Configured via `PORT` env var (default: 8080, 8081, 8082, etc.)
- **gRPC**: Always `PORT + 1000` (9080, 9081, 9082, etc.)

### Environment Variables
```bash
# auth-service
AUTH_SERVICE_GRPC_URL=http://auth-service:9081

# In Kubernetes
- name: AUTH_SERVICE_GRPC_URL
  value: "http://auth-service.default.svc.cluster.local:9081"
```

## Testing Patterns

### Integration Tests with testcontainers
```rust
use testcontainers::{clients, images::postgres::Postgres};

#[tokio::test]
async fn test_orphan_cleanup() {
    // Start PostgreSQL
    let docker = clients::Cli::default();
    let postgres = docker.run(Postgres::default());
    let db_url = format!("postgres://postgres:postgres@localhost:{}/postgres",
                        postgres.get_host_port_ipv4(5432));

    // Run migrations
    let db = create_pool(&db_url).await.unwrap();

    // Create MockAuthClient
    let auth_client = Arc::new(MockAuthClient::new());

    // Test cleanup logic
    let deleted = service.cleanup_orphans(&db, &auth_client).await.unwrap();
    assert_eq!(deleted, expected_count);
}
```

### MockAuthClient for Unit Tests
```rust
pub struct MockAuthClient {
    deleted_users: Arc<RwLock<HashSet<Uuid>>>,
    batch_call_count: Arc<AtomicU32>,
}

impl MockAuthClient {
    pub fn mark_user_deleted(&self, user_id: Uuid) {
        self.deleted_users.write().unwrap().insert(user_id);
    }

    pub fn get_batch_call_count(&self) -> u32 {
        self.batch_call_count.load(Ordering::SeqCst)
    }
}
```

## Monitoring and Observability

### Prometheus Metrics
```rust
use prometheus::{register_counter, register_histogram, Counter, Histogram};

lazy_static! {
    static ref GRPC_REQUESTS: Counter = register_counter!(
        "grpc_requests_total",
        "Total gRPC requests"
    ).unwrap();

    static ref GRPC_DURATION: Histogram = register_histogram!(
        "grpc_request_duration_seconds",
        "gRPC request duration"
    ).unwrap();
}

// In middleware
let timer = GRPC_DURATION.start_timer();
let result = inner_call().await;
timer.observe_duration();
GRPC_REQUESTS.inc();
```

### Structured Logging
```rust
tracing::info!(
    service = "auth-service",
    user_id = %user_id,
    duration_ms = duration.as_millis(),
    "gRPC call completed"
);
```

## Common Pitfalls

### ❌ Don't: Synchronous Blocking
```rust
// BAD: Blocks entire runtime
let result = tokio::task::block_in_place(|| {
    auth_client.user_exists(user_id).await
});
```

### ❌ Don't: Excessive Retries
```rust
// BAD: Can create cascading failures
for _ in 0..100 {  // Too many retries
    match auth_client.user_exists(user_id).await {
        Ok(result) => return Ok(result),
        Err(_) => continue,
    }
}
```

### ❌ Don't: Ignore Timeouts
```rust
// BAD: No timeout, can hang forever
let result = auth_client.user_exists(user_id).await?;
```

### ✅ Do: Exponential Backoff with Limits
```rust
// GOOD: Bounded retries with backoff
let mut backoff = Duration::from_millis(100);
for attempt in 0..3 {
    match auth_client.user_exists(user_id).await {
        Ok(result) => return Ok(result),
        Err(e) if attempt < 2 => {
            tokio::time::sleep(backoff).await;
            backoff *= 2;  // Exponential backoff
        }
        Err(e) => return Err(e),
    }
}
```

## Performance Optimization

### Connection Pooling Benefits
- **Reduced Latency**: Reuse existing connections (~50ms savings per request)
- **Better Throughput**: Multiplex requests over channels
- **Resource Efficiency**: Limit concurrent connections

### Batch Processing Benefits
- **Network Efficiency**: 100x fewer round trips for 100 users
- **Lower Latency**: ~50ms for 100 users vs 5000ms for 100 sequential calls
- **Reduced Load**: Less pressure on auth-service

### Recommended Batch Sizes
- **Small**: 50 users (low latency priority)
- **Medium**: 100 users (balanced, recommended)
- **Large**: 500 users (throughput priority, use for bulk operations only)

---

*Reference Implementation*: `backend/libs/grpc-clients/`
*Last Updated*: 2025-01-07
