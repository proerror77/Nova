# Timeout Protection for gRPC and Redis Operations

**Status**: ✅ Implemented
**Date**: 2025-11-09
**Risk Level**: P0 (prevents cascading failures)

## Problem

Missing timeout configurations can cause cascading failures when downstream services (gRPC, Redis) are slow or unresponsive. Without timeouts:
- A single slow Redis query blocks the entire request thread
- gRPC calls to unreachable services hang indefinitely
- Backpressure cascades through the system, eventually crashing all services

## Solution

### gRPC Client Timeouts

**Already implemented** in `backend/libs/grpc-clients/src/config.rs`:

```rust
// Existing configuration (no changes needed)
GRPC_CONNECTION_TIMEOUT_SECS=10  // TCP connection timeout
GRPC_REQUEST_TIMEOUT_SECS=30     // Individual request timeout
GRPC_KEEPALIVE_INTERVAL_SECS=30  // Keep-alive pings
GRPC_KEEPALIVE_TIMEOUT_SECS=10   // Keep-alive response deadline
```

**Enhanced** with `keep_alive_while_idle(true)` to detect broken connections faster.

### Redis Command Timeouts

**New utility** in `backend/libs/redis-utils/src/lib.rs`:

```rust
use redis_utils::with_timeout;

// Usage: Wrap all Redis commands
let exists: bool = redis_utils::with_timeout(async {
    redis::cmd("EXISTS")
        .arg(&key)
        .query_async(&mut conn)
        .await
})
.await?;
```

**Configuration**:
```bash
REDIS_COMMAND_TIMEOUT_MS=3000  # Default: 3 seconds, minimum: 500ms
```

## Updated Services

### ✅ auth-service
- **File**: `backend/auth-service/src/security/token_revocation.rs`
- **Functions**: All Redis operations (`revoke_token`, `is_token_revoked`, etc.)
- **Before**: Direct `.query_async()` (no timeout)
- **After**: Wrapped with `redis_utils::with_timeout()`

### ✅ feed-service
- **File**: Already had timeout wrapper in `src/utils/redis_timeout.rs`
- **Action**: Can now migrate to shared `redis_utils::with_timeout()`

### ✅ actix-middleware (rate limiter)
- **File**: `backend/libs/actix-middleware/src/rate_limit.rs`
- **Status**: Already has timeout via `tokio::time::timeout` (no changes needed)

## Environment Variables

Added to `backend/.env.example`:

```bash
# Redis command timeout (milliseconds)
# Prevents cascading failures when Redis is slow or unresponsive
# Default: 3000ms (3 seconds), minimum: 500ms
REDIS_COMMAND_TIMEOUT_MS=3000
```

## Linus-Style Review

### Good Taste ✅
- **No special cases**: Timeout is part of the data structure (configuration), not runtime exception handling
- **Simple pattern**: One function (`with_timeout`), reusable everywhere
- **Eliminated branches**: No need for `match timeout() { Ok(Ok(..)), Ok(Err(..)), Err(..) }` nested Results

### Backward Compatibility ✅
- gRPC: Existing config still works (added one field, no breaking changes)
- Redis: Default 3-second timeout is conservative (won't break slow queries in dev)
- Environment variable: Falls back to default if not set

### Real Problem ✅
- Production-grade issue: Redis/gRPC hangs are common causes of cascading failures
- Complexity matches severity: Simple wrapper function, not over-engineered
- Testable: Can verify timeout behavior with slow Redis in integration tests

## Testing

### Manual Verification
```bash
# Test Redis timeout (requires running Redis)
cd backend/auth-service
cargo test --lib token_revocation
```

### Integration Test (TODO)
Add test in `backend/tests/integration/fault_injection.rs`:
- Start Redis with `tc` (Linux traffic control) to simulate 5-second latency
- Call `is_token_revoked()` → should timeout after 3 seconds
- Verify error message: "redis command timed out"

## Metrics (Future Enhancement)

Could add counters for timeout tracking:
```rust
// backend/libs/grpc-metrics/src/lib.rs
lazy_static! {
    static ref GRPC_TIMEOUT_TOTAL: CounterVec = register_counter_vec!(
        "grpc_client_timeout_total",
        "gRPC client timeout count",
        &["service", "method"]
    ).unwrap();

    static ref REDIS_TIMEOUT_TOTAL: CounterVec = register_counter_vec!(
        "redis_timeout_total",
        "Redis command timeout count",
        &["operation"]
    ).unwrap();
}
```

## Files Modified

- `backend/libs/grpc-clients/src/config.rs` - Added `keep_alive_while_idle(true)`
- `backend/libs/redis-utils/src/lib.rs` - Added `with_timeout()` function
- `backend/libs/redis-utils/Cargo.toml` - Added `once_cell` dependency
- `backend/auth-service/src/security/token_revocation.rs` - Applied timeout wrapper
- `backend/.env.example` - Documented `REDIS_COMMAND_TIMEOUT_MS`
- `backend/TIMEOUT_PROTECTION.md` - This document

## Summary

**Changed**:
- ✅ gRPC: Enhanced keep-alive (one line)
- ✅ Redis: Centralized timeout wrapper (20 lines)
- ✅ auth-service: Protected all Redis calls (4 functions)

**Not Changed**:
- ❌ No new configuration structures (used env vars + constants)
- ❌ No breaking API changes (backward compatible)
- ❌ No complex retry logic (kept it simple)

**Result**: Production-grade timeout protection with minimal code changes.
