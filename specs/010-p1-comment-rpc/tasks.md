# Tasks: CreateComment RPC Implementation

**Input**: Design documents from `/specs/010-p1-comment-rpc/`
**Prerequisites**: plan.md, spec.md, 009-p0-auth-register-login completion

## Phase 1: Database Layer (1 day)

- [ ] T001 [P] Implement `CommentDb::insert_comment(post_id, user_id, content) -> Result<Comment>`
- [ ] T002 [P] Implement `CommentDb::post_exists(post_id) -> Result<bool>`
- [ ] T003 Implement `CommentDb::get_comments_for_post(post_id, limit, offset) -> Result<Vec<Comment>>`

## Phase 2: RPC + Validation (1 day)

- [ ] T010 [P] Add CreateComment RPC to content-service proto + implementation
- [ ] T011 [P] Validate content: 1-5000 chars, trim whitespace
- [ ] T012 [P] Return 404 if post doesn't exist
- [ ] T013 Rate limit: max 10 comments per user per minute (use rate_limit middleware)

## Phase 3: Cache + Tests (1-2 days)

- [ ] T020 [P] Invalidate Redis `post:{post_id}:comments` after insert
- [ ] T021 [P] Integration test: CreateComment + GetComments → new comment visible
- [ ] T022 Integration test: Rate limit enforced (>10/min rejected)
- [ ] T023 Load test: 100 concurrent CreateComment → p95 < 200ms

