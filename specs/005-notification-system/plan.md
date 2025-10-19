# Implementation Plan: 通知系统

**Feature Branch**: `005-notification-system`
**Status**: PLANNING
**Prepared**: 2025-10-18

## Phase 0: Technical Context & Research

### Technology Stack

- **Backend**: Rust + Actix-web
- **Database**: PostgreSQL
- **Event System**: Event sourcing pattern with event handlers
- **Push Notifications**: Firebase Cloud Messaging (FCM) for mobile
- **Queue**: Redis for notification delivery queue
- **Caching**: Redis for unread count
- **Authentication**: JWT

### Key Architecture Decisions

1. **Event-Driven Architecture**: Like/Comment/Follow events trigger notification creation
2. **Notification Aggregation**: Multiple actions within 5 minutes from same user are grouped
3. **Idempotent Creation**: Prevent duplicate notifications using event_id deduplication
4. **Push Notification Support**: Optional FCM integration with user preferences
5. **Read Status Tracking**: Boolean flag on notification for read/unread
6. **Unread Count Denormalization**: Cache unread_count on User for fast access

### Critical Dependencies

- **Like/Comment System** (003): Publishes like/comment events
- **Follow System** (004): Publishes follow events
- **User System**: For notification delivery and preferences
- **Event Bus**: For subscribing to system events

## Phase 1: Data Model & API Design

### Data Model

**Notification Entity**:
```
id (UUID, Primary Key)
user_id (UUID, Foreign Key → User, recipient)
notification_type (Enum: LIKE, COMMENT, FOLLOW)
actor_user_id (UUID, Foreign Key → User)
target_user_id (UUID, Foreign Key → User, optional)
resource_id (UUID, post_id or comment_id)
message (String)
is_read (Boolean, default false)
created_at (DateTime)

Indexes:
  - (user_id, is_read, created_at DESC) - for notification list
  - (actor_user_id, target_user_id, notification_type, created_at) - for deduplication check
```

**NotificationPreference Entity**:
```
user_id (UUID, Foreign Key, Primary Key)
push_notifications_enabled (Boolean, default true)
email_notifications_enabled (Boolean, default false)
notification_frequency (Enum: REAL_TIME, DAILY, WEEKLY)
muted_users (Array<UUID>, optional)
```

**User Table** (enhanced):
```
unread_notification_count (Int, default 0, denormalized)
```

### API Contracts

**1. Get Notifications**
```
GET /api/v1/notifications?limit=20&cursor={cursor}&unread_only=false
Header: Authorization: Bearer {token}
Response (200): {
  notifications: [
    {
      id: UUID,
      notification_type: "LIKE" | "COMMENT" | "FOLLOW",
      actor: { id, username, avatar_url },
      message: "string",
      resource_link: "/posts/{id}" or similar,
      is_read: Boolean,
      created_at: ISO8601
    }
  ],
  unread_count: 5,
  next_cursor: "base64_cursor"
}
```

**2. Mark Notification as Read**
```
PATCH /api/v1/notifications/{notification_id}
Header: Authorization: Bearer {token}
Request: { is_read: true }
Response (200): { is_read: true, updated_at: ISO8601 }
```

**3. Mark All as Read**
```
PATCH /api/v1/notifications
Header: Authorization: Bearer {token}
Request: { is_read: true, all: true }
Response (200): { marked_count: 42 }
```

**4. Get Notification Preferences**
```
GET /api/v1/notifications/preferences
Header: Authorization: Bearer {token}
Response (200): {
  push_notifications_enabled: Boolean,
  email_notifications_enabled: Boolean,
  notification_frequency: "REAL_TIME" | "DAILY" | "WEEKLY"
}
```

## Phase 2: Implementation Strategy

### Stage 1: Notification Creation (Week 1)

1. **Event Handlers**
   - Subscribe to like_created events
   - Subscribe to comment_created events
   - Subscribe to follow_created events
   - Create Notification record on each event

2. **Deduplication**
   - Check for existing notification of same type
   - Within 5-minute window from same actor
   - Aggregate by creating compound notification message

3. **User Notification Filtering**
   - Check NotificationPreference
   - Respect muted_users list
   - Filter by notification_type preferences

### Stage 2: Notification Retrieval & Management (Week 2)

1. **Notification List**
   - GET /notifications endpoint
   - Paginate by created_at DESC
   - Include actor user data
   - Calculate is_read status

2. **Mark as Read**
   - PATCH endpoint for single notification
   - Bulk PATCH for marking all as read
   - Update unread_count cache

3. **Unread Count**
   - Maintain denormalized unread_count on User
   - Update atomically with notification creation/read
   - Cache in Redis for fast access

### Stage 3: Push & Preferences (Week 3)

1. **Push Notifications**
   - Firebase Cloud Messaging integration (optional for Phase 1)
   - Store FCM device tokens
   - Send push on notification creation
   - Respect user preferences

2. **Notification Preferences**
   - Implement preference endpoints
   - Store in database
   - Apply during notification creation

3. **Testing**
   - Test aggregation logic
   - Test deduplication
   - Test concurrent creates
   - Test notification cleanup on post/follow deletion

## Constitution Check

- [ ] No duplicate notifications ✅
- [ ] Aggregation reduces noise ✅
- [ ] Read status tracked accurately ✅
- [ ] Cleanup on resource deletion ✅
- [ ] Event-driven architecture ✅

## Artifact Output

**Generated Files**:
- `/specs/005-notification-system/plan.md` (this file)
- `/src/models/notification.rs` - Notification model
- `/src/models/notification_preference.rs` - Preference model
- `/src/handlers/notifications.rs` - API endpoints
- `/src/services/notification_service.rs` - Notification logic
- `/src/events/notification_handlers.rs` - Event handlers
- `/src/db/migrations/005_create_notifications.sql` - Migration
- `/tests/integration/notification_tests.rs` - Tests

**Next Phase**: Implementation execution via `/speckit.tasks`
