# Tasks: 首页动态 Feed 显示系统

**Feature Branch**: `002-feed-query-system`
**Generated**: 2025-10-18
**Status**: Ready for Implementation
**Blocking Requirement**: 001-post-publish-system must be complete (provides Post table and data)

## Implementation Strategy

**MVP Scope**: User Story 1 (Feed Loading) only
- Enables users to see posts from followed users
- Foundation for all downstream systems
- Estimated: 1-2 weeks

**Phase 2 Extensions**: US2-3 (Pagination, Refresh)
- Large feed optimization
- User experience improvements

## Phase 1: Setup & Infrastructure

- [ ] T001 Create Follow table migration in `src/db/migrations/003_create_follows.sql` (prerequisite for feed queries)
- [ ] T002 Create Follow model struct in `src/models/follow.rs`
- [ ] T003 Set up database query helpers for feed in `src/db/queries/feed.sql`
- [ ] T004 Create error handling for feed service in `src/errors/feed_errors.rs`

## Phase 2: Foundational Services (Blocking Prerequisites)

- [ ] T005 Implement follow list query in `src/services/follow_service.rs`
  - Query all follows where user_id = authenticated_user_id
  - Return list of following_user_ids
  - Handle empty follow list
- [ ] T006 Create cursor pagination helper in `src/services/pagination.rs`
  - Encode (post_id, created_at) as cursor
  - Decode cursor for next query
  - Generate next_cursor for response
- [ ] T007 Implement user data joining in `src/db/queries/feed.sql`
  - JOIN Post with User to get username, avatar_url
  - Include post metadata (like_count, comment_count)
- [ ] T008 Create denormalized like_count check in `src/services/feed_service.rs`
  - LEFT JOIN Like records to compute is_liked flag
  - Include in feed response

## Phase 3: User Story 1 - 查看关注者贴文 (P1)

**Goal**: Authenticated user sees posts from followed users, sorted newest first

**Independent Test Criteria**:
- User A follows User B and C
- Posts from B and C appear in A's feed
- Posts sorted by created_at DESC (newest first)
- User D's posts don't appear (not followed)
- Feed returns 20 posts by default
- Response includes like_count, comment_count, is_liked flag

### Implementation Tasks

- [ ] T009 [US1] Create GET `/api/v1/feed` endpoint in `src/handlers/feed.rs`
  - Accepts limit (default 20, max 100)
  - Returns array of posts with user data
  - Includes pagination token (next_cursor)
- [ ] T010 [US1] Implement FeedResponse DTO in `src/models/feed.rs`
  - posts: Array of PostFeedItem
  - next_cursor: Optional string
- [ ] T011 [US1] Create PostFeedItem DTO in `src/models/feed.rs`
  - id, user {id, username, avatar_url}, image_url, thumbnail_url
  - caption, created_at, like_count, comment_count, is_liked
- [ ] T012 [US1] Implement feed query logic in `src/services/feed_service.rs`
  - Get authenticated user's followed user IDs
  - Query posts where user_id IN (followed_ids) AND status = PUBLISHED
  - Order by created_at DESC
  - Limit to requested limit (20 default)
- [ ] T013 [US1] Add JWT middleware to GET `/api/v1/feed` in `src/middleware/auth.rs`
- [ ] T014 [US1] Handle empty follow list gracefully in `src/services/feed_service.rs`
  - Return empty posts array
  - No error, just empty result
- [ ] T015 [US1] Create integration test for feed loading in `tests/integration/feed_tests.rs`
  - Create 3 users (A, B, C)
  - A follows B and C
  - Create posts from B and C
  - Verify feed shows both posts, sorted correctly

## Phase 4: User Story 2 - Feed 分页加载 (P1)

**Goal**: Pagination allows loading large feeds without timeout, 20 posts per page default

**Independent Test Criteria**:
- First request returns 20 posts + next_cursor
- Second request with cursor returns next 20 posts
- No duplicate posts across pages
- No gaps in posts
- Final page has no next_cursor
- Cursor is stable even during concurrent follow/unfollow

### Implementation Tasks

- [ ] T016 [US2] Implement cursor-based pagination in `src/services/pagination.rs`
  - Encode cursor: base64(post_id + created_at)
  - Decode cursor: extract post_id and created_at
  - Generate next_cursor: post_id and created_at of last post in page
- [ ] T017 [US2] Update feed query to support cursor in `src/services/feed_service.rs`
  - If cursor provided: query where (created_at, post_id) < (cursor_time, cursor_id)
  - Uses composite comparison for stable pagination
- [ ] T018 [US2] Add limit query parameter validation in `src/handlers/feed.rs`
  - Accept limit 1-100, default 20
  - Return 400 if invalid
- [ ] T019 [US2] Create pagination test in `tests/integration/pagination_tests.rs`
  - Create 100 posts
  - Load first page (20 posts)
  - Load second page with cursor
  - Verify 40 posts total, no duplicates, no gaps

## Phase 5: User Story 3 - 下拉刷新最新内容 (P2)

**Goal**: Users can refresh to see newest posts without reloading app

**Independent Test Criteria**:
- Refresh request with timestamp parameter
- Returns posts newer than timestamp
- New posts appear at top of feed
- Existing posts still visible below

### Implementation Tasks

- [ ] T020 [US3] Add refresh parameter to GET `/api/v1/feed` in `src/handlers/feed.rs`
  - Optional refresh_since_at (ISO8601 timestamp)
  - If provided: query posts created_at > refresh_since_at
- [ ] T021 [US3] Implement refresh logic in `src/services/feed_service.rs`
  - If refresh_since_at provided: prepend new posts to existing feed
  - Return combined array (newest first)
- [ ] T022 [US3] Create refresh test in `tests/integration/refresh_tests.rs`
  - Create initial feed
  - Create new posts
  - Call refresh endpoint
  - Verify new posts appear

## Phase 6: Edge Cases & Robustness

- [ ] T023 Handle deleted users gracefully in `src/services/feed_service.rs`
  - Query should exclude posts from deleted users
  - Deleted user = is_deleted = true in User table
- [ ] T024 Handle deleted posts in `src/services/feed_service.rs`
  - Only show posts where status = PUBLISHED
  - Deleted posts already excluded by status check
- [ ] T025 [P] Test concurrent follow/unfollow during feed query in `tests/integration/concurrency_tests.rs`
  - User A unfollows B during feed pagination
  - Verify results are consistent
- [ ] T026 Create empty feed test in `tests/integration/edge_case_tests.rs`
  - User follows no one
  - Feed returns empty array with no error

## Phase 7: Performance & Optimization

- [ ] T027 Create database index on (user_id, created_at DESC) in migration `src/db/migrations/004_create_feed_indexes.sql`
- [ ] T028 Add EXPLAIN ANALYZE to feed query in `src/db/queries/feed.sql`
  - Verify index usage
  - Target: < 500ms for 50 posts
- [ ] T029 Create performance test in `tests/performance/feed_load_tests.rs`
  - Simulate user with 50 followed users
  - Each with 100 posts
  - Measure query time
  - Target: < 500ms

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T030 Add logging to feed endpoints in `src/handlers/feed.rs`
  - Log user_id, limit, cursor, response size
- [ ] T031 Implement error response standardization in `src/handlers/feed.rs`
  - 400: Invalid parameters
  - 401: Unauthorized
  - 500: Internal error
- [ ] T032 Document feed API in `docs/api/feed.md`
  - GET /feed endpoint
  - Response format
  - Pagination examples
  - Curl examples

## Dependency Graph

```
Phase 1: Setup
  ↓
Phase 2: Foundational Services (blocking all user stories)
  ↓
Phase 3: US1 (Feed Loading)
  └─ Depends on: Phase 2, 001-post-publish-system
  ├─ Parallelizable: T009-T014 (endpoint code)
  └─ Test gate: T015 (integration test)
  ↓
Phase 4: US2 (Pagination)
  └─ Depends on: US1 (feed endpoint exists)
  ├─ Parallelizable: T016-T018
  └─ Test gate: T019 (pagination test)
  ↓
Phase 5: US3 (Refresh)
  └─ Depends on: US1 (feed endpoint exists)
  └─ Can proceed parallel with US2
  └─ Test gate: T022 (refresh test)
  ↓
Phase 6-8: Edge cases, Performance, Polish
  └─ Depends on: US1, US2, US3 complete
```

## Parallel Execution Opportunities

**Within Phase 2 (Foundational)**:
- T005 (follow query) can run parallel with T006 (pagination helper)
- T007 (user joining) can run parallel with T008 (is_liked flag)

**Within Phase 3 (US1)**:
- T009, T010, T011 can start in parallel (DTOs and endpoints)
- T012-T014 can start after T009 (depend on endpoint structure)

**Within Phase 4-5 (US2-3)**:
- US2 (pagination) and US3 (refresh) are independent
- Can implement both in parallel after US1

**Within Phase 6-8**:
- T023-T026 (edge cases) can start after Phase 3
- T027-T029 (performance) can run in parallel with T030-T032

## MVP Recommendation

**Minimum Viable Product**: Complete Phase 1-3 (Setup + US1)
- Users see posts from followed users
- Basic feed loading works
- Foundation for other systems

**Estimated effort**: 80-120 engineering hours
**Timeline**: 1-2 weeks with 1-2 engineers

**Defer to Phase 2 (v1.1)**:
- Phase 4 (pagination) - can add after MVP validates concept
- Phase 5 (refresh) - nice-to-have, can poll instead
- Phase 6-8 (edge cases, perf) - optimize after MVP working

## Testing Notes

**Independent Testing Strategy**:
- US1 can be tested with just 3 users and basic posts
- US2 pagination can be tested independently with 100 posts
- US3 refresh can be tested independently with timestamp simulation
- Edge cases tested separately per scenario

## Success Criteria Validation

After all tasks complete:
- ✅ SC-001: Feed loads < 1 second (measured with query profiling)
- ✅ SC-002: Pagination returns 40 posts total across 2 pages (no duplicates verified in tests)
- ✅ SC-003: New posts appear in feed within 5 seconds (timestamp checked)
- ✅ SC-004: System handles 10k concurrent queries (load test)
- ✅ SC-005: 99% query success rate (error tracking)
