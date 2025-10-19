# Tasks: 用户关注系统

**Feature Branch**: `004-follow-system`
**Generated**: 2025-10-18
**Status**: Ready for Implementation
**Critical Dependency**: Must complete before 002-feed-query-system (Feed depends on follows)

## Implementation Strategy

**MVP Scope**: User Story 1 + US2 (Follow/Unfollow + Lists)
- Foundation for entire social network
- Blocks Feed system
- Estimated: 1-2 weeks

**Phase 2 Extensions**: US3-4 (Lists, Mutual following indication)
- User experience improvements
- Social discovery

## Phase 1: Setup & Infrastructure

- [ ] T001 Enhance User table migration in `src/db/migrations/008_add_follow_counts.sql`
  - Add follower_count (Int, default 0)
  - Add following_count (Int, default 0)
- [ ] T002 Create Follow table migration in `src/db/migrations/009_create_follows.sql`
  - user_id (follower), following_user_id (followed), created_at
  - Unique constraint on (user_id, following_user_id)
  - Check constraint: user_id != following_user_id
- [ ] T003 Create Follow model struct in `src/models/follow.rs`
- [ ] T004 Set up error handling in `src/errors/follow_errors.rs`
  - Self-follow error
  - Duplicate follow error
  - Already following error

## Phase 2: Foundational Services (Blocking Prerequisites)

- [ ] T005 Implement follow list query in `src/services/follow_service.rs`
  - Query all follows where user_id = target_user_id
  - Return list of following_user_ids (for Feed queries)
- [ ] T006 Create atomic follower count update in `src/services/follow_service.rs`
  - Transaction: INSERT Follow AND UPDATE User.following_count AND UPDATE User.follower_count
- [ ] T007 Implement self-follow prevention in `src/services/follow_service.rs`
  - Check user_id != following_user_id before insert
  - Return 400 error if attempted
- [ ] T008 Implement event publishing for follows in `src/events/follow_events.rs`
  - Define follow_created, follow_deleted events

## Phase 3: User Story 1 - 用户关注其他用户 (P1)

**Goal**: Users can follow others, immediate UI feedback, follow count updated

**Independent Test Criteria**:
- Follow button changes to "Unfollow" immediately
- Following user's following_count += 1
- Followed user's follower_count += 1
- Followed user appears in following list
- Page refresh shows persistent follow state

### Implementation Tasks

- [ ] T009 [US1] Create POST `/api/v1/users/{user_id}/follow` endpoint in `src/handlers/follow.rs`
  - Toggle follow (create if not exists)
  - Returns updated follow status and counts
- [ ] T010 [US1] Implement follow creation in `src/services/follow_service.rs`
  - Validate target user exists
  - Check self-follow prevention
  - Insert Follow record
  - Update follower_count and following_count atomically
- [ ] T011 [US1] Create FollowResponse DTO in `src/models/follow.rs`
  - is_following: bool
  - target_user: { id, username, follower_count, following_count }
- [ ] T012 [US1] Add JWT middleware to follow endpoint in `src/middleware/auth.rs`
- [ ] T013 [US1] Handle user not found error in `src/handlers/follow.rs`
  - Return 404 if target user doesn't exist
- [ ] T014 [US1] Create integration test for follow in `tests/integration/follow_tests.rs`
  - User A follows User B
  - Verify is_following = true
  - Verify counts incremented
  - Verify persistent after page reload

## Phase 4: User Story 2 - 用户取消关注 (P1)

**Goal**: Users can unfollow, counts decreased, user disappears from feed

**Independent Test Criteria**:
- Unfollow button changes to "Follow"
- Following user's following_count -= 1
- Unfollowed user's follower_count -= 1
- User's posts disappear from Feed
- Counts accurate after unfollow

### Implementation Tasks

- [ ] T015 [US2] Create DELETE `/api/v1/users/{user_id}/follow` endpoint in `src/handlers/follow.rs`
- [ ] T016 [US2] Implement follow deletion in `src/services/follow_service.rs`
  - Delete Follow record
  - Update counts atomically (decrement both)
  - Publish follow_deleted event
- [ ] T017 [US2] Handle not following error in `src/handlers/follow.rs`
  - Return 404 if not currently following
- [ ] T018 [US2] Create integration test for unfollow in `tests/integration/unfollow_tests.rs`
  - Follow then unfollow
  - Verify is_following = false
  - Verify counts decremented

## Phase 5: User Story 3 - 查看粉丝和关注列表 (P1)

**Goal**: Users can view paginated follower and following lists with quick follow/unfollow

**Independent Test Criteria**:
- Followers list shows correct users
- Following list shows correct users
- Lists paginated (20 per page default)
- Each item shows is_following and is_followed_by
- Can follow/unfollow from list directly

### Implementation Tasks

- [ ] T019 [US3] Create GET `/api/v1/users/{user_id}/followers` endpoint in `src/handlers/follow.rs`
  - Paginated with limit (default 20, max 100), cursor
  - Returns list of users
- [ ] T020 [US3] Implement followers list query in `src/services/follow_service.rs`
  - Query follows where following_user_id = target_user_id
  - Join with User to get user data
  - Include is_following and is_followed_by flags
- [ ] T021 [US3] Create GET `/api/v1/users/{user_id}/following` endpoint in `src/handlers/follow.rs`
  - Same structure as followers endpoint
- [ ] T022 [US3] Implement following list query in `src/services/follow_service.rs`
  - Query follows where user_id = target_user_id
- [ ] T023 [US3] Create UserInListResponse DTO in `src/models/follow.rs`
  - id, username, avatar_url, bio, follower_count
  - is_following, is_followed_by
- [ ] T024 [US3] Implement cursor pagination for follow lists in `src/services/pagination.rs`
  - Use (follow_date, user_id) for stable pagination
- [ ] T025 [US3] Create integration test for follower list in `tests/integration/follower_list_tests.rs`
  - Create multiple followers
  - Verify list order and pagination

## Phase 6: User Story 4 - 查看某用户是否已关注我 (P2)

**Goal**: Show "Following Me" badge on user profiles when viewing someone who follows you

**Independent Test Criteria**:
- User B's profile shows "Following Me" when B follows A
- Badge disappears after B unfollows A
- Badge only appears for person viewing, not shown to B viewing own profile

### Implementation Tasks

- [ ] T026 [US4] Add is_followed_by flag to user profile response in `src/handlers/users.rs`
  - Check if target_user_id follows authenticated_user_id
- [ ] T027 [US4] Implement is_followed_by check in `src/services/follow_service.rs`
  - Query Follow where user_id = target AND following_user_id = authenticated
- [ ] T028 [US4] Update UserProfileResponse to include is_followed_by in `src/models/user.rs`
- [ ] T029 [US4] Create integration test for is_followed_by in `tests/integration/follow_badge_tests.rs`

## Phase 7: Performance & Denormalization

- [ ] T030 Create database indexes in `src/db/migrations/010_create_follow_indexes.sql`
  - Index on Follow (user_id, created_at DESC)
  - Index on Follow (following_user_id, created_at DESC)
  - Index on User (follower_count, following_count) for trending
- [ ] T031 Verify denormalized counts stay synchronized in `src/services/follow_service.rs`
  - Add consistency checks
- [ ] T032 Create performance test in `tests/performance/follow_tests.rs`
  - User with 100k followers
  - Verify list query < 500ms

## Phase 8: Edge Cases & Robustness

- [ ] T033 Handle rapid follow/unfollow in `src/services/follow_service.rs`
  - Use pessimistic or optimistic locking
  - Ensure final state matches last action
- [ ] T034 Test cascade deletion when user account deleted in `tests/integration/cascade_tests.rs`
  - Delete user should remove all follows
- [ ] T035 Handle deleted users in follow lists in `src/services/follow_service.rs`
  - Don't show deleted users in follower/following lists

## Phase 9: Event Publishing & Integration

- [ ] T036 Publish follow_created event in `src/events/follow_events.rs`
  - Event includes follower_user_id, followed_user_id
- [ ] T037 Publish follow_deleted event in `src/events/follow_events.rs`
  - Published after Follow record deleted
- [ ] T038 Create event handler integration test in `tests/integration/follow_events_tests.rs`

## Phase 10: Polish & Cross-Cutting Concerns

- [ ] T039 Add logging to all follow endpoints in `src/handlers/follow.rs`
  - Log follower and followed user IDs
- [ ] T040 Implement error response standardization in `src/handlers/follow.rs`
  - 400: Self-follow or already following
  - 401: Unauthorized
  - 404: User not found
- [ ] T041 Document follow APIs in `docs/api/follow.md`
  - POST /users/{id}/follow
  - DELETE /users/{id}/follow
  - GET /users/{id}/followers
  - GET /users/{id}/following
  - Include curl examples

## Dependency Graph

```
Phase 1-2: Setup + Foundational
  ↓
Phase 3: US1 (Follow)
  ├─ Parallelizable: T009-T013
  └─ Test gate: T014
  ↓
Phase 4: US2 (Unfollow)
  └─ Can parallel with US1 after Phase 2
  └─ Test gate: T018
  ↓
Phase 5: US3 (Lists)
  └─ Depends on: US1 and US2 (follow/unfollow logic exists)
  ├─ Parallelizable: T019-T024
  └─ Test gate: T025
  ↓
Phase 6: US4 (Followed By Badge)
  └─ Can parallel with US3
  └─ Test gate: T029
  ↓
Phase 7-10: Performance, Edge Cases, Events, Polish
  └─ Depends on: US1-4 complete
```

## Parallel Execution Opportunities

**Within Phase 3-4**:
- US1 (follow) and US2 (unfollow) can start in parallel after Phase 2
- T009-T013 can run parallel with T015-T017

**Within Phase 5-6**:
- Follower list (T019-T025) can run parallel with following list
- US4 (followed_by badge) can run parallel with US3

**Within Phase 7-10**:
- Indexes (T030-T032) can run parallel with edge cases
- Event publishing can run parallel with polish work

## MVP Recommendation

**Minimum Viable Product**: Phase 1-4 (Setup + US1 + US2)
- Users can follow/unfollow
- Counts accurate
- Foundation for Feed system

**Estimated effort**: 80-120 engineering hours
**Timeline**: 1-2 weeks with 1-2 engineers

**Defer to Phase 2 (v1.1)**:
- Phase 5 (follower lists) - UI refinement
- Phase 6 (followed_by badge) - nice-to-have
- Phase 7-10 (performance, edge cases, events)

## Critical Path Note

**BLOCKING DEPENDENCY**: Feed system (002) requires follow relationships.
Recommend implementing 004 Follow System BEFORE or IN PARALLEL with 002 Feed.

## Testing Notes

**Independent Testing**:
- US1 testable with just 2 users
- US2 testable independently
- US3 lists testable after US1/US2
- Events testable via mock handlers

## Success Criteria Validation

After all tasks complete:
- ✅ SC-001: Follow < 200ms (measured)
- ✅ SC-002: Counts consistent (database verification)
- ✅ SC-003: Lists load < 500ms with 100k followers (query profiling)
- ✅ SC-004: Counts appear immediately in profile (API response check)
- ✅ SC-005: 99% succeed (error tracking)
