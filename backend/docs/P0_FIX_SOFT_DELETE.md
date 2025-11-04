# P0 Fix #2: Unified Soft-Delete Pattern (GDPR Compliance)

## Problem

**Issue**: Inconsistent soft-delete patterns across tables
- Some tables have `deleted_at`, some don't
- Some have `deleted_by`, some don't
- No audit trail for GDPR "Right to Be Forgotten"
- Queries sometimes filter by `deleted_at`, sometimes don't
- Risk of accidental data exposure in queries

**Current State**:
```sql
-- Posts table: has deleted_at ✓
SELECT * FROM posts WHERE user_id = $1;  -- Missing: AND deleted_at IS NULL ❌

-- Comments table: NO soft-delete columns ❌
DELETE FROM comments WHERE post_id = $1;  -- Hard delete, no audit trail ❌

-- Messages: has deleted_at but not deleted_by ❌
```

**Compliance Risk**: GDPR Article 17 requires audit trail for data deletion requests

---

## Solution

**Migration 070**: Unified soft-delete across ALL tables

### Schema Changes

| Table | Before | After | Trigger | Outbox Event |
|-------|--------|-------|---------|--------------|
| users | deleted_at, deleted_by | ✓ | ✓ | UserDeleted |
| posts | deleted_at | deleted_at, deleted_by | ✓ | PostDeleted |
| comments | ❌ | deleted_at, deleted_by | ✓ | CommentDeleted |
| messages | deleted_at | deleted_at, deleted_by | ✓ | MessageDeleted |
| follows | ❌ | deleted_at, deleted_by | ✓ | FollowDeleted |
| blocks | ❌ | deleted_at, deleted_by | ✓ | BlockDeleted |
| media | ❌ | deleted_at, deleted_by | ✓ | MediaDeleted |

### Outbox Pattern Integration

```sql
-- When post is deleted:
UPDATE posts SET deleted_at = NOW(), deleted_by = $1 WHERE id = $2;

-- Trigger automatically creates event:
INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
VALUES ('Post', $2, 'PostDeleted', {...});

-- Kafka consumer processes:
// Feed service: remove from user's feed
// Search service: remove from index
// Analytics service: record deletion timestamp
```

---

## Implementation

**File**: `/backend/migrations/070_unify_soft_delete_complete.sql`

**Includes**:
1. Add `deleted_at, deleted_by` columns to 7 tables
2. Add CHECK constraints (both columns must be NULL or both NOT NULL)
3. Create PL/pgSQL triggers for Outbox events
4. Fix FK constraints (RESTRICT instead of CASCADE)
5. Create convenience views (`active_posts`, `active_comments`, etc.)
6. Add indexes for deleted/active queries
7. Comprehensive documentation

---

## Application Code Changes

### Before:
```rust
// ❌ Inconsistent - doesn't filter soft-deleted posts
pub async fn get_user_posts(user_id: UserId) -> Result<Vec<Post>> {
    sqlx::query_as::<_, Post>(
        "SELECT * FROM posts WHERE user_id = $1"
    )
    .bind(user_id.0)
    .fetch_all(&pool)
    .await
}
```

### After:
```rust
// ✅ Explicit soft-delete filtering
pub async fn get_user_posts(user_id: UserId) -> Result<Vec<Post>> {
    sqlx::query_as::<_, Post>(
        "SELECT * FROM posts WHERE user_id = $1 AND deleted_at IS NULL"
    )
    .bind(user_id.0)
    .fetch_all(&pool)
    .await
}

// OR use the convenience view:
pub async fn get_user_posts(user_id: UserId) -> Result<Vec<Post>> {
    sqlx::query_as::<_, Post>(
        "SELECT * FROM active_posts WHERE user_id = $1"
    )
    .bind(user_id.0)
    .fetch_all(&pool)
    .await
}
```

---

## Deletion Flow (GDPR Compliant)

```
User: "Delete my account"
  ↓
auth-service::delete_user()
  ↓
BEGIN TRANSACTION:
  UPDATE users SET deleted_at = NOW(), deleted_by = user_id WHERE id = $1;
  -- Triggers: emit_user_deletion_event()
  --   INSERT INTO outbox_events (..., event_type='UserDeleted', ...)
COMMIT
  ↓
Outbox consumer polls:
  SELECT * FROM outbox_events WHERE published_at IS NULL;
  ↓
For each event:
  - messaging-service: soft-delete user's messages
  - content-service: soft-delete user's posts
  - search-service: remove from index
  - feed-service: remove from feeds
  - [UPDATE outbox_events SET published_at = NOW()]
  ↓
Kafka topic: user-events
  Event: {"type": "UserDeleted", "user_id": "...", "deleted_at": "..."}
```

**Audit Trail**:
```sql
SELECT * FROM users WHERE id = $1;
-- Returns: deleted_at='2025-11-04T12:30:00Z', deleted_by='legal-dept'

SELECT * FROM posts WHERE deleted_by IS NOT NULL ORDER BY deleted_at DESC;
-- All deleted posts with deletion timestamp and who deleted them
```

---

## Testing

### Unit Tests

```rust
#[tokio::test]
async fn test_soft_delete_creates_outbox_event() {
    // Delete post
    sqlx::query("UPDATE posts SET deleted_at = NOW(), deleted_by = $1 WHERE id = $2")
        .bind(user_id)
        .bind(post_id)
        .execute(&pool)
        .await
        .unwrap();

    // Verify outbox event created
    let events: Vec<OutboxEvent> = sqlx::query_as(
        "SELECT * FROM outbox_events WHERE aggregate_id = $1 AND event_type = 'PostDeleted'"
    )
    .bind(post_id)
    .fetch_all(&pool)
    .await
    .unwrap();

    assert_eq!(events.len(), 1);
    assert_eq!(events[0].event_type, "PostDeleted");
}

#[tokio::test]
async fn test_active_posts_view_filters_deleted() {
    // Create post, then delete it
    sqlx::query("INSERT INTO posts (id, user_id) VALUES ($1, $2)")
        .execute(&pool)
        .await
        .unwrap();

    sqlx::query("UPDATE posts SET deleted_at = NOW(), deleted_by = $1 WHERE id = $2")
        .execute(&pool)
        .await
        .unwrap();

    // Query active_posts view
    let posts: Vec<Post> = sqlx::query_as("SELECT * FROM active_posts WHERE id = $1")
        .fetch_all(&pool)
        .await
        .unwrap();

    assert!(posts.is_empty());  // Deleted post should not appear
}

#[tokio::test]
async fn test_foreign_key_restrict_prevents_hard_delete() {
    // Create post
    sqlx::query("INSERT INTO posts (id, user_id) VALUES ($1, $2)")
        .execute(&pool)
        .await
        .unwrap();

    // Try to delete user (should fail with FK error)
    let result = sqlx::query("DELETE FROM users WHERE id = $1")
        .execute(&pool)
        .await;

    assert!(result.is_err());  // FK constraint violated
    assert!(result.unwrap_err().to_string().contains("foreign key"));
}
```

---

## Rollout Plan

### Phase 1: Migration (Week 1)
- [ ] Apply migration 070 to staging
- [ ] Verify all tables have deleted_at, deleted_by
- [ ] Verify outbox events created for deletions
- [ ] Run soft-delete queries on all tables

### Phase 2: Application Code Updates (Week 2-3)
Services to update:
- [ ] **content-service**: Add `AND deleted_at IS NULL` to all post/comment queries
- [ ] **user-service**: Add soft-delete filters to follower queries
- [ ] **messaging-service**: Add soft-delete filters to message queries
- [ ] **search-service**: Update indexing to skip deleted items
- [ ] **feed-service**: Update ranking to skip deleted posts

### Phase 3: Outbox Consumer Implementation (Week 3-4)
- [ ] Implement outbox consumer service (separate service or library)
- [ ] Subscribe to Outbox events from PostgreSQL
- [ ] Publish to Kafka topics
- [ ] Update published_at timestamp
- [ ] Implement retry logic with exponential backoff

### Phase 4: Verification (Week 4)
- [ ] Load test deletion flow
- [ ] Verify Kafka events published
- [ ] Verify cascade deletions (via Outbox)
- [ ] Test GDPR audit trail queries

---

## Verification Queries

```sql
-- GDPR Audit Trail
SELECT id, deleted_at, deleted_by FROM users WHERE deleted_at IS NOT NULL
ORDER BY deleted_at DESC LIMIT 10;

-- Find all deleted posts (for GDPR data export)
SELECT * FROM posts WHERE user_id = $1 AND deleted_at IS NOT NULL;

-- Verify Outbox events created
SELECT aggregate_type, COUNT(*) FROM outbox_events
WHERE published_at IS NULL GROUP BY aggregate_type;

-- Monitor Outbox backlog
SELECT COUNT(*) as unpublished_events FROM outbox_events
WHERE published_at IS NULL AND retry_count < 3;
```

---

## Status

- **Created**: 2025-11-04
- **Priority**: P0
- **Affects**: All services
- **Estimated Effort**: 2-3 weeks
- **Impact**: GDPR compliance, data consistency, audit trail
