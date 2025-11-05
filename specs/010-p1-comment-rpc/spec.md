# Feature Specification: CreateComment RPC Implementation

**Feature Branch**: `[010-p1-comment-rpc]`
**Created**: 2025-11-05
**Status**: Draft
**Priority**: P1 (Core feature - enables comments on posts)
**Input**: Decomposed from former 009-p2-core-features

## Verification (code audit) — 2025-11-05

- Current state: content-service has no CreateComment RPC
- Read paths exist: GetPostsByIds, GetPostsByAuthor (Phase 2)
- Database: comments table exists with (id, post_id, user_id, content, created_at, deleted_at)
- Cache: Redis pattern for comment lists exists

**Action**:
- Implement CreateComment RPC in content-service
- Validate input (content length, post exists)
- Persist to database
- Trigger cache invalidation for post's comment list
- Return created comment with id + timestamp

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add comment to post (Priority: P1)

As a service client, I can call content-service.CreateComment(post_id, content, user_id) gRPC RPC to add a comment to a post.

**Independent Test**: CreateComment gRPC RPC with valid post_id + content → Status::Ok with comment_id; invalid input → gRPC error (INVALID_ARGUMENT or NOT_FOUND).

**Acceptance Scenarios**:
1. Given valid post_id + content="Great post!", When calling CreateComment gRPC, Then response Status::Ok with `{ comment_id, post_id, user_id, content, created_at }`.
2. Given invalid post_id, Then Status::NotFound (gRPC code 5) with message `post_not_found`.
3. Given empty content, Then Status::InvalidArgument (gRPC code 3) with message `comment_empty`.
4. Given content > 5000 chars, Then Status::InvalidArgument with message `comment_too_long`.

---

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: gRPC CreateComment(post_id, content, user_id) → Comment
- FR-002: Validate post exists before inserting comment
- FR-003: Validate content: 1-5000 chars, trimmed
- FR-004: Soft delete filtering on queries (deleted_at IS NULL)
- FR-005: Invalidate Redis comment list cache for post after insert
- FR-006: Rate limit: max 10 comments per user per minute

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: `cargo test -p content-service` includes CreateComment tests (100% pass)
- SC-002: E2E: CreateComment + GetComments shows new comment < 200ms latency
- SC-003: Cache invalidation verified (comment list rebuilt on next read)
- SC-004: Rate limiter blocks >10 comments/min per user

---

## Observability Requirements *(mandatory - per Constitution Principle VI)*

### Prometheus Metrics

- `create_comment_requests_total` — Counter for all CreateComment RPC calls
- `create_comment_latency_seconds` — Histogram of latency (buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1.0])
- `create_comment_errors_total` — Counter by error type (validation_failed, post_not_found, rate_limited)
- `cache_invalidation_duration_seconds` — Histogram for cache invalidation latency

### Distributed Tracing (OpenTelemetry)

- Trace all CreateComment requests with spans for:
  - `post_validation` — Check post exists
  - `content_validation` — Validate comment content
  - `db_insert` — Database persistence
  - `cache_invalidation` — Redis cache invalidation
  - `rate_limit_check` — Rate limiter verification

### Logging

- Structured logs for:
  - Comment creation success (user_id, post_id, comment_id)
  - Validation failures (reason, input details)
  - Rate limit violations (user_id, attempt_timestamp)

---

## Timeline Estimate

- ~3-4 days (depends on 009-P0-A for authenticated user context)

