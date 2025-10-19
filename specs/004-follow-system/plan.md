# Implementation Plan: 用户关注系统

**Feature Branch**: `004-follow-system`
**Status**: PLANNING
**Prepared**: 2025-10-18

## Phase 0: Technical Context & Research

### Technology Stack

- **Backend**: Rust + Actix-web
- **Database**: PostgreSQL with atomic counter updates
- **Event System**: Event publishing for follow notifications
- **Caching**: Redis for follower/following count caching
- **Authentication**: JWT

### Key Architecture Decisions

1. **Denormalized Counts**: Store follower_count and following_count on User table, updated atomically
2. **No Self-follow Constraint**: Database-level check prevents user from following themselves
3. **Mutual Follows Allowed**: No requirement to auto-reciprocate follows
4. **Event Publishing**: Follow events trigger notifications
5. **Cascade Deletion**: Account deletion removes all follows automatically

### Critical Dependencies

- **User System**: User table with denormalized counts
- **Notification System** (005): Follow events trigger notifications
- **Feed System** (002): Depends on follow relationships
- **User Search** (006): Can directly follow from search results

## Phase 1: Data Model & API Design

### Data Model

**Follow Entity**:
```
id (UUID, Primary Key)
user_id (UUID, Foreign Key → User, the follower)
following_user_id (UUID, Foreign Key → User, the person being followed)
created_at (DateTime)

Unique Constraint: (user_id, following_user_id)
Check Constraint: user_id ≠ following_user_id (no self-follow)
Indexes:
  - (user_id, created_at DESC) - for following list
  - (following_user_id, created_at DESC) - for followers list
```

**User Table** (enhanced):
```
follower_count (Int, default 0)
following_count (Int, default 0)
```

### API Contracts

**1. Follow User**
```
POST /api/v1/users/{user_id}/follow
Header: Authorization: Bearer {token}
Request: {} (empty)
Response (200): {
  is_following: true,
  user: { id, username, follower_count, following_count }
}
Errors:
  - 400: Attempting to follow self
  - 401: Unauthorized
  - 404: User not found
```

**2. Unfollow User**
```
DELETE /api/v1/users/{user_id}/follow
Header: Authorization: Bearer {token}
Response (204): (empty)
Errors:
  - 401: Unauthorized
  - 404: User not found
```

**3. Get Followers List**
```
GET /api/v1/users/{user_id}/followers?limit=20&cursor={cursor}
Header: Authorization: Bearer {token}
Response (200): {
  users: [
    {
      id: UUID, username, avatar_url,
      is_following: Boolean,
      is_followed_by: Boolean
    }
  ],
  next_cursor: "base64_cursor"
}
```

**4. Get Following List**
```
GET /api/v1/users/{user_id}/following?limit=20&cursor={cursor}
Header: Authorization: Bearer {token}
Response (200): {
  users: [ {...same format...} ],
  next_cursor: "base64_cursor"
}
```

## Phase 2: Implementation Strategy

### Stage 1: Follow Toggle (Week 1)

1. **Follow Model**
   - Define Follow struct
   - Create migration with unique constraint and self-follow check
   - Set up relationship queries

2. **Follow Endpoint**
   - POST /users/{id}/follow (create Follow record)
   - Increment following_count for user, follower_count for target
   - Use transaction for atomicity

3. **Unfollow Endpoint**
   - DELETE /users/{id}/follow (remove Follow record)
   - Decrement counts atomically

### Stage 2: Follower/Following Lists (Week 2)

1. **List Queries**
   - Implement followers list with pagination
   - Implement following list with pagination
   - Include is_following and is_followed_by flags

2. **Performance**
   - Use cursor pagination (created_at based)
   - Create proper indexes
   - Test with large follower counts (100k+)

### Stage 3: Integration (Week 3)

1. **Event Publishing**
   - Publish follow_created events
   - Trigger notifications via event system

2. **Cascade Deletion**
   - When user deletes account, remove all follows
   - Update counts for affected users

3. **Testing**
   - Test follow/unfollow toggle
   - Test count accuracy
   - Test list pagination
   - Test concurrent operations

## Constitution Check

- [ ] Follow uniqueness enforced at database ✅
- [ ] Counts updated atomically ✅
- [ ] Self-follow prevented ✅
- [ ] No orphaned records on deletion ✅

## Artifact Output

**Generated Files**:
- `/specs/004-follow-system/plan.md` (this file)
- `/src/models/follow.rs` - Follow model
- `/src/handlers/follow.rs` - API endpoints
- `/src/services/follow_service.rs` - Follow logic
- `/src/db/migrations/004_create_follows.sql` - Migration
- `/tests/integration/follow_tests.rs` - Tests

**Next Phase**: Implementation execution via `/speckit.tasks`
