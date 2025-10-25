# Database Optimization Guide

## Overview

This guide identifies performance bottlenecks in the current codebase and provides optimization recommendations. These optimizations were identified during Phase 1 feature implementation.

## Critical Issues

### 1. N+1 Query Problem in User Search

**Location:** `backend/user-service/src/handlers/discover.rs:search_users()`

**Issue:**
```rust
for (id, username, display_name, bio, avatar_url, is_verified) in rows {
    // For EACH user, this query runs again!
    let is_private = sqlx::query_scalar::<_, bool>(
        "SELECT COALESCE(private_account, false) FROM users WHERE id = $1"
    )
    .bind(id)
    .fetch_optional(pool.get_ref())
    .await
    .unwrap_or(None)
    .unwrap_or(false);

    // And again for EACH direction of blocks!
    let is_blocked = user_repo::is_blocked(pool.get_ref(), requester_id, id).await.unwrap_or(false)
        || user_repo::is_blocked(pool.get_ref(), id, requester_id).await.unwrap_or(false);
}
```

**Impact:**
- Search for 20 results = 20 * 3 = 60+ database queries
- Search for 100 results = 100 * 3 = 300+ database queries
- Massive latency spike as result set grows

**Optimization:**
Fetch all required data in initial query:

```sql
SELECT
    u.id, u.username, u.display_name, u.bio, u.avatar_url, u.email_verified,
    u.private_account,
    CASE WHEN b1.id IS NOT NULL OR b2.id IS NOT NULL THEN true ELSE false END as is_blocked
FROM users u
LEFT JOIN blocks b1 ON b1.blocker_id = $1 AND b1.blocked_id = u.id
LEFT JOIN blocks b2 ON b2.blocker_id = u.id AND b2.blocked_id = $1
WHERE deleted_at IS NULL
AND (username ILIKE $2 OR display_name ILIKE $2 OR bio ILIKE $2)
ORDER BY
    CASE WHEN u.private_account THEN 1 ELSE 0 END,
    CASE WHEN username ILIKE $3 THEN 0 ELSE 1 END,
    username
LIMIT $4 OFFSET $5
```

**Expected Improvement:**
- From 60+ queries to 1 query per request
- ~95% latency reduction for search

---

### 2. Inefficient Permission Checks

**Location:** Multiple handlers (users.rs, messaging)

**Current Pattern:**
```rust
// Two separate function calls with separate DB queries
let is_blocked_1 = user_repo::is_blocked(pool, requester_id, target_id).await?;
let is_blocked_2 = user_repo::is_blocked(pool, target_id, requester_id).await?;

if is_blocked_1 || is_blocked_2 { /* reject */ }
```

**Optimization:**
Create a single query that checks both directions:

```rust
pub async fn are_blocked(pool: &PgPool, user_a: Uuid, user_b: Uuid) -> Result<bool, sqlx::Error> {
    let blocked: bool = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(
            SELECT 1 FROM blocks
            WHERE (blocker_id = $1 AND blocked_id = $2)
               OR (blocker_id = $2 AND blocked_id = $1)
        )"
    )
    .bind(user_a)
    .bind(user_b)
    .fetch_one(pool)
    .await?;

    Ok(blocked)
}
```

**Expected Improvement:**
- 50% reduction in block check queries
- Reduced database load

---

## Performance Optimizations Implemented

### 1. Database Indexes (Migration 030)

#### Full-Text Search Indexes
```sql
CREATE INDEX idx_users_username_trgm ON users USING GIN (username gin_trgm_ops);
CREATE INDEX idx_users_display_name_trgm ON users USING GIN (display_name gin_trgm_ops);
CREATE INDEX idx_users_bio_trgm ON users USING GIN (bio gin_trgm_ops);
```

**Benefits:**
- ILIKE queries now use GIN indexes instead of full table scans
- ~100x faster for large user tables (10k+ users)

#### Relationship Indexes
```sql
CREATE INDEX idx_follows_follower_id ON follows (follower_id, created_at DESC);
CREATE INDEX idx_follows_following_id ON follows (following_id, created_at DESC);
CREATE INDEX idx_follows_bidirectional ON follows (follower_id, following_id);
```

**Benefits:**
- Follower/following list queries: O(1) index lookup
- Existence checks: Single index search

#### Message Query Optimization
```sql
CREATE INDEX idx_messages_conversation_created ON messages (conversation_id, created_at DESC);
```

**Benefits:**
- Message history retrieval with pagination becomes index-only scan
- Eliminates full table scans

#### Block Indexes
```sql
CREATE INDEX idx_blocks_bidirectional ON blocks (blocker_id, blocked_id);
```

**Benefits:**
- Permission checks use single index scan
- Enables quick "is_blocked" lookups

### 2. Query Pattern Recommendations

#### Use Composite Indexes
```sql
-- ✅ Good - Uses composite index efficiently
SELECT * FROM messages
WHERE conversation_id = $1
ORDER BY created_at DESC
LIMIT 20;

-- ❌ Bad - Requires separate index on conversation_id
SELECT * FROM messages WHERE conversation_id = $1;
SELECT * FROM messages WHERE created_at > $1;
```

#### Avoid SELECT *
```sql
-- ✅ Good - Selects only needed columns
SELECT id, user_id, emoji, COUNT(*)
FROM message_reactions
WHERE message_id = $1
GROUP BY emoji;

-- ❌ Bad - Loads all columns, increases memory/network
SELECT * FROM message_reactions WHERE message_id = $1;
```

#### Batch Operations
```rust
// ✅ Good - Single batch query
let user_ids = vec![id1, id2, id3];
sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = ANY($1)")
    .bind(&user_ids)
    .fetch_all(pool)
    .await?;

// ❌ Bad - N separate queries
for user_id in user_ids {
    sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await?;
}
```

---

## Caching Strategies

### Redis Cache Layers

1. **User Profile Cache** (60s TTL)
   - Key: `nova:cache:user:{user_id}`
   - Invalidate on profile update
   - Eliminates repeated user lookups

2. **Relationship Cache** (5m TTL)
   - Key: `nova:cache:follows:{user_id}`
   - Cached follow list with last update timestamp
   - Useful for follower/following lists

3. **Search Results Cache** (30m TTL)
   - Key: `nova:cache:search:users:{query}:{limit}:{offset}`
   - Cache search results for popular queries
   - Invalidate on new user signup

4. **Conversation Member Cache** (2h TTL)
   - Key: `nova:cache:conv_members:{conversation_id}`
   - Cache group conversation member lists
   - Invalidate on member add/remove

---

## Monitoring Queries

### Identify Slow Queries

```sql
-- Enable query logging
SET log_min_duration_statement = 1000; -- Log queries > 1s

-- Check slow query log
SELECT * FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Find missing indexes
SELECT * FROM pg_stat_user_tables
WHERE seq_scan > index_scan;
```

### Check Index Usage

```sql
-- Find unused indexes
SELECT * FROM pg_stat_user_indexes
WHERE idx_scan = 0;

-- Find index size
SELECT
    schemaname, tablename, indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;
```

---

## Query Performance Targets

| Operation | Current | Target | Method |
|-----------|---------|--------|--------|
| User search (20 results) | 60+ queries | 1 query | JOIN to blocks table |
| Get followers (100 users) | Multiple queries | 1 query | Use index on following_id |
| Message history (50 msgs) | Full scan | Index scan | Composite index on (conversation_id, created_at) |
| Block check | 2 queries | 1 query | Bidirectional index + OR query |
| Profile access | 2-3 queries | 1 query | Include private_account in initial fetch |

---

## Implementation Priority

1. **Phase 1 (Immediate)** - Migration 030 Indexes
   - Already created, apply to database
   - Expected: 50-100x speedup for search

2. **Phase 2 (Next Sprint)** - Query Optimization
   - Fix N+1 queries in search and permission checks
   - Expected: 95% reduction in query count

3. **Phase 3 (Future)** - Caching Layer
   - Implement Redis caching for hot paths
   - Expected: 100-1000x speedup for cached reads

---

## References

- PostgreSQL Indexes: https://www.postgresql.org/docs/current/indexes.html
- GIN Indexes: https://www.postgresql.org/docs/current/gin-intro.html
- Query Performance: https://www.postgresql.org/docs/current/using-explain.html
