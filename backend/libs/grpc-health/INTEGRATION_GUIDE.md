# Integration Guide: Adding Health Checks to gRPC Services

This guide shows how to integrate grpc-health into your gRPC microservice.

## Step 1: Add Dependency

Add to your service's `Cargo.toml`:

```toml
[dependencies]
grpc-health = { path = "../libs/grpc-health" }
```

## Step 2: Update Service Main Function

### Before (without health checks)

```rust
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize dependencies
    let pg_pool = sqlx::PgPool::connect(&database_url).await?;

    // Create gRPC service
    let user_service = UserServiceServer::new(UserServiceImpl::new(pg_pool));

    // Start server
    Server::builder()
        .add_service(user_service)
        .serve(addr)
        .await?;

    Ok(())
}
```

### After (with health checks)

```rust
use grpc_health::HealthManagerBuilder;
use grpc_health::HealthManager;
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

    // NEW: Create health manager with all dependency checks
    let (health_manager, health_service) = HealthManagerBuilder::new()
        .with_postgres(pg_pool.clone())
        .with_redis(redis_client.clone())
        .with_kafka(&kafka_brokers)
        .build()
        .await;

    // NEW: Start background health checks (every 10 seconds)
    let health_manager = Arc::new(tokio::sync::Mutex::new(health_manager));
    HealthManager::start_background_check(
        health_manager.clone(),
        Duration::from_secs(10),
    );

    // Create gRPC service
    let user_service = UserServiceServer::new(UserServiceImpl::new(pg_pool));

    // Start server
    Server::builder()
        .add_service(health_service)  // NEW: Add health service FIRST
        .add_service(user_service)
        .serve(addr)
        .await?;

    Ok(())
}
```

## Step 3: Update Kubernetes Deployment

Add gRPC health probes to your deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: nova
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
      - name: user-service
        image: nova/user-service:latest
        ports:
        - containerPort: 50051
          name: grpc
          protocol: TCP

        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: database-secrets
              key: postgres-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: cache-secrets
              key: redis-url
        - name: KAFKA_BROKERS
          value: "kafka-0.kafka-headless:9092,kafka-1.kafka-headless:9092"

        # Startup Probe: Initial startup check
        # Gives the service time to initialize (up to 150 seconds)
        startupProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30  # 30 × 5s = 150s max startup time

        # Liveness Probe: Restart if unhealthy
        # Checks if the service is still running
        livenessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3  # Restart after 3 consecutive failures

        # Readiness Probe: Remove from Service if not ready
        # Checks if the service can handle traffic
        readinessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2  # Remove after 2 consecutive failures

        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

## Step 4: Test Locally

### Test with grpcurl

```bash
# 1. Start your service locally
cargo run --bin user-service

# 2. In another terminal, test health endpoint
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# Expected output:
# {
#   "status": "SERVING"
# }

# 3. Test with specific service name (if configured)
grpcurl -plaintext -d '{"service":"user_service.UserService"}' \
  localhost:50051 grpc.health.v1.Health/Check

# 4. Watch health status changes (streaming)
grpcurl -plaintext -d '{"service":""}' \
  localhost:50051 grpc.health.v1.Health/Watch
```

### Test with grpc_cli

```bash
# List services
grpc_cli ls localhost:50051

# Expected output:
# grpc.health.v1.Health
# user_service.UserService

# Call health check
grpc_cli call localhost:50051 grpc.health.v1.Health.Check ""

# Expected output:
# status: SERVING
```

## Step 5: Deploy and Verify

```bash
# 1. Build and push image
docker build -t nova/user-service:latest .
docker push nova/user-service:latest

# 2. Apply Kubernetes deployment
kubectl apply -f k8s/user-service-deployment.yaml

# 3. Check pod status
kubectl get pods -l app=user-service -w

# Expected: Pods should reach Running state with all containers ready
# NAME                            READY   STATUS    RESTARTS   AGE
# user-service-5d8f7b9c4d-abc12   1/1     Running   0          30s
# user-service-5d8f7b9c4d-def34   1/1     Running   0          30s
# user-service-5d8f7b9c4d-ghi56   1/1     Running   0          30s

# 4. Check probe status
kubectl describe pod user-service-5d8f7b9c4d-abc12 | grep -A 5 "Liveness\|Readiness"

# Expected: No probe failures
```

## Step 6: Test Failure Scenarios

### Simulate Database Failure

```bash
# 1. Block database traffic (example)
kubectl exec -it user-service-5d8f7b9c4d-abc12 -- \
  iptables -A OUTPUT -p tcp --dport 5432 -j DROP

# 2. Watch pod status
kubectl get pods -l app=user-service -w

# Expected: Pod should be marked as NotReady and eventually restarted
# NAME                            READY   STATUS    RESTARTS   AGE
# user-service-5d8f7b9c4d-abc12   0/1     Running   0          5m

# 3. Restore traffic
kubectl exec -it user-service-5d8f7b9c4d-abc12 -- \
  iptables -D OUTPUT -p tcp --dport 5432 -j DROP

# 4. Verify recovery
# Expected: Pod should become Ready again
```

## Advanced Configuration

### Custom Health Check Interval

```rust
// Check every 5 seconds instead of 10
HealthManager::start_background_check(
    health_manager.clone(),
    Duration::from_secs(5),
);
```

### Service-Specific Health Status

```rust
// You can set health for specific gRPC services
// This is useful if you have multiple services in one binary

use tonic::NamedService;

// Example: Set user service as not serving during maintenance
health_manager.lock().await.reporter.set_service_status(
    UserServiceServer::<UserServiceImpl>::NAME,
    tonic_health::ServingStatus::NotServing,
).await;
```

### Manual Health Check Control

```rust
// Disable background checks and control manually
let (mut health_manager, health_service) = HealthManager::new();

// Register checks
health_manager.register_check(Box::new(PostgresHealthCheck::new(pool))).await;

// Manual check and update
tokio::spawn(async move {
    loop {
        health_manager.check_and_update().await;
        tokio::time::sleep(Duration::from_secs(10)).await;
    }
});
```

### Add Custom Dependency Check

```rust
use grpc_health::{HealthCheck, HealthCheckError, Result};
use async_trait::async_trait;

struct ExternalApiCheck {
    client: reqwest::Client,
    api_url: String,
}

#[async_trait]
impl HealthCheck for ExternalApiCheck {
    async fn check(&self) -> Result<()> {
        let response = self.client
            .get(&format!("{}/health", self.api_url))
            .timeout(Duration::from_secs(3))
            .send()
            .await
            .map_err(|e| HealthCheckError::generic(format!("API health check failed: {}", e)))?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err(HealthCheckError::generic(format!(
                "API returned status: {}",
                response.status()
            )))
        }
    }
}

// Register it
let api_check = ExternalApiCheck {
    client: reqwest::Client::new(),
    api_url: "https://external-api.example.com".to_string(),
};

health_manager.register_check(Box::new(api_check)).await;
```

## Monitoring and Alerts

### Prometheus Metrics (Optional)

If you want to expose health status as metrics:

```rust
use prometheus::{IntGauge, register_int_gauge};

lazy_static! {
    static ref HEALTH_STATUS: IntGauge = register_int_gauge!(
        "service_health_status",
        "Service health status (1=serving, 0=not_serving)"
    ).unwrap();
}

// In your background check loop
let health_manager = Arc::new(tokio::sync::Mutex::new(health_manager));
let health_manager_clone = health_manager.clone();

tokio::spawn(async move {
    let mut interval = tokio::time::interval(Duration::from_secs(10));

    loop {
        interval.tick().await;

        let mut mgr = health_manager_clone.lock().await;
        let result = mgr.execute_checks().await;

        if result.is_ok() {
            HEALTH_STATUS.set(1);
            mgr.reporter.set_service_status("", tonic_health::ServingStatus::Serving).await;
        } else {
            HEALTH_STATUS.set(0);
            mgr.reporter.set_service_status("", tonic_health::ServingStatus::NotServing).await;
        }
    }
});
```

### Grafana Dashboard Query

```promql
# Health status over time
service_health_status{service="user-service"}

# Alert when service is unhealthy for 1 minute
ALERTS{alertname="ServiceUnhealthy"} > 0
  where service_health_status == 0 for 1m
```

## Troubleshooting

### Common Issues

#### 1. Health checks always fail

**Symptoms**: Pods keep restarting, health endpoint returns NOT_SERVING

**Solutions**:
- Check connection strings are correct
- Verify network connectivity to dependencies
- Increase health check timeouts
- Check service logs: `kubectl logs <pod>`

#### 2. Slow startup causing probe failures

**Symptoms**: Pods fail startup probe before fully initialized

**Solutions**:
- Increase `startupProbe.failureThreshold`
- Add `initialDelaySeconds` to startup probe
- Optimize service initialization
- Use lazy initialization for non-critical components

#### 3. False positives during high load

**Symptoms**: Health checks fail during traffic spikes

**Solutions**:
- Increase probe timeout values
- Increase `failureThreshold`
- Add resource limits to prevent resource exhaustion
- Consider separate health check connection pool

## Migration Checklist

- [ ] Add grpc-health dependency to Cargo.toml
- [ ] Update main.rs with health manager initialization
- [ ] Add background health check task
- [ ] Update Kubernetes deployment with gRPC probes
- [ ] Test locally with grpcurl
- [ ] Deploy to staging environment
- [ ] Verify probes work correctly
- [ ] Test failure scenarios
- [ ] Add monitoring/alerting
- [ ] Deploy to production
- [ ] Monitor for first 24 hours

## Next Steps

- Add health checks to all microservices
- Set up centralized health monitoring dashboard
- Configure alerts for health failures
- Document runbook for common health check failures
- Consider implementing graceful degradation
