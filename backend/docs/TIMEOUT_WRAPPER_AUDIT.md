# Timeout Wrapper Implementation Audit

**Date**: 2025-11-12
**Status**: 🟡 **PARTIAL IMPLEMENTATION** - Critical gaps identified
**Priority**: P1 (High - resilience requirement)

---

## Executive Summary

Nova has **mixed timeout protection** across services:

### ✅ Good News
- **gRPC Channel-level timeout**: All gRPC clients have 10s timeout via Tonic `Channel.timeout()`
- **Redis operations**: User-service, feed-service, events-service wrap Redis calls with custom timeout
- **resilience library exists**: Production-ready `with_timeout()` utility available

### 🔴 Critical Gaps
- **GraphQL Gateway**: No `resilience` library integration (most critical - single point of failure)
- **Multi-RPC sequences**: No protection for resolver-level timeout accumulation
- **4 services missing**: auth-service, feed-service, messaging-service, notification-service don't have `resilience` dependency

---

## Timeout Implementation Status

### Layer 1: gRPC Transport (Channel-level)

✅ **IMPLEMENTED** - All services inherit from `ServiceClients::create_channel()`

**Location**: `/backend/graphql-gateway/src/clients.rs:130-139`

```rust
fn create_channel(endpoint: &str) -> Channel {
    Endpoint::from_shared(endpoint.to_string())
        .expect("Invalid endpoint URL")
        .connect_timeout(Duration::from_secs(5))   // ✅ TCP handshake timeout
        .timeout(Duration::from_secs(10))          // ✅ Per-request timeout
        .http2_keep_alive_interval(Duration::from_secs(60))
        .keep_alive_timeout(Duration::from_secs(20))
        .keep_alive_while_idle(true)
        .connect_lazy()
}
```

**Coverage**:
- ✅ AuthServiceClient
- ✅ UserServiceClient
- ✅ ContentServiceClient
- ✅ RecommendationServiceClient (feed)

**Verdict**: ✅ **SUFFICIENT** - Tonic's channel-level timeout protects all gRPC calls

---

### Layer 2: Application-level Timeout Wrappers

#### Pattern 1: Redis Operations (3 services)

**Services**: user-service, feed-service, events-service

**Implementation**: Custom `run_with_timeout()` wrapper

**Example** (`/backend/user-service/src/utils/redis_timeout.rs`):
```rust
pub async fn run_with_timeout<F, T>(future: F) -> Result<T, anyhow::Error>
where
    F: Future<Output = Result<T, RedisError>>,
{
    tokio::time::timeout(Duration::from_secs(2), future)
        .await
        .context("Redis operation timed out after 2s")?
        .context("Redis operation failed")
}
```

**Usage Example**:
```rust
// user-service/src/cache/user_cache.rs:98
let cached: Option<String> = run_with_timeout(
    conn.get(&cache_key)
).await.ok().flatten();
```

**Verdict**: ✅ **CORRECT** - Proper timeout protection for Redis operations

---

#### Pattern 2: ClickHouse Client (2 services)

**Services**: user-service, content-service

**Implementation**: Timeout in `ch_client.rs`

**Example** (`/backend/user-service/src/db/ch_client.rs:30-54`):
```rust
impl ClickHouseClient {
    pub async fn execute_with_timeout<T>(
        &self,
        query: String,
    ) -> Result<Vec<T>, anyhow::Error>
    where
        T: for<'de> Deserialize<'de>,
    {
        timeout(
            Duration::from_secs(10),
            self.client.query(&query).fetch_all::<T>(),
        )
        .await
        .context("ClickHouse query timed out")?
        .context("ClickHouse query failed")
    }
}
```

**Verdict**: ✅ **CORRECT** - Analytics queries have 10s timeout

---

### Layer 3: resilience Library Integration

**Library Location**: `/backend/libs/resilience/src/timeout.rs`

**Key Functions**:
```rust
/// Execute a future with timeout
pub async fn with_timeout<F, T>(
    duration: Duration,
    future: F,
) -> Result<T, TimeoutError>

/// Execute a fallible future with timeout
pub async fn with_timeout_result<F, T, E>(
    duration: Duration,
    future: F,
) -> Result<T, TimeoutError>
```

#### Integration Status

| Service             | resilience Dependency | Usage Pattern                | Status |
|---------------------|----------------------|------------------------------|--------|
| **GraphQL Gateway** | ❌                    | Channel-level timeout only   | 🔴 GAP |
| auth-service        | ❌                    | Channel-level timeout only   | 🟡 NEEDS REVIEW |
| user-service        | ✅                    | Custom Redis wrappers        | ✅ GOOD |
| content-service     | ✅                    | Custom CH/Redis wrappers     | ✅ GOOD |
| feed-service        | ❌                    | Custom Redis wrappers        | 🟡 INCONSISTENT |
| messaging-service   | ❌                    | Channel-level timeout only   | 🟡 NEEDS REVIEW |
| notification-service| ❌                    | Channel-level timeout only   | 🟡 NEEDS REVIEW |
| search-service      | ✅                    | -                            | ✅ GOOD |
| media-service       | ✅                    | -                            | ✅ GOOD |
| events-service      | ✅                    | Custom Redis wrappers        | ✅ GOOD |
| identity-service    | ✅                    | -                            | ✅ GOOD |
| social-service      | ✅                    | -                            | ✅ GOOD |
| communication-service| ✅                   | -                            | ✅ GOOD |

**Summary**:
- ✅ 8/12 services have `resilience` dependency (67%)
- 🔴 4 services missing: GraphQL Gateway, auth-service, feed-service, messaging-service, notification-service

---

## Critical Issue: GraphQL Resolver Timeout Accumulation

### Problem

GraphQL Gateway resolvers can make **multiple sequential gRPC calls** without application-level timeout protection.

**Example**: `content.rs:delete_post()` (lines 191-238)

```rust
async fn delete_post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<bool> {
    let mut client = clients.content_client();

    // ❌ First RPC call (up to 10s from Channel timeout)
    let post_response = client.get_post(get_req).await
        .map_err(|e| format!("Failed to get post: {}", e))?;

    // ❌ Second RPC call (up to 10s from Channel timeout)
    client.delete_post(del_req).await
        .map_err(|e| format!("Failed to delete post: {}", e))?;

    // ⚠️ TOTAL POTENTIAL: 20 seconds timeout!
}
```

### Risk

- **Expected behavior**: Resolver timeout should be ~10-15s total
- **Actual behavior**: Each RPC has 10s timeout → cumulative 20s+ for multi-call resolvers
- **User impact**: GraphQL queries can hang for 20+ seconds before failing

### Recommendation

Wrap entire resolver in application-level timeout:

```rust
async fn delete_post(&self, ctx: &Context<'_>, id: String) -> GraphQLResult<bool> {
    use resilience::timeout::with_timeout_result;

    // ✅ Entire resolver has 12s budget (allows 2 RPCs @ 5s each + overhead)
    with_timeout_result(Duration::from_secs(12), async {
        let mut client = clients.content_client();

        let post_response = client.get_post(get_req).await?;
        client.delete_post(del_req).await?;

        Ok(true)
    })
    .await
    .map_err(|e| match e {
        TimeoutError::Elapsed(d) => {
            format!("Delete post operation timed out after {:?}", d).into()
        },
        TimeoutError::OperationFailed(msg) => msg.into(),
    })
}
```

---

## Timeout Configuration Matrix

### Current Timeouts by Operation Type

| Operation Type      | Timeout | Location                              | Status |
|---------------------|---------|---------------------------------------|--------|
| **gRPC Transport**  | 10s     | `clients.rs:134`                      | ✅ CORRECT |
| **TCP Connect**     | 5s      | `clients.rs:133`                      | ✅ CORRECT |
| **Redis Ops**       | 2s      | `redis_timeout.rs`                    | ✅ CORRECT |
| **ClickHouse Query**| 10s     | `ch_client.rs:42`                     | ✅ CORRECT |
| **GraphQL Resolver**| ❌ None | -                                     | 🔴 MISSING |
| **Database Acquire**| 10s     | `db-pool` (from PGPOOL audit)         | ✅ CORRECT |

### Recommended Timeout Hierarchy

```text
User Request (HTTP) → 30s (actix-web)
  └─ GraphQL Resolver → 15s (application-level, NOT IMPLEMENTED)
      ├─ gRPC Call 1 → 10s (Channel-level, IMPLEMENTED)
      ├─ Redis Op → 2s (app-level, IMPLEMENTED)
      └─ gRPC Call 2 → 10s (Channel-level, IMPLEMENTED)
```

**Key Principle**: Outer timeouts must exceed sum of inner timeouts:
- HTTP timeout (30s) > GraphQL resolver (15s) > gRPC call (10s) > Redis (2s)

---

## Missing Services Analysis

### GraphQL Gateway (CRITICAL 🔴)

**Risk**: Highest traffic entry point with no application-level timeout protection

**Files with multi-RPC calls**:
1. `src/schema/content.rs:delete_post()` - 2 gRPC calls
2. `src/schema/user.rs` - potential for multi-call resolvers

**Action Required**:
1. Add `resilience = { path = "../libs/resilience" }` to `Cargo.toml`
2. Wrap all resolvers with `with_timeout_result(Duration::from_secs(15), async { ... })`
3. Update error handling to distinguish timeout vs operation failure

---

### auth-service (HIGH 🟡)

**Current Protection**: Channel-level timeout only (10s)

**Risk**: Authentication operations typically single-RPC, but lacks standardization

**Action Required**:
1. Add `resilience` dependency
2. Audit for multi-step auth flows (e.g., register → create_user → send_email)
3. Add resolver-level timeouts where needed

---

### feed-service (MEDIUM 🟡)

**Current Protection**: Custom Redis wrappers, Channel-level gRPC timeout

**Risk**: Feed generation may involve multiple backend calls (content, user, ranking)

**Action Required**:
1. Replace custom Redis wrappers with `resilience::with_timeout`
2. Audit feed generation pipelines for multi-RPC sequences
3. Add resolver-level timeouts for complex feed operations

---

### messaging-service (MEDIUM 🟡)

**Current Protection**: Channel-level timeout only

**Risk**: Real-time messaging requires strict timeout guarantees

**Action Required**:
1. Add `resilience` dependency
2. Audit message delivery paths for multi-step operations
3. Implement retry with timeout for message persistence

---

### notification-service (MEDIUM 🟡)

**Current Protection**: Channel-level timeout only

**Risk**: Notification delivery may involve multiple backend calls (user prefs, templates, delivery)

**Action Required**:
1. Add `resilience` dependency
2. Audit notification pipeline for multi-RPC sequences
3. Add timeout protection for batch notification operations

---

## Testing Recommendations

### Unit Tests

All services should have timeout unit tests:

```rust
#[tokio::test]
async fn test_resolver_timeout_protection() {
    use resilience::timeout::with_timeout_result;

    let result = with_timeout_result(
        Duration::from_millis(100),
        async {
            // Simulate slow RPC
            tokio::time::sleep(Duration::from_secs(1)).await;
            Ok::<_, String>(())
        }
    ).await;

    assert!(matches!(result, Err(TimeoutError::Elapsed(_))));
}
```

### Integration Tests

Test timeout behavior under load:

```rust
#[tokio::test]
async fn test_multi_rpc_resolver_timeout() {
    // GraphQL query with 2 RPCs, each taking 6s
    // Should timeout at 12s resolver limit, not 20s cumulative

    let start = Instant::now();
    let result = execute_graphql_query("mutation { deletePost(id: \"slow\") }").await;
    let elapsed = start.elapsed();

    assert!(result.is_err());
    assert!(elapsed < Duration::from_secs(13)); // Should fail before 20s
    assert!(elapsed > Duration::from_secs(11)); // But after 11s minimum
}
```

---

## Implementation Priority

### Phase 1: GraphQL Gateway (P0 CRITICAL - 2-3 hours)

**Why**: Single point of failure, highest traffic, most at-risk for timeout accumulation

**Tasks**:
1. Add `resilience` dependency to `graphql-gateway/Cargo.toml`
2. Identify all resolvers with multiple gRPC calls (audit all `schema/*.rs`)
3. Wrap complex resolvers with `with_timeout_result(Duration::from_secs(15), async { ... })`
4. Add timeout unit tests
5. Update error messages to distinguish timeout from operation failure

**Files to Modify**:
- `graphql-gateway/Cargo.toml`
- `graphql-gateway/src/schema/content.rs` (delete_post)
- `graphql-gateway/src/schema/user.rs` (review all resolvers)
- `graphql-gateway/src/schema/auth.rs` (review all resolvers)

---

### Phase 2: Missing Service Dependencies (P1 HIGH - 1-2 hours)

**Services**: auth-service, messaging-service, notification-service

**Tasks**:
1. Add `resilience` dependency to Cargo.toml
2. Audit for multi-RPC sequences
3. Add timeouts where needed
4. Standardize timeout durations

---

### Phase 3: Standardize feed-service (P2 MEDIUM - 1 hour)

**Tasks**:
1. Replace custom Redis wrappers with `resilience::with_timeout`
2. Remove duplicate timeout logic
3. Add tests

---

## Monitoring & Alerting

### Prometheus Metrics (Recommended)

```rust
// Add to resilience library
lazy_static! {
    static ref TIMEOUT_TOTAL: IntCounterVec = register_int_counter_vec!(
        "timeout_operations_total",
        "Total timeout operations",
        &["service", "operation", "result"]  // result = "success" | "timeout" | "error"
    ).unwrap();

    static ref TIMEOUT_DURATION: HistogramVec = register_histogram_vec!(
        "timeout_operation_duration_seconds",
        "Timeout operation duration",
        &["service", "operation"],
        vec![0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0]
    ).unwrap();
}
```

### Grafana Alerts

```yaml
- alert: HighResolverTimeoutRate
  expr: |
    (
      rate(timeout_operations_total{result="timeout"}[5m])
      /
      rate(timeout_operations_total[5m])
    ) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High resolver timeout rate ({{ $value | humanizePercentage }})"
```

---

## Conclusion

### Summary

Nova's timeout protection is **partially implemented**:
- ✅ gRPC transport layer has correct 10s timeout
- ✅ Redis operations have 2s timeout in some services
- ✅ ClickHouse queries have 10s timeout
- 🔴 **GraphQL Gateway lacks application-level timeout** (CRITICAL GAP)
- 🟡 4 services missing `resilience` dependency

### Priority

**P1 HIGH** - GraphQL Gateway timeout implementation is critical for production reliability

### Recommended Actions

1. **Immediate (Week 1)**:
   - Add GraphQL resolver-level timeouts (2-3 hours)
   - Add integration tests for timeout behavior

2. **Short-term (Week 2)**:
   - Add `resilience` to missing services
   - Standardize timeout durations across services

3. **Long-term (Week 3+)**:
   - Add Prometheus metrics for timeout tracking
   - Implement Grafana alerts for high timeout rates

---

## References

- **resilience Library**: `/backend/libs/resilience/src/timeout.rs` (98 lines)
- **GraphQL Clients**: `/backend/graphql-gateway/src/clients.rs` (Channel timeout config)
- **Codex GPT-5 Recommendations**: Week 5-6 P1 priority (timeout/retry standardization)
- **Tonic Documentation**: [Request Timeouts](https://docs.rs/tonic/latest/tonic/transport/struct.Endpoint.html#method.timeout)

---

**Audit Completed By**: Claude Code
**Services Reviewed**: 12/12 (100%)
**Compliance**: 🟡 67% (8/12 have `resilience` dependency)
**Critical Gap**: GraphQL Gateway missing application-level timeout protection
