# Phase 1 Implementation Guide - Database Migration Cleanup

## 🎯 Overview

Four database migrations (065-068) have been created and committed to implement the Phase 1 quick-win fixes identified in the architecture review. These migrations address 4 critical high-impact issues.

**Status**: ✅ Database migrations created and committed
**Next Phase**: Code updates (Phase 2)
**Estimated Duration**: 2-3 days (after database testing)

---

## 📋 Phase 1 Migrations (COMPLETED)

### Migration 065: Merge post_metadata and social_metadata
- **Files**: `backend/migrations/065_merge_post_metadata_tables.sql`
- **Impact**: Posts, Post Metadata, Social Graph
- **Changes**:
  - Add `like_count`, `comment_count`, `view_count`, `share_count` to `posts` table
  - Create backward compatibility view `post_metadata`
  - Update triggers to maintain counters from `posts` table
  - Add indexes on counter columns

### Migration 066: Unify soft_delete → deleted_at
- **Files**: `backend/migrations/066_unify_soft_delete_naming.sql`
- **Impact**: Posts, Comments, Conversations, Messages
- **Changes**:
  - Rename `posts.soft_delete` → `posts.deleted_at`
  - Rename `comments.soft_delete` → `comments.deleted_at`
  - Add `conversations.deleted_at` column
  - Create helper views: `active_posts`, `active_comments`, `active_messages`, `active_conversations`
  - Create legacy compatibility views for old column names

### Migration 067: Fix messages.sender_id CASCADE
- **Files**: `backend/migrations/067_fix_messages_cascade.sql`
- **Impact**: Messages, Users
- **Changes**:
  - Add `ON DELETE CASCADE` to `messages.sender_id` foreign key
  - Create cascade delete trigger for soft-deleted users
  - Add performance indexes for cascade operations
  - Create orphaned message detection view

### Migration 068: Add encryption versioning
- **Files**: `backend/migrations/068_add_message_encryption_versioning.sql`
- **Impact**: Messages, Encryption
- **Changes**:
  - Add `encryption_algorithm` column (default: `AES-GCM-256`)
  - Add `encryption_key_version` column (default: `1`)
  - Create key rotation helper functions
  - Create encryption status monitoring view
  - Add audit log table for encryption operations

---

## 🔧 Phase 2: Rust Code Updates (IN PROGRESS)

### 2.1 Content Service - Post Metadata Queries

**File**: `backend/content-service/src/db/post_repo.rs`

**Current Code Pattern**:
```rust
// Joins post_metadata table
LEFT JOIN post_metadata pm ON p.id = pm.post_id
```

**Changes Needed**:
```rust
// Access counters directly from posts table
-- No JOIN needed, counters are in posts table

// Update get_post_metadata() function:
// Current: SELECT like_count, comment_count FROM post_metadata WHERE post_id = ?
// New:     SELECT like_count, comment_count FROM posts WHERE id = ?

// Update update_post_metadata() function:
// Current: UPDATE post_metadata SET like_count = ?
// New:     UPDATE posts SET like_count = ?
```

**Affected Functions**:
- `get_post_with_metadata(post_id)` - Refactor to use posts table directly
- `get_post_metadata(post_id)` - Simplify query
- `update_post_metadata()` - Update to use posts table
- `increment_post_views()` - Update column name
- `increment_post_comments()` - Update column name
- `increment_post_likes()` - Update column name

**Estimated Effort**: 2-3 hours

---

### 2.2 Feed Service - Post Metadata Queries

**File**: `backend/feed-service/src/services/recommendation_v2/mod.rs`

**Current Code Pattern**:
```rust
JOIN post_metadata pm ON pm.post_id = p.id
```

**Changes Needed**:
```rust
// Remove JOIN, use posts columns directly
// SELECT p.like_count, p.comment_count FROM posts p
```

**File**: `backend/feed-service/src/services/trending/service.rs`

**Current Code Pattern**:
```rust
async fn get_post_metadata(&self, post_id: Uuid) -> Result<Option<(String, String, String)>> {
    // Queries post_metadata table
}
```

**Changes Needed**:
```rust
// Update to query posts table directly
async fn get_post_metadata(&self, post_id: Uuid) -> Result<Option<(String, String, String)>> {
    // SELECT like_count, comment_count, view_count FROM posts WHERE id = ?
}
```

**Estimated Effort**: 1-2 hours

---

### 2.3 Test Fixtures - post_metadata Updates

**Files**:
- `backend/tests/fixtures/mod.rs`
- `backend/tests/integration/posts_test.rs`
- `backend/user-service/tests/common/fixtures.rs`
- `backend/user-service/tests/posts_test.rs`

**Current Code Pattern**:
```rust
pub async fn update_post_metadata(
    pool: &PgPool,
    post_id: Uuid,
    like_count: i32,
    comment_count: i32,
    view_count: i32,
) -> Result<()> {
    sqlx::query("UPDATE post_metadata SET like_count = ? WHERE post_id = ?")
        .bind(like_count)
        .bind(post_id)
        .execute(pool)
        .await?;
    // ... etc
}
```

**Changes Needed**:
```rust
// Update to target posts table instead
pub async fn update_post_metadata(
    pool: &PgPool,
    post_id: Uuid,
    like_count: i32,
    comment_count: i32,
    view_count: i32,
) -> Result<()> {
    sqlx::query("UPDATE posts SET like_count = ?, comment_count = ?, view_count = ? WHERE id = ?")
        .bind(like_count)
        .bind(comment_count)
        .bind(view_count)
        .bind(post_id)
        .execute(pool)
        .await?;
    Ok(())
}
```

**Estimated Effort**: 1-2 hours

---

### 2.4 Soft Delete Unification (soft_delete → deleted_at)

**Files to Search**:
```bash
grep -r "soft_delete" backend --include="*.rs"
```

**Pattern 1: Direct column references**
```rust
// Current
WHERE posts.soft_delete IS NULL

// New
WHERE posts.deleted_at IS NULL
```

**Pattern 2: Column updates**
```rust
// Current
UPDATE posts SET soft_delete = NOW()

// New
UPDATE posts SET deleted_at = NOW()
```

**Pattern 3: Schema definitions** (if using SQLx compile-time checking)
```rust
// Check sqlx::query!() compile-time queries
// These may need migration helper views or code updates
```

**Affected Services**:
- ✅ content-service - Post soft deletes
- ✅ messaging-service - Message/conversation soft deletes
- ✅ user-service - User operations
- ✅ feed-service - Feed queries filtering soft-deleted posts

**Migration Strategy**:
1. Create database views for backward compatibility (done in migration)
2. Update Rust code to use `deleted_at` column name
3. Remove dependency on legacy column names
4. Run integration tests

**Estimated Effort**: 3-4 hours (due to high number of references)

---

### 2.5 Message Encryption Versioning

**Files to Update**:
- `backend/messaging-service/src/` (encryption handlers)
- `backend/libs/nova-messaging/` (encryption utilities)

**Current Code Pattern**:
```rust
pub struct EncryptedMessage {
    encrypted_content: String,
    nonce: String,
    // No algorithm or key version tracking
}
```

**Changes Needed**:
```rust
pub struct EncryptedMessage {
    encrypted_content: String,
    nonce: String,
    encryption_algorithm: String,  // e.g., "AES-GCM-256"
    encryption_key_version: i32,   // e.g., 1, 2, 3...
}
```

**Implementation Tasks**:
1. Update `EncryptedMessage` struct to include algorithm and key_version
2. Update message encryption handler to set these fields
3. Update message decryption handler to read these fields
4. Create key rotation function
5. Add monitoring/observability for encryption versions

**Estimated Effort**: 3-4 hours

---

## 📊 Phase 2 Summary

| Task | Files | Effort | Risk |
|------|-------|--------|------|
| Remove post_metadata JOINs | content-service, feed-service | 3h | Low |
| Update test fixtures | tests/ | 2h | Low |
| Unify soft_delete naming | All services | 4h | Medium |
| Add encryption versioning | messaging-service | 4h | Medium |
| **Total** | **30+ files** | **~13 hours** | **Medium** |

---

## 🚀 Phase 2 Implementation Checklist

### Pre-Implementation
- [ ] Review all affected files
- [ ] Set up local test database
- [ ] Create feature branch for Phase 2
- [ ] Document any custom table access patterns not covered by this guide

### Post_metadata → posts migration
- [ ] Update content-service post queries
- [ ] Update feed-service post queries
- [ ] Update test fixtures
- [ ] Run `cargo test` for content-service and feed-service
- [ ] Verify migration runs without errors

### soft_delete → deleted_at unification
- [ ] Global find/replace with verification
- [ ] Update all query builders
- [ ] Update migrations filter logic
- [ ] Run integration tests
- [ ] Verify views work for backward compatibility

### Encryption versioning implementation
- [ ] Update EncryptedMessage struct
- [ ] Update encryption handlers
- [ ] Update decryption handlers
- [ ] Add key rotation logic
- [ ] Add monitoring queries
- [ ] Run messaging-service tests

### Final Validation
- [ ] `cargo check --all` - No compilation errors
- [ ] `cargo clippy --all` - No warnings
- [ ] `cargo test` - All tests passing
- [ ] Integration tests in staging environment
- [ ] Performance benchmark (ensure no regressions)

---

## 📝 Notes

1. **Backward Compatibility**: Migrations 065 and 066 create database views to support legacy queries. This allows phased code updates.

2. **Testing Strategy**:
   - Unit tests: Can run locally without database
   - Integration tests: Require Phase 1 migrations to be applied
   - Set `SQLX_OFFLINE=true` if database isn't available for compile-time checks

3. **Rollback Plan**: If issues arise during Phase 2:
   - Database state can be rolled back using SQLx migrations rollback
   - Code can be reverted to main branch
   - Views provide backward compatibility layer

4. **Performance Impact**:
   - ✅ post_metadata merge: **Improves** performance (eliminates 1:1 JOIN)
   - ✅ soft_delete unification: Neutral (same indexed column)
   - ✅ message CASCADE: Neutral (adds constraint, not query change)
   - ✅ encryption versioning: Minimal (adds columns, indexed for key rotation)

5. **Key Rotation Process** (for future reference):
   ```sql
   -- 1. Get messages with old key
   SELECT * FROM messages WHERE encryption_key_version = 1;

   -- 2. Re-encrypt with new key (application layer)

   -- 3. Update key version
   UPDATE messages SET encryption_key_version = 2 WHERE id = ?;

   -- 4. Monitor status
   SELECT * FROM message_encryption_status;
   ```

---

## 🔗 Related Documents

- `ARCHITECTURE_REVIEW.md` - Full analysis of all 10 issues
- `ARCHITECTURE_REVIEW_SUMMARY.md` - Executive summary
- Migration files: `backend/migrations/065-068_*.sql`
