# Resilience Patterns - Deep Dive

This document provides detailed explanations of resilience patterns implemented in this library, including theory, implementation details, and real-world scenarios.

---

## Table of Contents

1. [Circuit Breaker Pattern](#circuit-breaker-pattern)
2. [Timeout Pattern](#timeout-pattern)
3. [Retry Pattern](#retry-pattern)
4. [Bulkhead Pattern](#bulkhead-pattern)
5. [Combining Patterns](#combining-patterns)
6. [Anti-Patterns](#anti-patterns)

---

## Circuit Breaker Pattern

### Theory

The Circuit Breaker pattern prevents cascading failures in distributed systems by:
1. Monitoring call failures
2. Opening the circuit when threshold is reached (failing fast)
3. Allowing limited test calls after cooldown
4. Closing the circuit if tests succeed

**Analogy**: Like an electrical circuit breaker that trips when current is too high, preventing damage to the system.

### State Machine

```
┌─────────┐
│ Closed  │ ───── failure_threshold ────┐
└─────────┘                              │
     ↑                                   ↓
     │                             ┌──────────┐
     │                             │   Open   │
     │                             └──────────┘
     │                                   │
     │                                   │ timeout
     │                                   ↓
     │                             ┌──────────┐
     └─── success_threshold ───── │ HalfOpen │
                                  └──────────┘
                                        │
                                        │ any failure
                                        ↓
                                  ┌──────────┐
                                  │   Open   │
                                  └──────────┘
```

### Implementation Details

#### Sliding Window Error Rate

The circuit breaker tracks the last N requests (configurable via `window_size`) and calculates the error rate:

```rust
error_rate = failures / total_requests

// Example: 60 failures out of 100 requests = 60% error rate
```

#### Dual Threshold Logic

Circuit opens when EITHER:
1. **Consecutive failures** >= `failure_threshold`
2. **Error rate** >= `error_rate_threshold`

**Rationale**: Consecutive failures catch sudden outages, error rate catches gradual degradation.

### Real-World Scenarios

#### Scenario 1: Database Connection Pool Exhausted

```
Time | Event                    | State    | Action
-----|--------------------------|----------|------------------
0s   | DB pool exhausted        | Closed   | All calls timeout
5s   | 5 consecutive timeouts   | Open     | Fail fast (no DB calls)
65s  | Timeout elapsed          | HalfOpen | Allow test call
66s  | Test call succeeds       | HalfOpen | Allow another test
67s  | 2nd test succeeds        | Closed   | Resume normal operation
```

#### Scenario 2: Gradual Service Degradation

```
Time | Event                    | Error Rate | State    | Action
-----|--------------------------|------------|----------|------------------
0s   | Service healthy          | 5%         | Closed   | Normal
10s  | Service degrading        | 40%        | Closed   | Still below threshold
20s  | Service degrading more   | 60%        | Open     | Error rate > 50%
80s  | Timeout elapsed          | N/A        | HalfOpen | Test recovery
```

### Configuration Guidelines

| Scenario | failure_threshold | success_threshold | timeout | error_rate_threshold |
|----------|-------------------|-------------------|---------|----------------------|
| Internal gRPC | 5 | 2 | 60s | 50% |
| Database | 10 | 3 | 30s | 60% |
| External API | 5 | 2 | 120s | 50% |
| Cache | 3 | 2 | 15s | 50% |

**Guidelines**:
- **failure_threshold**: Lower for critical dependencies (3-5), higher for less critical (10+)
- **success_threshold**: 2-3 successes to confirm recovery
- **timeout**: Longer for external services (120s), shorter for internal (30-60s)
- **error_rate_threshold**: 50% is a good default

---

## Timeout Pattern

### Theory

Timeouts prevent resource exhaustion by enforcing time limits on operations. Without timeouts:
- Threads/tasks blocked indefinitely
- Connection pool exhaustion
- Cascading failures

**Principle**: **Every external call MUST have a timeout** (Codex GPT-5 P0 requirement).

### Implementation

```rust
pub async fn with_timeout<F, T>(
    duration: Duration,
    future: F,
) -> Result<T, TimeoutError>
where
    F: Future<Output = T>,
{
    tokio::time::timeout(duration, future)
        .await
        .map_err(|_| TimeoutError::Elapsed(duration))
}
```

### Real-World Scenarios

#### Scenario 1: Slow Database Query

```
Time | Event                    | Action
-----|--------------------------|------------------------------------------
0s   | Execute query            | Query starts
9s   | Query still running      | Still waiting
10s  | Timeout reached          | Cancel query, return TimeoutError
```

**Benefit**: Prevents connection pool from being blocked by slow queries.

#### Scenario 2: Unresponsive External API

```
Time | Event                    | Action
-----|--------------------------|------------------------------------------
0s   | Call external API        | HTTP request sent
30s  | No response              | Still waiting
60s  | Timeout reached          | Cancel request, return error
```

**Benefit**: Allows retry logic to kick in or fallback to cached data.

### Configuration Guidelines

| Operation Type | Timeout | Rationale |
|---------------|---------|-----------|
| Redis GET | 1-5s | Cache should be fast |
| Database SELECT | 10s | Queries should be optimized |
| Database UPDATE | 30s | Writes can be slower (locks) |
| Internal gRPC | 30s | Allow for complex operations |
| External HTTP | 60s | Third-party services can be slow |
| S3 Upload | 120s | Large files take time |

**Guidelines**:
1. Start with presets
2. Monitor P99 latency
3. Set timeout = P99 * 2-3
4. Iterate based on production data

---

## Retry Pattern

### Theory

Retries handle transient failures (temporary errors that resolve themselves):
- Network glitches
- Rate limit 429 errors
- Temporary service unavailability

**Key Decision**: **Is the operation idempotent?**
- ✅ **Idempotent** (GET, PUT, DELETE): Safe to retry
- ❌ **Non-idempotent** (POST without idempotency key): Don't retry

### Exponential Backoff

Doubles delay between retries to avoid overwhelming the service:

```
Attempt 1: 100ms
Attempt 2: 200ms (100ms * 2)
Attempt 3: 400ms (200ms * 2)
Attempt 4: 800ms (400ms * 2)
...
```

### Jitter

Adds random variance (±30%) to prevent thundering herd:

```
Without jitter:
Client 1: 100ms, 200ms, 400ms
Client 2: 100ms, 200ms, 400ms  ← All clients retry at same time
Client 3: 100ms, 200ms, 400ms

With jitter:
Client 1: 85ms, 230ms, 370ms
Client 2: 110ms, 180ms, 420ms   ← Spread out
Client 3: 95ms, 210ms, 390ms
```

### Implementation

```rust
pub async fn with_retry<F, Fut, T, E>(
    config: RetryConfig,
    mut f: F,
) -> Result<T, RetryError<E>>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, E>>,
{
    let mut attempt = 0;
    let mut backoff = config.initial_backoff;

    loop {
        match f().await {
            Ok(result) => return Ok(result),
            Err(_) => {
                attempt += 1;
                if attempt > config.max_retries {
                    return Err(RetryError::MaxRetriesExceeded(config.max_retries));
                }

                let delay = calculate_backoff(backoff, config.jitter);
                tokio::time::sleep(delay).await;

                backoff = Duration::from_millis(
                    (backoff.as_millis() as f64 * config.backoff_multiplier)
                        .min(config.max_backoff.as_millis() as f64) as u64
                );
            }
        }
    }
}
```

### Real-World Scenarios

#### Scenario 1: Transient Network Error

```
Time | Attempt | Event                | Action
-----|---------|----------------------|-------------------------
0s   | 1       | Network timeout      | Wait 100ms
0.1s | 2       | Connection refused   | Wait 200ms
0.3s | 3       | Success              | Return result
```

#### Scenario 2: Rate Limit

```
Time | Attempt | Event                | Action
-----|---------|----------------------|-------------------------
0s   | 1       | 429 Too Many Reqs    | Wait 500ms
0.5s | 2       | 429 Too Many Reqs    | Wait 1s
1.5s | 3       | 429 Too Many Reqs    | Wait 2s
3.5s | 4       | 200 OK               | Return result
```

### Configuration Guidelines

| Scenario | max_retries | initial_backoff | max_backoff | jitter |
|----------|-------------|-----------------|-------------|--------|
| Internal gRPC | 3 | 100ms | 5s | true |
| External API | 5 | 500ms | 30s | true |
| Cache (Redis) | 2 | 50ms | 1s | true |
| Database | 0 | N/A | N/A | N/A |

**Guidelines**:
- **max_retries**: 3-5 for idempotent operations, 0 for writes
- **initial_backoff**: 50-500ms depending on expected latency
- **max_backoff**: Cap at 5-30s to prevent excessive delays
- **jitter**: Always enable (true) for production

---

## Bulkhead Pattern

### Theory

Bulkhead pattern isolates resources to prevent cascading failures:
- Separate thread pools per dependency
- Limit concurrent requests
- Prevent one service from exhausting all resources

**Analogy**: Ship compartments (bulkheads) prevent entire ship from sinking if one compartment floods.

### Implementation (via Tower)

```rust
use tower::limit::ConcurrencyLimit;

let service = ServiceBuilder::new()
    .concurrency_limit(100) // Max 100 concurrent requests
    .service(my_service);
```

### Real-World Scenario

```
Scenario: High load on User Service, Feed Service should not be affected

Without bulkhead:
User Service: 1000 requests/s → Thread pool exhausted
Feed Service: Cannot get threads → Both services down

With bulkhead:
User Service: 1000 requests/s → Max 100 concurrent, rest queued
Feed Service: Separate pool → Still operational
```

---

## Combining Patterns

### Defense in Depth

Combine patterns for maximum resilience:

```rust
let config = presets::grpc_config();
let circuit_breaker = CircuitBreaker::new(config.circuit_breaker);

let result = circuit_breaker.call(|| async {
    with_timeout_result(config.timeout.duration, async {
        with_retry(config.retry.unwrap(), || async {
            grpc_client.call(request).await
        }).await
    }).await
}).await;
```

**Execution Flow**:
1. **Circuit Breaker**: Check if circuit is open → If yes, fail fast
2. **Timeout**: Enforce 30s deadline → If exceeded, cancel
3. **Retry**: Attempt up to 3 times with backoff → If all fail, propagate error
4. **Circuit Breaker**: Record failure → May open circuit

### Pattern Selection Matrix

| Scenario | Circuit Breaker | Timeout | Retry | Bulkhead |
|----------|-----------------|---------|-------|----------|
| Internal gRPC | ✅ | ✅ | ✅ | ✅ |
| Database SELECT | ✅ | ✅ | ❌ | ✅ |
| Database INSERT | ✅ | ✅ | ❌ | ✅ |
| Redis GET | ✅ | ✅ | ✅ | ✅ |
| External HTTP | ✅ | ✅ | ✅ | ✅ |
| Kafka Produce | ✅ | ✅ | ✅ | ✅ |

---

## Anti-Patterns

### ❌ Anti-Pattern 1: Retrying Non-Idempotent Operations

```rust
// DON'T DO THIS
let result = with_retry(config, || async {
    db.execute("INSERT INTO orders (user_id, amount) VALUES ($1, $2)", ...)
        .await
}).await;
```

**Problem**: May create duplicate orders.

**Solution**: Use idempotency keys or don't retry writes.

### ❌ Anti-Pattern 2: No Timeout on External Calls

```rust
// DON'T DO THIS
let response = reqwest::get("https://external-api.com/slow").await?;
```

**Problem**: May block indefinitely.

**Solution**: Always wrap external calls with timeout.

```rust
// DO THIS
let response = with_timeout(
    Duration::from_secs(60),
    reqwest::get("https://external-api.com/slow")
).await?;
```

### ❌ Anti-Pattern 3: Circuit Breaker Per Request

```rust
// DON'T DO THIS
async fn handle_request() {
    let cb = CircuitBreaker::new(config); // New instance per request
    cb.call(|| async { ... }).await
}
```

**Problem**: Circuit breaker state is not shared, defeats the purpose.

**Solution**: Use a single instance shared across requests (Arc).

```rust
// DO THIS
struct AppState {
    user_service_cb: Arc<CircuitBreaker>,
}

async fn handle_request(state: Arc<AppState>) {
    state.user_service_cb.call(|| async { ... }).await
}
```

### ❌ Anti-Pattern 4: Too Short Timeout

```rust
// DON'T DO THIS
with_timeout(Duration::from_millis(100), async {
    complex_database_join().await // P99 = 500ms
}).await
```

**Problem**: 99% of requests will timeout.

**Solution**: Set timeout >= P99 * 2.

### ❌ Anti-Pattern 5: Retrying Circuit Breaker Open Errors

```rust
// DON'T DO THIS
with_retry(config, || async {
    cb.call(|| async { ... }).await
}).await
```

**Problem**: Circuit breaker open means service is down, retrying is useless.

**Solution**: Let circuit breaker handle failures, don't wrap with retry.

---

## Further Reading

- [Microsoft: Circuit Breaker Pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/circuit-breaker)
- [Netflix: Hystrix](https://github.com/Netflix/Hystrix/wiki/How-it-Works)
- [AWS: Implementing Retries](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)
- [Google SRE Book: Handling Overload](https://sre.google/sre-book/handling-overload/)

---

## Contributing

When adding new patterns, follow these guidelines:

1. **Add comprehensive tests** (at least 5 tests per pattern)
2. **Document real-world scenarios** (when to use, when not to use)
3. **Provide preset configurations** (tuned for common use cases)
4. **Add Prometheus metrics** (if metrics feature is enabled)
5. **Update README.md** (with usage examples)
