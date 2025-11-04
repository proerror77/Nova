# Tasks: Circuit Breaker Pattern

**Input**: Design documents from `/specs/012-p2-circuit-breaker/`
**Prerequisites**: plan.md, spec.md, 006-p0-testcontainers completion

## Phase 1: Middleware Standardization (1-2 days)

- [ ] T001 [P] Create `backend/libs/circuit-breaker` crate with tower::ServiceLayer
- [ ] T002 [P] Define fallback trait per service (cache, queue, empty response)
- [ ] T003 Apply middleware to all cross-service gRPC calls

## Phase 2: Fallback Logic (1 day)

- [ ] T010 feed-service → content-service: fallback to cache
- [ ] T011 messaging-service → user-service: fallback to queue
- [ ] T012 content-service → feed-service: fallback graceful

## Phase 3: Metrics + Tests (1 day)

- [ ] T020 [P] Add metrics: open/closed/half-open state transitions
- [ ] T021 [P] Integration tests: failure injection → fallback verified

