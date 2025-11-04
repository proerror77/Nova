# P0 Fix #4: Service Discovery & Circuit Breaker

## Problem

**Issue 1: Hardcoded Service Addresses**
```rust
// Current code - brittle:
let auth_service_addr = std::env::var("AUTH_SERVICE_URL")
    .unwrap_or("http://auth-service:8083");  // ❌ Hardcoded

let user_service_addr = "http://user-service:8080";  // ❌ Hardcoded
```

**Issue 2: No Circuit Breaker in Most Services**
```rust
// Current code - cascading failures:
let result = grpc_client.validate_token(token).await?;  // No timeout, no retry
// If auth-service slow/down: request hangs forever
```

**Impact**:
- No load balancing across service replicas
- Service address changes require code redeploy
- One slow service takes down entire API (cascading failures)

---

## Solution: Kubernetes DNS + Circuit Breaker

### Approach 1: Native Kubernetes (Recommended for EKS)

**No code changes needed!** Kubernetes handles service discovery.

```rust
// Instead of hardcoding, use Kubernetes DNS:
let addr = "http://auth-service.nova.svc.cluster.local:8083";
// K8s automatically load-balances across replicas
```

**How it works**:
```
Client → auth-service.nova.svc.cluster.local:8083
              ↓
         Kubernetes CoreDNS
              ↓
         Load balance across:
         - auth-service-pod-1:8083
         - auth-service-pod-2:8083
         - auth-service-pod-3:8083
```

### Approach 2: Consul (If Polyrepo Conversion Planned)

Uses distributed service registry:
```rust
// Register service
consul.register("auth-service", "localhost:8083")?;

// Query service
let endpoints = consul.discover("auth-service")?;
// Returns: [8.8.8.1:8083, 8.8.8.2:8083, ...]

// Client auto-rotates through endpoints
```

---

## Circuit Breaker Implementation

**File**: `/libs/actix-middleware/src/circuit_breaker.rs` (Already exists!)

### Usage in gRPC Clients

```rust
// Example: user-service calling auth-service

use actix_middleware::CircuitBreaker;

pub struct AuthServiceClient {
    circuit_breaker: CircuitBreaker,
    client: tonic::transport::Channel,
}

impl AuthServiceClient {
    pub async fn validate_token(&self, token: &str) -> Result<Claims> {
        // All calls go through circuit breaker
        self.circuit_breaker.call(|| async {
            // Call with timeout
            let response = tokio::time::timeout(
                Duration::from_secs(2),
                self.client.validate_token(token)
            ).await??;
            Ok(response)
        }).await?
    }
}
```

### Fallback Strategies

```rust
// When circuit is OPEN, implement graceful degradation:

pub async fn get_user_posts(user_id: UserId) -> Result<Vec<Post>> {
    match user_service_cb.call(|| async {
        user_service.get_posts(user_id).await
    }).await {
        Ok(posts) => Ok(posts),
        Err(CircuitBreakerError::Open) => {
            // Service is down - return cached data
            let cached = cache.get_user_posts(user_id).await;
            Ok(cached.unwrap_or_default())  // Return stale data rather than error
        }
        Err(e) => Err(e),
    }
}
```

---

## Implementation Plan

### Phase 1: Enable Circuit Breaker (Week 1)

Update all services that call other services:

**1. user-service** (calls auth-service)
```rust
// File: user-service/src/grpc/clients.rs
pub struct AuthServiceClient {
    client: AuthServiceGrpcClient,
    circuit_breaker: CircuitBreaker,
}

impl AuthServiceClient {
    pub fn new(addr: &str) -> Self {
        Self {
            client: AuthServiceGrpcClient::connect(addr).await?,
            circuit_breaker: CircuitBreaker::new(
                CircuitBreakerConfig {
                    failure_threshold: 5,
                    success_threshold: 3,
                    timeout: Duration::from_secs(30),
                }
            ),
        }
    }

    pub async fn validate_token(&self, token: &str) -> Result<Claims> {
        self.circuit_breaker.call(|| {
            let mut client = self.client.clone();
            async move {
                client.validate_token(ValidateTokenRequest {
                    token: token.to_string(),
                })
                .await
            }
        }).await?
    }
}
```

**2. content-service** (calls media-service)
```rust
pub struct MediaServiceClient {
    circuit_breaker: CircuitBreaker,
    ...
}

impl MediaServiceClient {
    pub async fn upload_media(...) -> Result<MediaResponse> {
        self.circuit_breaker.call(|| async {
            // Media upload with timeout
            tokio::time::timeout(
                Duration::from_secs(30),
                self.upload_internal(...)
            ).await??
        }).await?
    }
}
```

### Phase 2: Kubernetes Service Discovery (Week 2)

Update service configuration:

```yaml
# kubernetes/base/user-service-deployment.yaml
env:
  - name: AUTH_SERVICE_URL
    value: "http://auth-service.nova.svc.cluster.local:8083"
  - name: CONTENT_SERVICE_URL
    value: "http://content-service.nova.svc.cluster.local:8081"
  - name: MEDIA_SERVICE_URL
    value: "http://media-service.nova.svc.cluster.local:8082"
  # No more hardcoded localhost!
```

### Phase 3: Monitoring & Alerting (Week 3)

```rust
// In CircuitBreaker::call():
let state = self.circuit_breaker.state().await;
match state {
    CircuitBreakerState::Open => {
        alert!("Service {} circuit breaker OPEN", service_name);
        CIRCUIT_BREAKER_OPEN.inc();
    }
    CircuitBreakerState::HalfOpen => {
        tracing::warn!("Circuit breaker HALF-OPEN for {}", service_name);
    }
    _ => {}
}
```

Alert Rules:
```yaml
- alert: CircuitBreakerOpen
  expr: circuit_breaker_state{state="open"} == 1
  for: 2m
  annotations:
    summary: "{{ $labels.service }} circuit breaker is OPEN"

- alert: HighServiceErrorRate
  expr: rate(service_errors_total[5m]) > 0.1
  annotations:
    summary: "{{ $labels.service }} has >10% error rate"
```

---

## Configuration

### Circuit Breaker Tuning

| Environment | failure_threshold | success_threshold | timeout |
|-------------|-------------------|-------------------|---------|
| Development | 1 | 1 | 5s |
| Staging | 3 | 2 | 10s |
| Production | 5 | 3 | 30s |

```rust
// Adjust per service based on characteristics:
pub fn config_for_service(service: &str) -> CircuitBreakerConfig {
    match service {
        "auth-service" => CircuitBreakerConfig {
            failure_threshold: 3,   // Fast fail
            success_threshold: 3,
            timeout: Duration::from_secs(30),
        },
        "media-service" => CircuitBreakerConfig {
            failure_threshold: 5,   // More tolerant of brief failures
            success_threshold: 5,
            timeout: Duration::from_secs(60),  // Uploads are slow
        },
        _ => CircuitBreakerConfig::default(),
    }
}
```

---

## Testing

```rust
#[tokio::test]
async fn test_circuit_breaker_opens_on_failures() {
    let cb = CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 2,
        timeout: Duration::from_secs(1),
        ..Default::default()
    });

    // Trigger 2 failures
    let _ = cb.call(|| async {
        Err::<(), _>("Service error")
    }).await;

    let _ = cb.call(|| async {
        Err::<(), _>("Service error")
    }).await;

    // 3rd call should be rejected immediately (circuit open)
    let start = Instant::now();
    let result = cb.call(|| async {
        Ok::<(), _>(())
    }).await;

    assert!(result.is_err());
    assert!(start.elapsed() < Duration::from_millis(100));  // No hang
}

#[tokio::test]
async fn test_circuit_breaker_recovers() {
    let cb = CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 1,
        success_threshold: 2,
        timeout: Duration::from_millis(100),
    });

    // Open the circuit
    let _ = cb.call(|| async {
        Err::<(), _>("error")
    }).await;

    assert_eq!(cb.state().await, CircuitBreakerState::Open);

    // Wait for timeout
    tokio::time::sleep(Duration::from_millis(150)).await;

    // Half-open: successful call should close circuit
    let _ = cb.call(|| async { Ok::<(), _>(()) }).await;
    let _ = cb.call(|| async { Ok::<(), _>(()) }).await;

    assert_eq!(cb.state().await, CircuitBreakerState::Closed);
}

#[tokio::test]
async fn test_fallback_on_circuit_open() {
    // When auth-service is down, should return cached user data
    let cb = create_open_circuit_breaker().await;

    let result = match user_service_call(&cb).await {
        Err(CircuitBreakerError::Open) => {
            cache.get_cached_user().await  // Fallback
        }
        other => other,
    };

    assert!(result.is_ok());
}
```

---

## Monitoring Dashboard

```
Circuit Breaker State:
├── auth-service: CLOSED ✓ (0 failures, p99: 8ms)
├── content-service: CLOSED ✓ (0 failures, p99: 12ms)
├── user-service: CLOSED ✓ (0 failures, p99: 10ms)
├── media-service: HALF-OPEN ⚠️ (recovering from failure)
└── search-service: OPEN ❌ (5 consecutive failures)

Service Error Rates:
├── auth-service: 0.1%
├── content-service: 0.2%
├── media-service: 2.1% ← HIGH
└── search-service: 5.8% ← CRITICAL
```

---

## Troubleshooting

### Problem: Circuit breaker stays OPEN

**Check**:
```bash
kubectl logs -l app=media-service | grep -i error
kubectl get svc media-service
```

**Causes**:
1. Service not running
2. Service not healthy (health check failing)
3. Network issue

**Fix**:
```bash
# Restart service
kubectl rollout restart deploy/media-service

# Check service DNS
kubectl run -it debug --image=busybox -- nslookup media-service.nova.svc.cluster.local

# Check service endpoints
kubectl get endpoints media-service
```

### Problem: Cascading failures still happening

**Check**: Are all services using circuit breaker?
```bash
grep -r "CircuitBreaker" backend/*/src/grpc/
# If not present in a service, it's not protected
```

**Fix**: Add circuit breaker to all gRPC clients

---

## Status

- **Created**: 2025-11-04
- **Priority**: P0
- **Estimated Effort**: 3 weeks
- **Fixes**: Cascading failures, enables safe scaling
- **Required**: Phase 1 + 2 for production readiness
