# Tasks: 通知系统

**Feature Branch**: `005-notification-system`
**Generated**: 2025-10-18
**Status**: Ready for Implementation
**Dependencies**: 003-like-comment-system (like/comment events), 004-follow-system (follow events)

## Implementation Strategy

**MVP Scope**: User Story 1 + US2 + US3 (Like/Comment/Follow notifications + Basic retrieval)
- Core engagement driver
- Triggered by existing events from systems 003-004
- Estimated: 1-2 weeks

**Phase 2 Extensions**: US4-5 (Read status, mark all, preferences)
- User preference management
- Notification lifecycle management

## Phase 1: Setup & Infrastructure

- [ ] T001 Create Notification table migration in `src/db/migrations/011_create_notifications.sql`
  - id, user_id, notification_type (enum), actor_user_id, target_user_id, resource_id
  - message, is_read, created_at, updated_at
- [ ] T002 Create NotificationPreference table migration in `src/db/migrations/012_create_notification_preferences.sql`
  - user_id, push_enabled, email_enabled, notification_frequency
- [ ] T003 Create Notification model struct in `src/models/notification.rs`
- [ ] T004 Create NotificationPreference model struct in `src/models/notification_preference.rs`
- [ ] T005 Set up error handling in `src/errors/notification_errors.rs`
- [ ] T006 Create event subscription system in `src/events/notification_subscriber.rs`
  - Subscribe to like_created, comment_created, follow_created events

## Phase 2: Foundational Services (Blocking Prerequisites)

- [ ] T007 Create event listener setup in `src/services/notification_service.rs`
  - Listen for Like, Comment, Follow events
  - Create Notification records
- [ ] T008 Implement notification aggregation in `src/services/notification_service.rs`
  - Check for existing notification within 5 minutes
  - Same actor, same post (for likes/comments)
  - Update message instead of creating new notification
- [ ] T009 Create deduplication check in `src/services/notification_service.rs`
  - Prevent duplicate notifications via event_id tracking
  - Idempotent notification creation
- [ ] T010 Implement event handlers registration in `src/main.rs`
  - Register like_created → notification creation handler
  - Register comment_created → notification creation handler
  - Register follow_created → notification creation handler

## Phase 3: User Story 1 - 收到点赞通知 (P1)

**Goal**: When post is liked, post author receives notification with actor info

**Independent Test Criteria**:
- Like event triggers notification creation
- Notification shows liker username and avatar
- Notification marked as unread by default
- Notification appears in notification list
- Notification links to post

### Implementation Tasks

- [ ] T011 [US1] Create like_created event handler in `src/events/like_notifications.rs`
  - On like_created event: create Notification
  - Type = LIKE, actor = liker, target = post author
- [ ] T012 [US1] Implement like notification creation in `src/services/notification_service.rs`
  - Create Notification record
  - Query post.user_id (who to notify)
  - Message: "{actor_username} liked your post"
- [ ] T013 [US1] Create integration test for like notification in `tests/integration/like_notification_tests.rs`
  - Create post by User A
  - User B likes post
  - Verify notification created for A
  - Verify is_read = false

## Phase 4: User Story 2 - 收到评论通知 (P1)

**Goal**: When post is commented, post author receives notification with comment preview

**Independent Test Criteria**:
- Comment event triggers notification
- Notification shows commenter and comment text (first 50 chars)
- Notification links to post with comment highlighted
- Post author can click to view full comment

### Implementation Tasks

- [ ] T014 [US2] Create comment_created event handler in `src/events/comment_notifications.rs`
  - On comment_created: create Notification
- [ ] T015 [US2] Implement comment notification creation in `src/services/notification_service.rs`
  - Message: "{commenter_name} commented: {content_preview}"
  - content_preview = first 50 chars of comment
- [ ] T016 [US2] Create integration test for comment notification in `tests/integration/comment_notification_tests.rs`
  - Create post, comment on it
  - Verify notification created
  - Verify message has preview

## Phase 5: User Story 3 - 收到关注通知 (P1)

**Goal**: When receiving follow, user gets notification with follower profile

**Independent Test Criteria**:
- Follow event triggers notification
- Notification shows follower name and avatar
- Can follow back directly from notification

### Implementation Tasks

- [ ] T017 [US3] Create follow_created event handler in `src/events/follow_notifications.rs`
- [ ] T018 [US3] Implement follow notification creation in `src/services/notification_service.rs`
  - Message: "{follower_name} followed you"
  - Include follower avatar and profile link
- [ ] T019 [US3] Create integration test for follow notification in `tests/integration/follow_notification_tests.rs`

## Phase 6: User Story 4 - 标记通知为已读 (P2)

**Goal**: Users can mark notifications as read, unread count updated

**Independent Test Criteria**:
- Mark single notification as read changes is_read = true
- Mark all as read sets all is_read = true
- Unread count decremented
- Read notifications appear dimmed in UI

### Implementation Tasks

- [ ] T020 [US4] Create PATCH `/api/v1/notifications/{id}` endpoint in `src/handlers/notifications.rs`
  - Body: { is_read: true }
- [ ] T021 [US4] Implement mark as read in `src/services/notification_service.rs`
  - Update notification.is_read = true
  - Decrement user.unread_notification_count atomically
- [ ] T022 [US4] Create PATCH `/api/v1/notifications` endpoint in `src/handlers/notifications.rs`
  - Mark all notifications as read
- [ ] T023 [US4] Implement mark all as read in `src/services/notification_service.rs`
  - Update all notifications for user where is_read = false
  - Set user.unread_notification_count = 0
- [ ] T024 [US4] Create integration test for mark as read in `tests/integration/mark_read_tests.rs`

## Phase 7: User Story 5 - 通知中心分页加载 (P2)

**Goal**: Notification center shows paginated history, sortable by recency

**Independent Test Criteria**:
- First load returns 20 most recent notifications
- Pagination cursor returns next 20
- No duplicates across pages
- Oldest notifications beyond 30 days not included

### Implementation Tasks

- [ ] T025 [US5] Create GET `/api/v1/notifications` endpoint in `src/handlers/notifications.rs`
  - Pagination with limit (default 20, max 100), cursor
  - Optional unread_only flag
- [ ] T026 [US5] Implement notification list query in `src/services/notification_service.rs`
  - Query notifications where user_id = authenticated_user_id
  - Order by created_at DESC
  - Cursor pagination using (created_at, notification_id)
- [ ] T027 [US5] Create NotificationListResponse DTO in `src/models/notification.rs`
  - notifications: Array of NotificationItem
  - unread_count: Int
  - next_cursor: Optional string
- [ ] T028 [US5] Create NotificationItem DTO in `src/models/notification.rs`
  - id, type, actor {id, username, avatar_url}, message, resource_link
  - is_read, created_at
- [ ] T029 [US5] Create integration test for notification list in `tests/integration/notification_list_tests.rs`

## Phase 8: Notification Aggregation & Deduplication

- [ ] T030 Implement aggregation logic in `src/services/notification_service.rs`
  - Check for existing notification within 5 minutes
  - Same type, same actor, same post
  - Update message to reflect count: "X liked your 3 posts"
- [ ] T031 Create aggregation test in `tests/integration/aggregation_tests.rs`
  - User B likes 3 posts from User A within 5 minutes
  - Verify single aggregated notification created
  - Verify message shows count

## Phase 9: Unread Count Denormalization

- [ ] T032 Enhance User table with unread_notification_count in `src/db/migrations/013_add_unread_count.sql`
  - Add unread_notification_count (Int, default 0)
- [ ] T033 Implement unread count update in `src/services/notification_service.rs`
  - Increment on notification creation
  - Decrement on mark as read
  - Atomically update
- [ ] T034 Create endpoint to get unread count in `src/handlers/notifications.rs`
  - GET `/api/v1/notifications/unread-count`
  - Returns { unread_count: Int }

## Phase 10: Notification Preferences

- [ ] T035 [P] Create GET `/api/v1/notifications/preferences` endpoint in `src/handlers/notifications.rs`
- [ ] T035B [P] Create PUT `/api/v1/notifications/preferences` endpoint in `src/handlers/notifications.rs`
  - Body: { push_enabled, email_enabled, notification_frequency }
- [ ] T036 Implement preference retrieval in `src/services/notification_service.rs`
- [ ] T037 Implement preference update in `src/services/notification_service.rs`
  - Validate frequency enum (REAL_TIME, DAILY, WEEKLY)

## Phase 11: Push Notifications (Optional for MVP)

- [ ] T038 Create push notification structure in `src/services/push_service.rs`
  - Firebase Cloud Messaging integration (optional)
- [ ] T039 Store FCM device tokens in database (optional phase)
- [ ] T040 Send push notification on notification creation (optional phase)

## Phase 12: Cleanup & Cascading Deletion

- [ ] T041 Implement cleanup when post deleted in `src/services/post_service.rs`
  - Delete all notifications referencing post_id
- [ ] T042 Implement cleanup when follow deleted in `src/services/follow_service.rs`
  - Delete follow notifications
- [ ] T043 Create cleanup integration test in `tests/integration/cleanup_tests.rs`

## Phase 13: Performance & Monitoring

- [ ] T044 Create database indexes in `src/db/migrations/014_create_notification_indexes.sql`
  - Index on (user_id, is_read, created_at DESC)
  - Index on created_at for cleanup queries
- [ ] T045 Create performance test in `tests/performance/notification_tests.rs`
  - User receives 1000 notifications
  - List query < 200ms
  - Mark all as read < 100ms
- [ ] T046 Add logging to notification endpoints in `src/handlers/notifications.rs`

## Phase 14: Polish & Documentation

- [ ] T047 Implement error response standardization in `src/handlers/notifications.rs`
- [ ] T048 Document notification APIs in `docs/api/notifications.md`
  - GET /notifications
  - PATCH /notifications/{id}
  - PATCH /notifications (mark all)
  - GET /notifications/preferences
  - PUT /notifications/preferences

## Dependency Graph

```
Phase 1-2: Setup + Foundational Event Listeners
  ↓
Phase 3-5: US1-3 (Like/Comment/Follow notifications)
  ├─ Parallelizable: Each event handler independent
  ├─ T011-T019 can run in parallel
  └─ Test gates: T013, T016, T019
  ↓
Phase 6: US4 (Mark as read)
  └─ Depends on: Notification creation (Phase 3-5)
  └─ Parallelizable: T020-T023
  └─ Test gate: T024
  ↓
Phase 7: US5 (Pagination)
  └─ Can parallel with Phase 6
  └─ Parallelizable: T025-T029
  ↓
Phase 8-14: Aggregation, Dedup, Preferences, Push, Cleanup, Performance, Polish
  └─ Depends on: Core notification creation working
```

## Parallel Execution Opportunities

**Within Phase 3-5**:
- Like notification handler (T011-T013) can run parallel with comment and follow handlers
- All three event handlers (T011, T014, T017) are independent

**Within Phase 6-7**:
- Mark as read (T020-T024) can run parallel with pagination (T025-T029)

**Within Phase 8-10**:
- Aggregation (T030-T031) can run parallel with denormalization (T032-T034)
- Preferences (T035-T037) can run in parallel

**Within Phase 11-14**:
- Push notifications can run parallel with cleanup
- Performance optimization can run parallel with documentation

## MVP Recommendation

**Minimum Viable Product**: Phase 1-7 (Setup + US1-5)
- Users receive like/comment/follow notifications
- Can view notification list
- Can mark as read
- Unread count tracks

**Estimated effort**: 120-160 engineering hours
**Timeline**: 1.5-2 weeks with 1-2 engineers

**Defer to Phase 2 (v1.1)**:
- Phase 8-9 (aggregation, denormalization) - optimization
- Phase 10 (preferences) - user control
- Phase 11 (push) - mobile integration
- Phase 12-14 (cleanup, performance, docs)

## Critical Dependencies

Requires completion of:
- 003-like-comment-system (like/comment events)
- 004-follow-system (follow events)

Can proceed in parallel with 002-feed-query-system

## Testing Notes

**Independent Testing**:
- Each event handler testable independently
- Like notification testable without comment/follow system
- List/pagination testable independently
- Mark as read testable independently

## Success Criteria Validation

After all tasks complete:
- ✅ SC-001: Notifications created < 2s (event handler timing)
- ✅ SC-002: List loads < 200ms (query profiling)
- ✅ SC-003: Mark as read < 100ms (database timing)
- ✅ SC-004: Aggregation reduces count 50%+ (count comparison)
- ✅ SC-005: 99% no duplicates (dedup verification)
