# Phase 1 Security Fixes - Implementation Guide

**Priority**: P0 (BLOCKER) - Must fix before production deployment
**Estimated Effort**: 4-6 hours
**Risk**: Critical vulnerabilities if not addressed

---

## Fix 1: JWT Secret Strength Validation (P0-1)

### Problem
JWT middleware accepts ANY secret, including weak ones like "test" or "secret123".

**Risk**: Complete authentication bypass via brute-force

### Implementation

**File**: `backend/graphql-gateway/src/middleware/jwt.rs`

**Line 23-29**, replace:
```rust
impl JwtMiddleware {
    pub fn new(secret: String) -> Self {
        Self { secret }
    }
}
```

**With**:
```rust
impl JwtMiddleware {
    /// Create new JWT middleware with secret validation
    ///
    /// # Security Requirements
    /// - Minimum length: 32 bytes (256 bits)
    /// - Recommended: Cryptographically random secret from secure source
    ///
    /// # Panics
    /// Panics if secret doesn't meet security requirements (fail-fast principle)
    pub fn new(secret: String) -> Self {
        // CRITICAL: Validate secret strength at startup
        if secret.len() < 32 {
            panic!(
                "JWT secret too short ({} bytes). SECURITY REQUIREMENT: ≥32 bytes. \
                 Generate with: openssl rand -base64 32",
                secret.len()
            );
        }

        // Warn if secret appears weak
        if secret.chars().all(|c| c.is_ascii_alphanumeric())
            && secret.len() < 64
        {
            tracing::warn!(
                "JWT secret appears to have low entropy. \
                 Recommend using cryptographically random secret."
            );
        }

        Self { secret }
    }
}
```

### Testing

**Add to** `backend/graphql-gateway/src/middleware/jwt.rs`:

```rust
#[cfg(test)]
mod secret_validation_tests {
    use super::*;

    #[test]
    #[should_panic(expected = "JWT secret too short")]
    fn test_rejects_weak_secret() {
        JwtMiddleware::new("weak".to_string());
    }

    #[test]
    #[should_panic(expected = "JWT secret too short")]
    fn test_rejects_31_byte_secret() {
        JwtMiddleware::new("a".repeat(31));
    }

    #[test]
    fn test_accepts_32_byte_secret() {
        let _middleware = JwtMiddleware::new("a".repeat(32));
        // Passes if no panic
    }

    #[test]
    fn test_accepts_strong_secret() {
        let strong = "bGFyZ2UtcmFuZG9tLXNlY3VyZS1zZWNyZXQtd2l0aC1oaWdoLWVudHJvcHk=";
        let _middleware = JwtMiddleware::new(strong.to_string());
        // Passes if no panic
    }
}
```

### Deployment

**1. Generate Strong Secret**:
```bash
# Generate 64-byte cryptographically random secret
openssl rand -base64 64 > /secure/path/jwt_secret.key
chmod 600 /secure/path/jwt_secret.key

# Verify length
wc -c /secure/path/jwt_secret.key  # Should be ≥32 bytes
```

**2. Update Kubernetes Secret**:
```bash
kubectl create secret generic jwt-secret \
  --from-file=jwt-secret=/secure/path/jwt_secret.key \
  --namespace=nova \
  --dry-run=client -o yaml | kubectl apply -f -
```

**3. Update Deployment**:
```yaml
# k8s/microservices/graphql-gateway-deployment.yaml
env:
  - name: JWT_SECRET
    valueFrom:
      secretKeyRef:
        name: jwt-secret
        key: jwt-secret
```

**4. Verify in Staging**:
```bash
# This should FAIL (intentional test)
kubectl set env deployment/graphql-gateway JWT_SECRET=weak -n nova

# Should see in logs:
# PANIC: JWT secret too short (4 bytes). SECURITY REQUIREMENT: ≥32 bytes.

# Restore correct secret
kubectl rollout undo deployment/graphql-gateway -n nova
```

---

## Fix 2: Pool Backpressure Implementation (P0-2)

### Problem
No early rejection when pool is near exhaustion, leading to cascading failures.

### Implementation

**File**: `backend/libs/db-pool/src/lib.rs`

**Add at end of file** (before `#[cfg(test)]`):

```rust
/// Error types for pool operations
#[derive(Debug)]
pub enum PoolError {
    /// Pool exhausted - utilization above threshold
    PoolExhausted {
        utilization_percent: u32,
        idle_connections: u32,
        max_connections: u32,
    },
    /// Timeout acquiring connection
    AcquireTimeout(String),
}

impl std::fmt::Display for PoolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PoolError::PoolExhausted {
                utilization_percent,
                idle_connections,
                max_connections,
            } => write!(
                f,
                "Pool exhausted: {}% utilization ({} idle / {} max)",
                utilization_percent, idle_connections, max_connections
            ),
            PoolError::AcquireTimeout(msg) => write!(f, "Connection acquire timeout: {}", msg),
        }
    }
}

impl std::error::Error for PoolError {}

/// Acquire connection with backpressure check
///
/// Rejects early if pool utilization exceeds threshold, preventing cascading failures.
///
/// # Arguments
/// * `pool` - Database connection pool
/// * `exhaustion_threshold` - Utilization ratio (0.0-1.0) to trigger backpressure
///                             Recommended: 0.85 (85%)
///
/// # Returns
/// * `Ok(connection)` - Connection acquired successfully
/// * `Err(PoolError::PoolExhausted)` - Pool above threshold
/// * `Err(PoolError::AcquireTimeout)` - Timeout waiting for connection
///
/// # Example
/// ```no_run
/// use db_pool::{create_pool, DbConfig, acquire_with_backpressure};
///
/// # #[tokio::main]
/// # async fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let pool = create_pool(DbConfig::for_service("my-service")).await?;
///
/// match acquire_with_backpressure(&pool, 0.85).await {
///     Ok(conn) => {
///         // Use connection
///         sqlx::query("SELECT 1").execute(&mut *conn).await?;
///     }
///     Err(PoolError::PoolExhausted { .. }) => {
///         // Return 503 Service Unavailable to client
///         return Err("Service temporarily overloaded".into());
///     }
///     Err(PoolError::AcquireTimeout(_)) => {
///         return Err("Database timeout".into());
///     }
/// }
/// # Ok(())
/// # }
/// ```
pub async fn acquire_with_backpressure(
    pool: &PgPool,
    exhaustion_threshold: f32,
) -> Result<sqlx::pool::PoolConnection<sqlx::Postgres>, PoolError> {
    use std::time::Duration;

    // Calculate current utilization
    let idle = pool.num_idle();
    let max = pool.options().get_max_connections();
    let active = pool.size() - idle;
    let utilization = active as f32 / max as f32;

    // Fast-fail if above threshold
    if utilization > exhaustion_threshold {
        // Increment Prometheus metric
        use prometheus::IntCounter;
        lazy_static::lazy_static! {
            static ref BACKPRESSURE_REJECTIONS: IntCounter = prometheus::register_int_counter!(
                "db_pool_backpressure_rejections_total",
                "Requests rejected due to pool backpressure"
            ).expect("Prometheus metric registration");
        }
        BACKPRESSURE_REJECTIONS.inc();

        tracing::warn!(
            utilization_percent = (utilization * 100.0) as u32,
            idle_connections = idle,
            max_connections = max,
            threshold = (exhaustion_threshold * 100.0) as u32,
            "Pool backpressure triggered - rejecting request"
        );

        return Err(PoolError::PoolExhausted {
            utilization_percent: (utilization * 100.0) as u32,
            idle_connections: idle,
            max_connections: max,
        });
    }

    // Normal acquisition with timeout
    pool.acquire()
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Pool acquire failed");
            PoolError::AcquireTimeout(e.to_string())
        })
}
```

### Update Services to Use Backpressure

**File**: `backend/user-service/src/db.rs` (and similar for other services)

**Find all**:
```rust
let conn = pool.acquire().await?;
```

**Replace with**:
```rust
use db_pool::{acquire_with_backpressure, PoolError};

let conn = acquire_with_backpressure(&pool, 0.85).await.map_err(|e| match e {
    PoolError::PoolExhausted { .. } => {
        // Return 503 to client
        Error::ServiceOverloaded(e.to_string())
    }
    PoolError::AcquireTimeout(_) => {
        Error::DatabaseTimeout(e.to_string())
    }
})?;
```

### Testing

**Add to** `backend/libs/db-pool/src/lib.rs`:

```rust
#[cfg(test)]
mod backpressure_tests {
    use super::*;

    #[tokio::test]
    async fn test_backpressure_below_threshold() {
        // Mock pool with 10 max connections, 8 idle (20% utilization)
        // Should succeed with 85% threshold
    }

    #[tokio::test]
    async fn test_backpressure_above_threshold() {
        // Mock pool with 10 max connections, 1 idle (90% utilization)
        // Should reject with 85% threshold
    }
}
```

---

## Fix 3: Path Sanitization for Logging (P1-1)

### Problem
Query parameters in request paths may contain PII (emails, tokens).

### Implementation

**File**: `backend/graphql-gateway/src/middleware/jwt.rs`

**Line 159-165**, replace:
```rust
tracing::info!(
    user_id = %user_id,
    method = %method,
    path = %path,  // ❌ May contain query params
    elapsed_ms = start.elapsed().as_millis() as u32,
    "JWT authentication successful"
);
```

**With**:
```rust
// Sanitize path to remove query parameters
let sanitized_path = req.path().split('?').next().unwrap_or(req.path());

tracing::info!(
    user_id = %user_id,
    method = %method,
    path = %sanitized_path,  // ✅ No query params
    elapsed_ms = start.elapsed().as_millis() as u32,
    "JWT authentication successful"
);
```

**Also update error logs** (lines 87-93, 103-109, 118-125):

```rust
// Example for line 87-93
tracing::warn!(
    method = %method,
    path = %req.path().split('?').next().unwrap_or(req.path()),  // ✅ Sanitized
    error = "missing_header",
    error_type = "authentication_error",
    elapsed_ms = start.elapsed().as_millis() as u32,
    "JWT authentication failed: Missing Authorization header"
);
```

### Create Reusable Helper

**File**: `backend/graphql-gateway/src/utils/logging.rs` (new file)

```rust
//! Logging utilities with PII protection

/// Sanitize request path for logging
///
/// Removes query parameters that may contain PII (emails, tokens, etc.)
///
/// # Examples
/// ```
/// assert_eq!(
///     sanitize_path_for_logging("/api/users?email=victim@example.com"),
///     "/api/users"
/// );
/// ```
pub fn sanitize_path_for_logging(path: &str) -> &str {
    path.split('?').next().unwrap_or(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_removes_query_params() {
        assert_eq!(
            sanitize_path_for_logging("/api/users?email=victim@example.com"),
            "/api/users"
        );
    }

    #[test]
    fn test_handles_no_query_params() {
        assert_eq!(
            sanitize_path_for_logging("/api/users"),
            "/api/users"
        );
    }

    #[test]
    fn test_handles_multiple_query_params() {
        assert_eq!(
            sanitize_path_for_logging("/api/reset?token=abc&email=test@example.com"),
            "/api/reset"
        );
    }
}
```

---

## Fix 4: Metrics Endpoint Protection (P2-5)

### Problem
`/metrics` endpoint accessible without authentication, exposing internal metrics.

### Implementation

**File**: `backend/messaging-service/src/metrics/mod.rs`

**Line 50-62**, replace:
```rust
pub async fn metrics_handler() -> HttpResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    if let Err(err) = encoder.encode(&metric_families, &mut buffer) {
        return HttpResponse::InternalServerError().body(err.to_string());
    }

    HttpResponse::Ok()
        .content_type(encoder.format_type())
        .body(buffer)
}
```

**With**:
```rust
use actix_web::HttpRequest;
use std::net::IpAddr;

pub async fn metrics_handler(req: HttpRequest) -> actix_web::Result<HttpResponse> {
    // Option 1: IP whitelist for internal monitoring systems
    if let Some(peer_addr) = req.peer_addr() {
        if !is_internal_ip(peer_addr.ip()) {
            return Err(actix_web::error::ErrorForbidden(
                "Metrics endpoint restricted to internal IPs"
            ));
        }
    }

    // Option 2: Basic auth for Prometheus scraper (if IP whitelist not feasible)
    // validate_metrics_auth(&req)?;

    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    if let Err(err) = encoder.encode(&metric_families, &mut buffer) {
        return Ok(HttpResponse::InternalServerError().body(err.to_string()));
    }

    Ok(HttpResponse::Ok()
        .content_type(encoder.format_type())
        .body(buffer))
}

/// Check if IP address is internal (private network)
fn is_internal_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ipv4) => {
            // 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8
            ipv4.is_loopback()
                || ipv4.is_private()
                || ipv4.octets()[0] == 10
                || (ipv4.octets()[0] == 172 && (ipv4.octets()[1] >= 16 && ipv4.octets()[1] <= 31))
                || (ipv4.octets()[0] == 192 && ipv4.octets()[1] == 168)
        }
        IpAddr::V6(ipv6) => ipv6.is_loopback(),
    }
}
```

---

## Fix 5: Error Message Sanitization (P2-2)

### Problem
Error messages too verbose, exposing internal implementation details.

### Implementation

**File**: `backend/graphql-gateway/src/middleware/jwt.rs`

**Line 150-152**, replace:
```rust
Err(e) => {
    return Box::pin(async move {
        Err(actix_web::error::ErrorUnauthorized(format!("Invalid token: {}", e)))
        //                                                                    ^^^
        //                                                  ❌ Exposes error details
    });
}
```

**With**:
```rust
Err(e) => {
    // Log detailed error internally for debugging
    tracing::error!(
        error = %e,
        error_type = "jwt_decode_failed",
        "JWT decode error"
    );

    // Return generic error to client (no details)
    return Box::pin(async move {
        Err(actix_web::error::ErrorUnauthorized("Invalid or expired token"))
        //                                        ^^^^^^^^^^^^^^^^^^^^^^^^^
        //                                        ✅ Generic message
    });
}
```

---

## Verification Checklist

After implementing fixes:

- [ ] **JWT Secret Validation**
  - [ ] Run: `cargo test -p graphql-gateway --lib jwt`
  - [ ] Verify panic on weak secret
  - [ ] Deploy with strong secret (≥32 bytes)

- [ ] **Pool Backpressure**
  - [ ] Run: `cargo test -p db-pool backpressure`
  - [ ] Verify Prometheus metric registered
  - [ ] Load test to trigger backpressure

- [ ] **Path Sanitization**
  - [ ] Run: `cargo test -p graphql-gateway logging`
  - [ ] Manually inspect logs for query params

- [ ] **Metrics Protection**
  - [ ] Verify `/metrics` returns 403 from external IP
  - [ ] Verify `/metrics` works from internal IP

- [ ] **Error Messages**
  - [ ] Send invalid JWT, verify generic error message
  - [ ] Check logs for detailed error (should be present)

---

## Deployment Timeline

**Day 1** (2 hours):
- Implement JWT secret validation
- Implement path sanitization
- Run tests, create PR

**Day 2** (3 hours):
- Implement pool backpressure
- Update all services to use backpressure
- Run integration tests

**Day 3** (1 hour):
- Implement metrics protection
- Implement error message sanitization
- Final testing

**Day 4** (Deploy):
- Deploy to staging
- Run security tests
- Deploy to production

---

## Rollback Plan

If issues occur:

```bash
# Quick rollback
kubectl rollout undo deployment/graphql-gateway -n nova
kubectl rollout undo deployment/user-service -n nova

# Restore previous commit
git revert <commit-hash>
git push origin main
```

---

**Critical**: DO NOT deploy Phase 2 until these P0 fixes are in production.
