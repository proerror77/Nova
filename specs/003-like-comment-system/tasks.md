# Tasks: 贴文互动系统（点赞与评论）

**Feature Branch**: `003-like-comment-system`
**Generated**: 2025-10-18
**Status**: Ready for Implementation
**Blocking Requirements**: 001-post-publish-system (provides Post table)

## Implementation Strategy

**MVP Scope**: User Story 1 + US2 (Likes + Comments)
- Core social interactions
- Drives engagement
- Triggers notifications (if 005 ready)
- Estimated: 1-2 weeks

**Phase 2 Extensions**: US3 (Delete comments)
- User content management
- Post author moderation

## Phase 1: Setup & Infrastructure

- [ ] T001 Create Like table migration in `src/db/migrations/005_create_likes.sql`
  - user_id, post_id, created_at
  - Unique constraint (user_id, post_id)
- [ ] T002 Create Comment table migration in `src/db/migrations/006_create_comments.sql`
  - id, post_id, user_id, content, created_at, updated_at
- [ ] T003 Create Like model struct in `src/models/like.rs`
- [ ] T004 Create Comment model struct in `src/models/comment.rs`
- [ ] T005 Set up error handling in `src/errors/interaction_errors.rs`
  - Duplicate like error
  - Comment too long error
  - Invalid post error

## Phase 2: Foundational Services (Blocking Prerequisites)

- [ ] T006 Implement caption/content validation in `src/services/content_validator.rs`
  - Max 300 characters
  - No empty content
  - Support Unicode and Emoji
- [ ] T007 Create atomic like count update in `src/services/like_service.rs`
  - Transaction: INSERT Like AND UPDATE Post.like_count
  - Handle duplicate error (unique constraint)
- [ ] T008 Create atomic comment count update in `src/services/comment_service.rs`
  - Transaction: INSERT Comment AND UPDATE Post.comment_count
- [ ] T009 Implement event publishing setup in `src/events/mod.rs`
  - Define Like events: like_created, like_deleted
  - Define Comment events: comment_created, comment_deleted

## Phase 3: User Story 1 - 用户点赞贴文 (P1)

**Goal**: Users can toggle like on posts (idempotent), like count updated immediately

**Independent Test Criteria**:
- Like increases post.like_count by 1
- Second like (on same post by same user) decreases by 1 (toggle)
- Like button shows is_liked = true when liked
- Like button shows is_liked = false when unliked
- Concurrent likes handled correctly (no race conditions)

### Implementation Tasks

- [ ] T010 [US1] Create POST `/api/v1/posts/{post_id}/like` endpoint in `src/handlers/interactions.rs`
  - Toggle like (create if not exists, delete if exists)
  - Returns updated post like_count
- [ ] T011 [US1] Implement Like toggle logic in `src/services/like_service.rs`
  - Check if Like record exists (user_id, post_id)
  - If exists: DELETE and decrement like_count
  - If not exists: INSERT and increment like_count
  - Use transaction for atomicity
- [ ] T012 [US1] Add JWT middleware to like endpoint in `src/middleware/auth.rs`
- [ ] T013 [US1] Create LikeResponse DTO in `src/models/like.rs`
  - id, post_id, user_id, created_at, post_like_count
- [ ] T014 [US1] Handle concurrent like requests in `src/services/like_service.rs`
  - Use pessimistic locking on Post row during update
  - OR optimistic locking with version field
- [ ] T015 [US1] Create integration test for like toggle in `tests/integration/like_tests.rs`
  - Create post, user, like, verify count = 1
  - Like again, verify count = 0
  - Verify is_liked flag toggles

## Phase 4: User Story 2 - 用户评论贴文 (P1)

**Goal**: Users can submit comments, comments appear immediately with author info

**Independent Test Criteria**:
- Comment appears in comment list immediately after creation
- Comment shows author username, avatar, content
- Comment count incremented
- Empty comment rejected (400 error)
- 350-char comment rejected (400 error)
- 300-char comment accepted

### Implementation Tasks

- [ ] T016 [US2] Create POST `/api/v1/posts/{post_id}/comments` endpoint in `src/handlers/interactions.rs`
  - Accept content (1-300 chars)
  - Return created Comment with user data
- [ ] T017 [US2] Implement comment creation in `src/services/comment_service.rs`
  - Validate content length
  - Create Comment record with user_id and post_id
  - Increment post.comment_count atomically
  - Publish comment_created event
- [ ] T018 [US2] Create CommentRequest and CommentResponse DTOs in `src/models/comment.rs`
  - Request: { content: String }
  - Response: { id, post_id, user: {id, username, avatar_url}, content, created_at }
- [ ] T019 [US2] Create GET `/api/v1/posts/{post_id}/comments` endpoint in `src/handlers/interactions.rs`
  - Accept limit (default 20, max 100), cursor for pagination
  - Return array of comments sorted by created_at
- [ ] T020 [US2] Implement comment list query in `src/services/comment_service.rs`
  - Query comments for post_id
  - Join with User to get username, avatar_url
  - Paginate with cursor (created_at based)
- [ ] T021 [US2] Add JWT middleware to comment endpoints in `src/middleware/auth.rs`
- [ ] T022 [US2] Create integration test for comment submission in `tests/integration/comment_tests.rs`
  - Create post
  - Submit comment
  - Verify appears in list immediately
  - Verify comment_count incremented

## Phase 5: User Story 3 - 删除自己的评论 (P2)

**Goal**: Users can delete own comments, post author can delete any comment on their post

**Independent Test Criteria**:
- Comment author can delete own comment
- Post author can delete any comment on their post
- Other users cannot delete
- Comment disappears immediately
- comment_count decremented
- 403 error if not authorized

### Implementation Tasks

- [ ] T023 [US3] Create DELETE `/api/v1/posts/{post_id}/comments/{comment_id}` endpoint in `src/handlers/interactions.rs`
- [ ] T024 [US3] Implement permission check in `src/services/comment_service.rs`
  - Query comment to get user_id
  - Check if requester == comment.user_id OR requester == post.user_id
  - Return 403 if not authorized
- [ ] T025 [US3] Implement comment deletion in `src/services/comment_service.rs`
  - Delete Comment record
  - Decrement post.comment_count atomically
  - Publish comment_deleted event
- [ ] T026 [US3] Create integration test for comment deletion in `tests/integration/delete_comment_tests.rs`
  - Author deletes own comment
  - Post author deletes comment
  - Non-author gets 403 error

## Phase 6: Event Publishing & Notifications

- [ ] T027 Publish like_created event in `src/events/like_events.rs`
  - Event includes post_id, post_author_id, liker_user_id
  - Published after Like record inserted
- [ ] T028 Publish like_deleted event in `src/events/like_events.rs`
  - Published after Like record deleted
- [ ] T029 Publish comment_created event in `src/events/comment_events.rs`
  - Event includes post_id, post_author_id, commenter_user_id, comment_content
- [ ] T030 Publish comment_deleted event in `src/events/comment_events.rs`
  - Published after Comment record deleted
- [ ] T031 Create event handler integration test in `tests/integration/event_tests.rs`
  - Verify events published correctly

## Phase 7: Performance & Denormalization

- [ ] T032 Create database indexes in migration `src/db/migrations/007_create_interaction_indexes.sql`
  - Index on Like (post_id, created_at) for fetching post's likes
  - Index on Comment (post_id, created_at DESC) for comment list
  - Index on Like (user_id, post_id) for uniqueness
- [ ] T033 Add denormalized like_count and comment_count update to Post in `src/services/like_service.rs`
  - Verify counts stay synchronized
- [ ] T034 Create performance test in `tests/performance/interaction_tests.rs`
  - 100 concurrent likes on same post
  - Verify like_count accuracy
  - Measure latency (target < 500ms)

## Phase 8: Edge Cases & Robustness

- [ ] T035 Handle non-existent post in like endpoint in `src/handlers/interactions.rs`
  - Return 404 if post not found
- [ ] T036 Handle deleted post in comment endpoint in `src/handlers/interactions.rs`
  - Don't allow comments on deleted posts
  - Return 404
- [ ] T037 Test is_liked flag in feed response in `tests/integration/feed_like_integration.rs`
  - Feed includes is_liked for authenticated user
  - is_liked = false for posts user hasn't liked

## Phase 9: Polish & Cross-Cutting Concerns

- [ ] T038 Add logging to all interaction endpoints in `src/handlers/interactions.rs`
  - Log user_id, post_id, action (like/comment)
- [ ] T039 Implement error response standardization in `src/handlers/interactions.rs`
  - 400: Invalid input
  - 401: Unauthorized
  - 403: Permission denied
  - 404: Not found
  - 409: Duplicate like (optional)
- [ ] T040 Document interaction APIs in `docs/api/interactions.md`
  - POST /posts/{id}/like
  - POST /posts/{id}/comments
  - GET /posts/{id}/comments
  - DELETE /posts/{id}/comments/{id}
  - Include curl examples

## Dependency Graph

```
Phase 1: Setup (tables, models)
  ↓
Phase 2: Foundational Services
  ├─ Parallel: T006-T009 (validation, service setup, events)
  ↓
Phase 3: US1 (Like System)
  ├─ Parallelizable: T010-T014 (endpoint, service, DTO)
  └─ Test gate: T015 (like integration test)
  ↓
Phase 4: US2 (Comment System)
  └─ Can start parallel with US1 after Phase 2
  ├─ Parallelizable: T016-T021 (endpoints, services)
  └─ Test gate: T022 (comment integration test)
  ↓
Phase 5: US3 (Delete Comments)
  └─ Depends on: Phase 4 (comment system exists)
  ├─ Parallelizable: T023-T026
  └─ Test gate: T026 (delete test)
  ↓
Phase 6-9: Events, Performance, Edge Cases, Polish
  └─ Depends on: US1-3 complete
```

## Parallel Execution Opportunities

**Within Phase 2**:
- T006 (validation) runs parallel with T007-T008 (atomic operations)
- T009 (events) runs parallel with all service code

**Within Phase 3-4**:
- US1 (like) and US2 (comment) are largely independent
- Can implement both in parallel after Phase 2
- T010-T014 can run parallel with T016-T021

**Within Phase 5**:
- All delete tasks (T023-T026) can start in parallel

**Within Phase 6-9**:
- Event publishing (T027-T031) can run parallel with performance/polish work
- T032-T034 (indexes) can run parallel with T035-T040

## MVP Recommendation

**Minimum Viable Product**: Phase 1-4 (Setup + US1 + US2)
- Users can like posts
- Users can comment
- Counts updated immediately
- Comments appear in list

**Estimated effort**: 100-150 engineering hours
**Timeline**: 1.5-2 weeks with 1-2 engineers

**Defer to Phase 2 (v1.1)**:
- Phase 5 (delete comments) - can add after MVP
- Phase 6 (events) - integrate with notification system later
- Phase 7-9 (performance, edge cases, polish)

## Testing Notes

**Independent Testing**:
- US1 (like) testable with just Post and User models
- US2 (comment) testable independently
- US3 (delete) testable after US2
- Events testable via mock event handlers

## Success Criteria Validation

After all tasks complete:
- ✅ SC-001: Like/unlike completes < 500ms (measured)
- ✅ SC-002: Comments appear < 1 second (UI measurement)
- ✅ SC-003: Like and comment counts accurate (database verification)
- ✅ SC-004: Duplicate likes prevented (concurrent test)
- ✅ SC-005: 99% operations succeed (error tracking)
