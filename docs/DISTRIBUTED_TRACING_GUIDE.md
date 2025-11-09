# Distributed Tracing Implementation Guide

**Status**: ✅ Ready for Implementation
**Technology**: OpenTelemetry + Jaeger
**Date**: 2025-11-09

---

## Overview

This document describes the implementation of distributed tracing across the Nova backend microservices using OpenTelemetry and Jaeger.

### Benefits

- **Request Tracing**: Track requests across multiple services
- **Performance Analysis**: Identify bottlenecks and slow operations
- **Dependency Visualization**: Understand service dependencies
- **Error Detection**: Quickly identify failing services
- **Latency Breakdown**: See time spent in each service/operation

---

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP/gRPC + trace headers
       ▼
┌─────────────────────────────────────┐
│  Nova Backend Services              │
│  - auth-service                     │
│  - user-service                     │
│  - content-service                  │
│  - messaging-service                │
│  - ...                              │
│                                     │
│  Each service:                      │
│  1. Extracts trace context          │
│  2. Creates child spans             │
│  3. Propagates context downstream   │
│  4. Exports spans to collector      │
└──────────────┬──────────────────────┘
               │ OTLP (gRPC)
               ▼
       ┌───────────────┐
       │    Jaeger     │
       │   Collector   │
       └───────┬───────┘
               │
               ▼
       ┌───────────────┐
       │ Elasticsearch │
       │  (Production) │
       │      or       │
       │    Memory     │
       │  (Dev/Staging)│
       └───────┬───────┘
               │
               ▼
       ┌───────────────┐
       │ Jaeger Query  │
       │   UI + API    │
       └───────────────┘
```

---

## Implementation

### 1. Library Integration

Add the `opentelemetry-config` library to each service's `Cargo.toml`:

```toml
[dependencies]
opentelemetry-config = { path = "../libs/opentelemetry-config" }
```

### 2. Service Initialization

Update each service's `main.rs`:

```rust
use opentelemetry_config::{init_tracing, shutdown_tracing, TracingConfig};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    let tracing_config = TracingConfig::from_env();
    let _tracer = init_tracing("auth-service", tracing_config)?;

    // ... existing service initialization ...

    // Shutdown tracing on exit
    shutdown_tracing();
    Ok(())
}
```

### 3. gRPC Interceptor Integration

For gRPC services, add the tracing interceptor:

```rust
use opentelemetry_config::grpc_tracing_interceptor;
use tonic::transport::Server;

Server::builder()
    .add_service(
        AuthServiceServer::with_interceptor(
            auth_service,
            grpc_tracing_interceptor
        )
    )
    .serve(addr)
    .await?;
```

### 4. HTTP Middleware Integration

For HTTP services (Actix-Web):

```rust
use opentelemetry_config::http_tracing_layer;
use actix_web::{App, HttpServer};

HttpServer::new(move || {
    App::new()
        .wrap(http_tracing_layer())
        // ... other middleware ...
})
.bind(addr)?
.run()
.await
```

---

## Configuration

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `TRACING_ENABLED` | Enable tracing | `false` | `true` |
| `TRACING_EXPORTER` | Exporter type | `otlp` | `otlp` or `jaeger` |
| `OTLP_ENDPOINT` | OTLP collector endpoint | `http://jaeger:4317` | `http://jaeger-collector:4317` |
| `JAEGER_ENDPOINT` | Jaeger agent endpoint | `http://jaeger:14268/api/traces` | (legacy) |
| `TRACING_SAMPLE_RATE` | Sample rate (0.0-1.0) | `0.1` | `0.1` (10%), `1.0` (100%) |
| `SERVICE_VERSION` | Service version | `dev` | `1.2.3` |
| `APP_ENV` | Environment | `development` | `production`, `staging` |

### Environment-Specific Configuration

#### Development
```bash
TRACING_ENABLED=true
TRACING_EXPORTER=otlp
OTLP_ENDPOINT=http://localhost:4317
TRACING_SAMPLE_RATE=1.0
APP_ENV=development
```

#### Staging
```bash
TRACING_ENABLED=true
TRACING_EXPORTER=otlp
OTLP_ENDPOINT=http://jaeger-collector.observability:4317
TRACING_SAMPLE_RATE=0.5
APP_ENV=staging
```

#### Production
```bash
TRACING_ENABLED=true
TRACING_EXPORTER=otlp
OTLP_ENDPOINT=http://jaeger-collector.observability:4317
TRACING_SAMPLE_RATE=0.1
APP_ENV=production
```

---

## Deployment

### 1. Deploy Jaeger to Kubernetes

#### Development/Staging (In-Memory Storage)
```bash
kubectl apply -f k8s/base/jaeger/deployment.yaml
```

#### Production (Elasticsearch Backend)
```bash
# Deploy Elasticsearch first (if not already deployed)
kubectl apply -f k8s/base/elasticsearch/

# Deploy Jaeger with Elasticsearch backend
kubectl apply -f k8s/overlays/production/jaeger-production.yaml
```

### 2. Verify Jaeger Deployment
```bash
# Check pods
kubectl get pods -n observability

# Check services
kubectl get svc -n observability

# Access Jaeger UI
kubectl port-forward -n observability svc/jaeger-query 16686:16686
# Open http://localhost:16686
```

### 3. Update Service ConfigMaps

Add tracing configuration to each service's ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-service-config
  namespace: default
data:
  TRACING_ENABLED: "true"
  TRACING_EXPORTER: "otlp"
  OTLP_ENDPOINT: "http://jaeger-collector.observability:4317"
  TRACING_SAMPLE_RATE: "0.1"
  SERVICE_VERSION: "1.0.0"
  APP_ENV: "production"
```

### 4. Deploy Updated Services
```bash
# Deploy services with tracing enabled
kubectl apply -k k8s/overlays/production/

# Monitor rollout
kubectl rollout status deployment/auth-service
kubectl rollout status deployment/user-service
# ... etc
```

---

## Usage

### 1. Accessing Jaeger UI

**Development**:
```bash
kubectl port-forward -n observability svc/jaeger-query 16686:16686
open http://localhost:16686
```

**Production**:
```
https://jaeger.nova.com
```

### 2. Searching Traces

1. **By Service**: Select service from dropdown (e.g., "auth-service")
2. **By Operation**: Filter by specific operation (e.g., "/api/v1/auth/login")
3. **By Tags**: Search by tags (e.g., `http.status_code=500`)
4. **By Duration**: Find slow requests (e.g., > 1000ms)

### 3. Analyzing a Trace

Click on a trace to see:
- **Timeline**: Visual representation of span durations
- **Span Details**:
  - Service name
  - Operation name
  - Duration
  - Tags (HTTP method, status, errors)
  - Logs (if any)
- **Service Dependencies**: Call graph visualization

### 4. Example Trace Analysis

**Scenario**: Login request is slow

1. Search for service: `auth-service`, operation: `/api/v1/auth/login`
2. Filter by duration > 1000ms
3. Click on slow trace
4. Examine spans:
   ```
   auth-service: POST /api/v1/auth/login (1200ms)
   ├─ user-service.GetUser (800ms) ⚠️ SLOW!
   │  └─ PostgreSQL query (750ms) ⚠️ BOTTLENECK
   └─ Redis SET (50ms)
   ```
5. **Root Cause**: Database query in user-service is slow
6. **Action**: Add database index or optimize query

---

## Best Practices

### 1. Span Naming

✅ **Good**:
```rust
let span = tracing::info_span!(
    "database_query",
    db.table = "users",
    db.operation = "SELECT"
);
```

❌ **Bad**:
```rust
let span = tracing::info_span!("query"); // Too generic
```

### 2. Adding Context

```rust
use tracing::field;

let span = tracing::info_span!(
    "create_user",
    user.id = field::Empty,
    user.email = %email,
);

// Later, add the user ID
span.record("user.id", user_id);
```

### 3. Error Tracking

```rust
if let Err(e) = result {
    tracing::error!(
        error = %e,
        error.kind = "DatabaseError",
        "Failed to create user"
    );
}
```

### 4. Custom Spans for Operations

```rust
use tracing::instrument;

#[instrument(
    name = "send_email",
    skip(client),
    fields(
        email.to = %to_address,
        email.subject = %subject
    )
)]
async fn send_email(
    client: &EmailClient,
    to_address: &str,
    subject: &str,
    body: &str,
) -> Result<(), Error> {
    // Implementation
}
```

---

## Performance Considerations

### Sample Rate Guidelines

| Environment | Sample Rate | Reasoning |
|-------------|-------------|-----------|
| Development | 100% (1.0) | Trace all requests for debugging |
| Staging | 50% (0.5) | Balance between visibility and overhead |
| Production | 10% (0.1) | Minimize overhead, still statistically significant |
| High Traffic | 1% (0.01) | Very high traffic services |

### Resource Impact

**Per-Service Overhead**:
- CPU: +2-5%
- Memory: +50-100MB
- Network: +1-2KB per traced request

**Jaeger Collector Resources**:
- Development: 100m CPU, 256Mi memory
- Staging: 500m CPU, 1Gi memory
- Production: 500m-2000m CPU, 1Gi-4Gi memory (with HPA)

### Batching Configuration

Default batch configuration (already optimized in library):
- Queue size: 2048 spans
- Batch size: 512 spans
- Export interval: 5 seconds

---

## Troubleshooting

### Issue: No Traces Appearing

**Check 1**: Verify tracing is enabled
```bash
kubectl exec -it deployment/auth-service -- env | grep TRACING
```

**Check 2**: Verify Jaeger connectivity
```bash
kubectl exec -it deployment/auth-service -- \
  curl -v http://jaeger-collector.observability:4317
```

**Check 3**: Check service logs
```bash
kubectl logs deployment/auth-service | grep -i tracing
```

### Issue: Spans Not Linked

**Cause**: Trace context not propagated correctly

**Solution**: Ensure gRPC interceptor or HTTP middleware is applied to ALL services

```rust
// gRPC - MUST use interceptor
Server::builder()
    .add_service(
        ServiceServer::with_interceptor(svc, grpc_tracing_interceptor)
    )

// HTTP - MUST use layer
App::new().wrap(http_tracing_layer())
```

### Issue: High Latency After Enabling Tracing

**Cause**: Sample rate too high or exporter blocking

**Solution 1**: Reduce sample rate
```bash
TRACING_SAMPLE_RATE=0.01  # 1% instead of 10%
```

**Solution 2**: Verify batching is enabled (default in library)

**Solution 3**: Check Jaeger collector resource limits

---

## Security Considerations

### 1. PII in Spans

❌ **Never** log sensitive data:
```rust
// BAD - Leaks password
tracing::info!(user.password = %password);
```

✅ **Only log safe attributes**:
```rust
// GOOD - Only user ID
tracing::info!(user.id = %user_id);
```

### 2. Jaeger UI Access

- **Development**: No authentication (localhost only)
- **Staging**: Basic auth via Ingress annotations
- **Production**: OAuth2 proxy with SSO

Example Ingress with OAuth:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jaeger-ui
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://oauth2-proxy.nova.com/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://oauth2-proxy.nova.com/oauth2/start"
```

### 3. Trace Data Retention

| Environment | Retention | Storage |
|-------------|-----------|---------|
| Development | 7 days | Memory |
| Staging | 30 days | Elasticsearch |
| Production | 90 days | Elasticsearch with index lifecycle |

---

## Monitoring & Alerts

### Key Metrics

Monitor Jaeger health using Prometheus:

1. **Collector Metrics**:
   - `jaeger_collector_queue_length`
   - `jaeger_collector_spans_received_total`
   - `jaeger_collector_spans_dropped_total`

2. **Storage Metrics**:
   - `jaeger_storage_latency`
   - `jaeger_storage_errors_total`

### Recommended Alerts

```yaml
# Alert if spans are being dropped
- alert: JaegerSpansDropped
  expr: rate(jaeger_collector_spans_dropped_total[5m]) > 100
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Jaeger is dropping spans"

# Alert if collector queue is full
- alert: JaegerQueueFull
  expr: jaeger_collector_queue_length > 4000
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Jaeger collector queue nearly full"
```

---

## Next Steps

After implementing distributed tracing:

1. **✅ Implement Chaos Engineering** (Chaos Mesh) - Use traces to validate system resilience
2. **GraphQL Federation** - Trace federated GraphQL queries
3. **Event Sourcing** - Correlate traces with event replay
4. **Read Replicas** - Measure read/write latency differences

---

## References

- OpenTelemetry Documentation: https://opentelemetry.io/docs/
- Jaeger Documentation: https://www.jaegertracing.io/docs/
- OpenTelemetry Rust: https://github.com/open-telemetry/opentelemetry-rust

---

**Document Version**: 1.0
**Last Updated**: 2025-11-09
**Status**: Ready for Implementation
