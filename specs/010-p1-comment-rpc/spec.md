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

As a user, I can POST a comment to any post and see it appear in the comment feed.

**Independent Test**: CreateComment RPC with valid post_id + content → 200 + comment_id; empty content → 400.

**Acceptance Scenarios**:
1. Given valid post_id + content="Great post!", When CreateComment, Then response 200 with `{ comment_id, post_id, user_id, content, created_at }`.
2. Given invalid post_id, Then 404 post_not_found.
3. Given empty content, Then 400 invalid_comment.
4. Given content > 5000 chars, Then 400 comment_too_long.

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

## Timeline Estimate

- ~3-4 days (depends on 009-P0-A for authenticated user context)

