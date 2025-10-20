# Implementation Plan: 贴文互动系统（点赞与评论）

**Feature Branch**: `003-like-comment-system`
**Status**: PLANNING
**Prepared**: 2025-10-18

## Phase 0: Technical Context & Research

### Technology Stack

- **Backend**: Rust + Actix-web (async)
- **Database**: PostgreSQL with transactions
- **Concurrency**: Optimistic locking or pessimistic locking for like_count updates
- **Cache Invalidation**: Redis for cache busting
- **Events**: Event publishing for notification triggers
- **Authentication**: JWT from 001-user-auth

### Key Architecture Decisions

1. **Like Toggle Pattern**: Single endpoint that creates OR deletes Like record (idempotent)
2. **Unique Constraint Enforcement**: Database-level unique constraint on (user_id, post_id) prevents duplicates
3. **Denormalized Like Count**: Update post.like_count atomically with Like creation/deletion
4. **Comment Immutability Phase 1**: Comments not editable (only create/delete), simplifies initial design
5. **Notification Events**: Publish event to event system when like/comment created

### Critical Dependencies

- **Post Publishing System** (001): Posts must exist and be PUBLISHED
- **User Authentication** (001-user-auth): User must be authenticated
- **Notification System** (005): Like/comment events trigger notifications
- **Feed System** (002): Like/comment counts included in feed responses

### Integration Points

- **Upstream**: Post data, user auth
- **Downstream**: Notifications (005), Feed (002) - they display counts
- **Event Bus**: Publish like_created, comment_created events

## Phase 1: Data Model & API Design

### Data Model

**Like Entity**:
```
id (UUID, Primary Key)
user_id (UUID, Foreign Key)
post_id (UUID, Foreign Key)
created_at (DateTime)

Unique Constraint: (user_id, post_id)
Indexes:
  - (post_id, created_at DESC) - for showing post's likes
  - (user_id, post_id) - unique constraint
```

**Comment Entity**:
```
id (UUID, Primary Key)
post_id (UUID, Foreign Key)
user_id (UUID, Foreign Key)
content (String, max 300 chars)
created_at (DateTime)
updated_at (DateTime)

Indexes:
  - (post_id, created_at DESC) - for fetching comments
  - user_id - for user timeline queries
```

**Post Table** (enhanced):
```
like_count (Int, denormalized)
comment_count (Int, denormalized)
```

### API Contracts

**1. Toggle Like**
```
POST /api/v1/posts/{post_id}/like
Header: Authorization: Bearer {token}
Request: {} (empty)
Response (200 - Like created): {
  id: UUID,
  post_id: UUID,
  user_id: UUID,
  created_at: ISO8601,
  post_like_count: 42
}
Response (200 - Like deleted): {
  is_liked: false,
  post_like_count: 41
}
Errors:
  - 401: Unauthorized
  - 404: Post not found
  - 409: Post not published yet
```

**2. Create Comment**
```
POST /api/v1/posts/{post_id}/comments
Header: Authorization: Bearer {token}
Request: {
  content: "string, 1-300 chars"
}
Response (201): {
  id: UUID,
  post_id: UUID,
  user_id: UUID,
  content: "string",
  created_at: ISO8601,
  user: {
    id: UUID,
    username: "string",
    avatar_url: "string"
  }
}
Errors:
  - 400: Content empty or > 300 chars
  - 401: Unauthorized
  - 404: Post not found
```

**3. Get Comments**
```
GET /api/v1/posts/{post_id}/comments?limit=20&cursor={cursor}
Header: Authorization: Bearer {token}
Response (200): {
  comments: [
    {
      id: UUID,
      post_id: UUID,
      user: { id, username, avatar_url },
      content: "string",
      created_at: ISO8601,
      can_delete: Boolean (if current user or post author)
    }
  ],
  next_cursor: "base64_cursor"
}
```

**4. Delete Comment**
```
DELETE /api/v1/posts/{post_id}/comments/{comment_id}
Header: Authorization: Bearer {token}
Response (204): (empty)
Errors:
  - 403: Not authorized to delete
  - 404: Comment not found
```

## Phase 2: Implementation Strategy

### Stage 1: Like System (Week 1)

1. **Like Model & Database**
   - Define Like struct with unique constraint
   - Create migration with unique index on (user_id, post_id)
   - Set up sqlx compile-time query validation

2. **Like Toggle Endpoint**
   - Implement POST /posts/{id}/like
   - Check if Like exists
   - If exists: DELETE and decrement like_count
   - If not exists: INSERT and increment like_count
   - Return updated like_count

3. **Like Count Denormalization**
   - Update post.like_count atomically with Like record
   - Use PostgreSQL atomic update in transaction
   - Test race conditions with concurrent requests

### Stage 2: Comment System (Week 2)

1. **Comment Model & Database**
   - Define Comment struct with 300 char validation
   - Create migration with indexes
   - Implement content validation (non-empty, max length)

2. **Comment Endpoints**
   - POST /posts/{id}/comments (create)
   - GET /posts/{id}/comments (list with pagination)
   - DELETE /posts/{id}/comments/{id} (delete with permission check)

3. **Comment Count Denormalization**
   - Update post.comment_count with each create/delete
   - Atomic transaction to maintain consistency

### Stage 3: Event Publishing & Testing (Week 3)

1. **Event Publishing**
   - Define Like/Comment events
   - Publish to event bus when created
   - Event includes post_id, user_id, post_author_id

2. **Permission Checks**
   - Delete comment: only comment author or post author
   - Implement authorization middleware

3. **Integration Testing**
   - Test like toggle idempotency
   - Test comment count accuracy
   - Test permission checks
   - Test race conditions on counts
   - Load test with concurrent likes

## Constitution Check

### Data Integrity Gates

- [ ] Like uniqueness enforced at database level ✅
- [ ] Like/comment counts stay consistent ✅
- [ ] No orphaned likes/comments on post deletion ✅
- [ ] Comment content validation at API boundary ✅

### Consistency Model

- [ ] Like toggle is idempotent ✅
- [ ] Counts updated atomically ✅
- [ ] Permission checks consistent ✅

### Event Reliability

- [ ] Events published for all state changes ✅
- [ ] No lost events on failure ✅
- [ ] Events include all needed context ✅

## Artifact Output

**Generated Files**:
- `/specs/003-like-comment-system/plan.md` (this file)
- `/src/models/like.rs` - Like struct and operations
- `/src/models/comment.rs` - Comment struct and operations
- `/src/handlers/interactions.rs` - Like/comment API endpoints
- `/src/services/like_service.rs` - Like business logic
- `/src/services/comment_service.rs` - Comment business logic
- `/src/events/interaction_events.rs` - Event definitions
- `/src/db/migrations/003_create_likes_comments.sql` - Database migrations
- `/tests/integration/interaction_tests.rs` - Integration tests

**Next Phase**: Implementation execution via `/speckit.tasks`
