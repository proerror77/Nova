# P0-5: Resilience Library Integration Guide

## Overview

Based on Codex GPT-5 architectural review, all external calls (database, gRPC, cache) must have explicit timeouts to prevent cascading failures. The `resilience` library provides battle-tested timeout wrappers and circuit breakers.

**Status**: Dependencies added to all V2 services. This guide shows how to integrate timeout wrappers into critical paths.

---

## Critical Issues from Codex Review

> "**Unbounded or inconsistent timeouts/retries**: Every gRPC/DB/HTTP call must have explicit deadlines and bounded retries; add circuit breakers and load‑shedding to stop cascading failures."

> "**Week 1–2 Priority**: enforce timeouts and circuit breakers"

### Timeout Recommendations

```rust
// Connection pool configuration (Codex)
connect_timeout: 5s
statement_timeout: 30s (at DB level)
service_request_timeout: 10-30s

// Per-operation timeouts (resilience lib defaults)
database: 10s
grpc: 10s
cache: 5s
http: 30s
kafka: 5s
```

---

## Integration Pattern

### Step 1: Add Dependency (✅ DONE for all V2 services)

```toml
# Cargo.toml
[dependencies]
resilience = { path = "../libs/resilience" }
```

### Step 2: Import Timeout Wrappers

```rust
use resilience::{with_db_timeout, with_grpc_timeout, with_cache_timeout};
```

### Step 3: Wrap Critical Operations

#### Database Operations

**Before (no timeout)**:
```rust
async fn get_user(pool: &PgPool, user_id: Uuid) -> Result<User> {
    sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await
        .context("Failed to fetch user")
}
```

**After (with timeout)**:
```rust
async fn get_user(pool: &PgPool, user_id: Uuid) -> Result<User> {
    with_db_timeout(async {
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await
            .context("Failed to fetch user")
    })
    .await
}
```

#### gRPC Calls

**Before (no timeout)**:
```rust
async fn call_auth_service(&self, req: AuthRequest) -> Result<AuthResponse> {
    let mut client = self.auth_client.clone();
    client
        .authenticate(tonic::Request::new(req))
        .await
        .map(|r| r.into_inner())
        .context("Auth service call failed")
}
```

**After (with timeout)**:
```rust
async fn call_auth_service(&self, req: AuthRequest) -> Result<AuthResponse> {
    with_grpc_timeout(async {
        let mut client = self.auth_client.clone();
        client
            .authenticate(tonic::Request::new(req))
            .await
            .map(|r| r.into_inner())
            .context("Auth service call failed")
    })
    .await
}
```

#### Redis Operations

**Before (no timeout)**:
```rust
async fn get_cached_user(redis: &mut ConnectionManager, key: &str) -> Result<Option<User>> {
    let value: Option<String> = redis::cmd("GET")
        .arg(key)
        .query_async(redis)
        .await
        .context("Redis GET failed")?;

    value.map(|s| serde_json::from_str(&s)).transpose()
}
```

**After (with timeout)**:
```rust
async fn get_cached_user(redis: &mut ConnectionManager, key: &str) -> Result<Option<User>> {
    with_cache_timeout(async {
        let value: Option<String> = redis::cmd("GET")
            .arg(key)
            .query_async(redis)
            .await
            .context("Redis GET failed")?;

        value.map(|s| serde_json::from_str(&s)).transpose()
    })
    .await
}
```

---

## Circuit Breaker Pattern (Advanced)

For frequently failing dependencies, add circuit breakers to fail fast:

```rust
use resilience::CircuitBreaker;

// Service initialization
let breaker = CircuitBreaker::new(
    5,   // failure_threshold: open after 5 failures
    3,   // success_threshold: close after 3 successes in half-open
    Duration::from_secs(60),  // timeout: stay open for 60s
    10,  // half_open_max_calls: allow 10 probes in half-open state
);

// Usage
let result = breaker.call(|| async {
    // Your operation
    external_service_call().await
}).await;
```

---

## Priority Integration Points

### High Priority (Week 1)

1. **identity-service**: All authentication DB queries and Redis token operations
2. **user-service**: User profile queries, follow graph operations
3. **content-service**: Post/comment queries, feed generation
4. **GraphQL Gateway**: All gRPC calls to backend services

### Medium Priority (Week 2)

5. **search-service**: Elasticsearch queries, index operations
6. **events-service**: Kafka produce operations
7. **media-service**: S3 operations, transcoding job submissions
8. **social-service**: Follow/unfollow DB transactions
9. **communication-service**: Message delivery, push notifications

---

## Configuration Override (Environment Variables)

The `resilience` library respects environment variables for timeout tuning:

```bash
# Override default timeouts
RESILIENCE_DB_TIMEOUT_SECS=15
RESILIENCE_GRPC_TIMEOUT_SECS=10
RESILIENCE_CACHE_TIMEOUT_SECS=5
```

---

## Testing Timeout Behavior

### Unit Test Example

```rust
#[tokio::test]
async fn test_timeout_triggers() {
    let result = with_db_timeout(async {
        // Simulate slow query
        tokio::time::sleep(Duration::from_secs(15)).await;
        Ok::<_, anyhow::Error>(())
    })
    .await;

    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("timed out"));
}
```

### Integration Test with Real Services

```rust
#[tokio::test]
async fn test_grpc_call_with_timeout() {
    let auth_client = AuthClient::new("http://localhost:50051").await.unwrap();

    let result = with_grpc_timeout(async {
        auth_client.authenticate(invalid_token).await
    })
    .await;

    // Should complete within 10s or timeout
    assert!(result.is_ok() || result.unwrap_err().to_string().contains("timed out"));
}
```

---

## Monitoring & Alerting

### Metrics to Track

```rust
// Example Prometheus metrics
counter!("resilience_timeouts_total", "operation" => "database");
counter!("resilience_timeouts_total", "operation" => "grpc");
histogram!("operation_duration_seconds", "operation" => "database");
```

### Alert Rules

```yaml
# Prometheus alert rules
- alert: HighDatabaseTimeoutRate
  expr: rate(resilience_timeouts_total{operation="database"}[5m]) > 0.1
  for: 5m
  annotations:
    summary: "Database timeout rate > 10%"

- alert: CircuitBreakerOpen
  expr: circuit_breaker_state == 2  # 2 = Open
  for: 2m
  annotations:
    summary: "Circuit breaker opened for {{ $labels.service }}"
```

---

## Rollout Strategy

### Phase 1: Add Dependencies (✅ COMPLETE)
- All V2 services have `resilience` dependency in Cargo.toml

### Phase 2: Critical Path Integration (IN PROGRESS)
- Wrap database authentication queries (identity-service)
- Wrap gRPC calls in GraphQL Gateway
- Wrap feed generation queries (content-service)

### Phase 3: Full Coverage (Week 2-3)
- Systematic review of all DB queries
- All gRPC calls wrapped
- All Redis operations wrapped
- Circuit breakers added to unstable dependencies

### Phase 4: Tuning (Week 4+)
- Monitor timeout metrics
- Adjust thresholds based on P95/P99 latencies
- Add custom timeouts for known slow operations

---

## Common Pitfalls

### ❌ DON'T: Wrap entire functions
```rust
// BAD: Wraps too much, loses granularity
async fn get_user_profile(user_id: Uuid) -> Result<Profile> {
    with_db_timeout(async {
        let user = fetch_user(user_id).await?;
        let posts = fetch_posts(user_id).await?;
        let followers = fetch_followers(user_id).await?;
        build_profile(user, posts, followers)
    }).await
}
```

### ✅ DO: Wrap individual I/O operations
```rust
// GOOD: Each I/O operation has its own timeout
async fn get_user_profile(user_id: Uuid) -> Result<Profile> {
    let user = with_db_timeout(fetch_user(user_id)).await?;
    let posts = with_db_timeout(fetch_posts(user_id)).await?;
    let followers = with_db_timeout(fetch_followers(user_id)).await?;
    Ok(build_profile(user, posts, followers))
}
```

### ❌ DON'T: Ignore timeout errors
```rust
// BAD: Swallows timeout information
let result = with_db_timeout(query).await.ok();
```

### ✅ DO: Propagate with context
```rust
// GOOD: Preserves error chain
let result = with_db_timeout(query)
    .await
    .context("Failed to fetch user profile")?;
```

---

## Next Steps

1. **Review this guide** with the team
2. **Start with identity-service** (authentication is critical path)
3. **Add metrics/logging** for timeout events
4. **Monitor production** for false positives
5. **Tune timeouts** based on real P95/P99 latencies

---

## References

- Codex GPT-5 Architecture Review (2025-11-11)
- `backend/libs/resilience/src/lib.rs` - Library implementation
- P0 Implementation Checklist - Week 1 priorities

---

**Author**: Nova Backend Team
**Last Updated**: 2025-11-11
**Status**: Phase 2 - Critical Path Integration
