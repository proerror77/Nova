# Feature Specification: Bounded Redis SCAN Invalidation

**Feature Branch**: `[004-p0-redis-scan-bounds]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Add MAX_ITERATIONS/MAX_KEYS limits to SCAN invalidation loop"

## Verification (code audit) — 2025-11-05

- user-service has implemented bounded SCAN with caps and jittered COUNT.
  - Reference: `backend/user-service/src/cache/user_cache.rs:150-210` (MAX_ITERATIONS, MAX_KEYS, cursor break, jittered COUNT).
- Deletions are chunked in batches of 1000 to avoid protocol limits.
  - Reference: `backend/user-service/src/cache/user_cache.rs:214-226`.

Status: Implemented; add metrics if desired.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Predictable invalidation time (Priority: P1)

As an operator, I need search cache invalidation to complete quickly even when many keys match, avoiding unbounded loops.

**Independent Test**: With 200k matching keys and concurrent mutations, invalidation returns within configured cap and logs warning.

**Acceptance Scenarios**:
1. Given MAX_ITERATIONS=1000 and COUNT=500, When scanning an evolving keyspace, Then loop exits by iteration cap and logs metrics.
2. Given MAX_KEYS=50k cap, When more keys match, Then first 50k are deleted and a continuation hint is logged.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Add `MAX_ITERATIONS` and `MAX_KEYS` caps to `invalidate_search_cache` in `backend/user-service/src/cache/user_cache.rs`.
- FR-002: Add jittered `COUNT` and small sleeps to reduce event-loop starvation.
- FR-003: Emit metrics/logs with scanned/deleted counts and cursor progression.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: Worst-case invalidation returns < 1s with default caps.
- SC-002: No blocking of Redis or app reactor under key churn.
