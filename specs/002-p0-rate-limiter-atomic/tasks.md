# Tasks: Atomic Rate Limiter (Redis Lua)

**Input**: Design documents from `/specs/002-p0-rate-limiter-atomic/`

## Phase 1: Implementation

- [ ] T001 Replace logic in `backend/user-service/src/middleware/rate_limit.rs` with Lua-based atomic increment
- [ ] T002 Return `(count, ttl_remaining)` for observability (optional)
- [ ] T003 Add config to `backend/user-service/src/config/mod.rs` to support per-endpoint overrides (future-proof)

## Phase 2: Tests

- [ ] T010 Add Redis testcontainer harness `backend/user-service/tests/integration/rate_limit_concurrency_test.rs`
- [ ] T011 Verify no more than `max_requests` pass under parallel load
- [ ] T012 Verify TTL is set once and not extended

