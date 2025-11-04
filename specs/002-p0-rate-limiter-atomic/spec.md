# Feature Specification: Atomic Rate Limiter (Redis Lua)

**Feature Branch**: `[002-p0-rate-limiter-atomic]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Fix TOCTOU race in rate limiter by using atomic Redis ops"

## Verification (code audit) — 2025-11-05

- user-service: already uses atomic Lua `INCR`+`EXPIRE` once per window.
  - Reference: `backend/user-service/src/middleware/rate_limit.rs:140-156` (EVAL script path, returns incremented count).
- content-service: still uses non-atomic `GET` → `SET_EX` (TOCTOU window under concurrency).
  - Reference: `backend/content-service/src/middleware/mod.rs:140-152`.

Action:
- Implement FR-001 in content-service middleware; reuse the user-service Lua approach and add small tests.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enforce limits under concurrency (Priority: P1)

As an operator, I need rate limits to hold when many concurrent requests arrive so attackers cannot bypass limits.

**Why this priority**: Current GET+SETEX split is non-atomic; DDoS can evade limits.

**Independent Test**: Hammer `N=max_requests+10` concurrent requests within window; observe `429` from N - max_requests.

**Acceptance Scenarios**:
1. Given `max_requests=100/window=60s`, When 200 parallel requests hit within 1 second, Then >=100 requests are rejected (429) consistently.
2. Given distributed instances, When both receive traffic, Then counters behave as if a single global limit per key.

---

### User Story 2 - Correct TTL semantics (Priority: P2)

As a developer, I want TTL set once per window (on first increment) to avoid extending windows on every hit.

**Independent Test**: After first request, TTL ~ window; subsequent increments do not reset TTL; window rolls over correctly.

### Edge Cases

- New key starts at 1 with TTL set to full window.
- Missing Redis or timeouts: default to allow but emit metrics and logs.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Replace `GET`+`SETEX` with atomic `INCR` + conditional `EXPIRE` in a Lua script.
- FR-002: Implement function that returns `(count, ttl_remaining)` for observability.
- FR-003: Add config for different windows and burst limits per route if needed in future.
- FR-004: Provide integration tests using `testcontainers` Redis verifying concurrency behavior.

### Key Entities

- Redis key: `rate_limit:{client_id}` -> counter with TTL

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: Concurrency test shows no more than `max_requests` pass in a window across 1–4 app instances.
- SC-002: TTL is not extended by subsequent increments (window fixed).
- SC-003: 0 regression in p99 latency for rate-limited endpoints (<= +2ms).
