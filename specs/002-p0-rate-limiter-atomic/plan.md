# Implementation Plan: Atomic Rate Limiter (Redis Lua)

**Branch**: `[002-p0-rate-limiter-atomic]` | **Date**: 2025-11-04 | **Spec**: specs/002-p0-rate-limiter-atomic/spec.md
**Input**: Feature specification from `/specs/002-p0-rate-limiter-atomic/spec.md`

## Summary

Replace TOCTOU `GET`+`SETEX` logic with a single Lua script that performs `INCR` and sets `EXPIRE` only on first increment.

## Technical Context

**Language/Version**: Rust 1.75+  
**Primary Dependencies**: `redis` crate  
**Storage**: Redis  
**Testing**: `cargo test`, `testcontainers` (Redis)  
**Target Platform**: Linux server  
**Performance Goals**: Maintain ~O(1) latency for limiter

## Project Structure

```
specs/002-p0-rate-limiter-atomic/
├── plan.md
└── spec.md

backend/user-service/src/middleware/rate_limit.rs
backend/libs/redis-utils/ (optional common script helper)
backend/user-service/tests/integration/rate_limit_concurrency_test.rs
```

## Steps

1) Add Lua script constant that returns new count and sets TTL when count==1
2) Call `EVAL` with key + ARGV(window_secs)
3) Return `is_rate_limited = count > max_requests`
4) Add integration test saturating with concurrency and verifying 429s

