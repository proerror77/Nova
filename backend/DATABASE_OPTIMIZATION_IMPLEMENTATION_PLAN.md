# Database Optimization Implementation Plan

## Overview
This plan outlines the step-by-step implementation of database optimizations identified in the performance audit. Organized by priority to maximize impact while minimizing risk.

---

## Phase 1: Critical Fixes (Week 1) - Zero Downtime

### Goal
Fix the most critical performance bottlenecks that cause exponential slowdown.

### Migrations to Run

#### 1.1 PostgreSQL Optimizations
```bash
# Run the P0 migration
psql $DATABASE_URL < migrations/060_performance_optimization_p0.sql
```

**What it does:**
- Adds `sequence_number` column to messages (eliminates COUNT query)
- Denormalizes conversations table (eliminates subqueries)
- Adds full-text search column `content_tsv` to messages
- Creates composite indexes for common query patterns

**Rollback plan:**
```sql
-- If needed (low risk, additive changes only)
ALTER TABLE messages DROP COLUMN IF EXISTS sequence_number;
ALTER TABLE messages DROP COLUMN IF EXISTS content_tsv;
ALTER TABLE conversations DROP COLUMN IF EXISTS last_sequence_number;
ALTER TABLE conversations DROP COLUMN IF EXISTS member_count;
ALTER TABLE conversations DROP COLUMN IF EXISTS last_message_id;
ALTER TABLE conversations DROP COLUMN IF EXISTS last_message_at;
DROP TRIGGER IF EXISTS set_message_sequence ON messages;
DROP TRIGGER IF EXISTS update_member_count_on_add ON conversation_members;
DROP TRIGGER IF EXISTS update_member_count_on_remove ON conversation_members;
DROP TRIGGER IF EXISTS update_last_message_on_insert ON messages;
```

**Expected impact:**
- Message send operations: **100-1000x faster**
- Conversation queries: **3-5x faster**
- Message search: **100-1000x faster**

#### 1.2 ClickHouse Feed Tables
```bash
# Run on ClickHouse server
clickhouse-client --multiquery < clickhouse/002_feed_candidates_tables.sql
```

**What it does:**
- Creates `feed_candidates_followees` table
- Creates `feed_candidates_trending` table
- Creates `feed_candidates_affinity` table
- Materializes `user_author_90d` and `post_metrics_1h` views
- Adds time-based partitioning to all CDC tables

**Rollback plan:**
```sql
-- Drop new tables
DROP TABLE IF EXISTS feed_candidates_followees;
DROP TABLE IF EXISTS feed_candidates_trending;
DROP TABLE IF EXISTS feed_candidates_affinity;
DROP TABLE IF EXISTS user_author_90d_mv;
DROP TABLE IF EXISTS post_metrics_1h_mv;

-- Restore old tables from backups
-- (Backup tables created automatically by migration)
```

**Expected impact:**
- Feed generation: **10-100x faster**
- Trending queries: **Instant** (pre-computed)
- Data cleanup: **Instant** (partition drops)

### Code Changes Required

#### 1.3 Update Message Service
**File:** `backend/messaging-service/src/services/message_service.rs`

```rust
// OLD CODE (lines 85-90)
let seq: i64 = sqlx::query_scalar(
    "SELECT COUNT(*)::bigint FROM messages WHERE conversation_id = $1"
)
.bind(conversation_id)
.fetch_one(db)
.await?;

// NEW CODE (replace with)
// sequence_number is now assigned by trigger, just fetch it
let result = sqlx::query(
    "SELECT id, sequence_number FROM messages WHERE id = $1"
)
.bind(id)
.fetch_one(db)
.await?;

let seq: i64 = result.get("sequence_number");
```

**File:** `backend/messaging-service/src/services/conversation_service.rs`

```rust
// OLD CODE (lines 99-114) - subqueries
let r = sqlx::query(
    r#"
    SELECT
      $1::uuid AS id,
      (
        SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = $1
      ) AS member_count,
      (
        SELECT m.id FROM messages m WHERE m.conversation_id = $1 ORDER BY m.created_at DESC LIMIT 1
      ) AS last_message_id
    "#
).fetch_one(db).await?;

// NEW CODE (replace with)
let r = sqlx::query(
    "SELECT id, member_count, last_message_id FROM conversations WHERE id = $1"
).bind(id).fetch_one(db).await?;
```

#### 1.4 Testing Plan

**Unit Tests:**
```bash
cd backend/messaging-service
cargo test services::message_service::tests
cargo test services::conversation_service::tests
```

**Integration Tests:**
```bash
# Test message send performance
curl -X POST http://localhost:8003/api/v1/messages \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "conversation_id": "uuid",
    "content": "test message"
  }'

# Should complete in <50ms (was ~200ms before)

# Test conversation fetch
curl http://localhost:8003/api/v1/conversations/uuid \
  -H "Authorization: Bearer $TOKEN"

# Should complete in <30ms (was ~100ms before)
```

**Load Test:**
```bash
# Send 1000 messages to a conversation with 10,000 existing messages
# Before: ~200ms per message
# After: ~20ms per message
```

---

## Phase 2: Query Optimizations (Week 2)

### Goal
Optimize existing queries to eliminate N+1 patterns and use better SQL patterns.

### Code Changes

#### 2.1 Optimize Message History Query
**File:** `backend/messaging-service/src/services/message_service.rs`

Replace `get_message_history_with_details` function:

```rust
pub async fn get_message_history_with_details(
    db: &Pool<Postgres>,
    _encryption: &EncryptionService,
    conversation_id: Uuid,
    user_id: Uuid,
    limit: i64,
    offset: i64,
    include_recalled: bool,
) -> Result<Vec<MessageDto>, AppError> {
    let limit = limit.min(200);
    let privacy_mode = Self::fetch_conversation_privacy(db, conversation_id).await?;
    let use_encryption = matches!(privacy_mode, PrivacyMode::StrictE2e);

    let where_recalled = if include_recalled {
        ""
    } else {
        "AND m.recalled_at IS NULL"
    };

    // SINGLE QUERY with JSON aggregation
    let query_sql = format!(
        r#"
        SELECT
            m.id,
            m.sender_id,
            m.sequence_number,
            m.created_at,
            m.recalled_at,
            m.updated_at,
            m.version_number,
            m.content,
            m.content_encrypted,
            m.content_nonce,
            m.message_type,

            -- Aggregate reactions
            COALESCE(
                json_agg(
                    DISTINCT jsonb_build_object(
                        'emoji', r.emoji,
                        'count', r.reaction_count,
                        'user_reacted', r.user_reacted
                    )
                ) FILTER (WHERE r.emoji IS NOT NULL),
                '[]'::json
            ) as reactions_json,

            -- Aggregate attachments
            COALESCE(
                json_agg(
                    DISTINCT jsonb_build_object(
                        'id', a.id,
                        'file_name', a.file_name,
                        'file_type', a.file_type,
                        'file_size', a.file_size,
                        's3_key', a.s3_key
                    )
                ) FILTER (WHERE a.id IS NOT NULL),
                '[]'::json
            ) as attachments_json
        FROM messages m
        LEFT JOIN LATERAL (
            SELECT
                emoji,
                COUNT(*) as reaction_count,
                BOOL_OR(user_id = $2) as user_reacted
            FROM message_reactions
            WHERE message_id = m.id
            GROUP BY emoji
        ) r ON true
        LEFT JOIN message_attachments a ON a.message_id = m.id
        WHERE m.conversation_id = $1
          AND m.deleted_at IS NULL
          {}
        GROUP BY
            m.id, m.sender_id, m.sequence_number, m.created_at, m.recalled_at,
            m.updated_at, m.version_number, m.content,
            m.content_encrypted, m.content_nonce, m.message_type
        ORDER BY m.created_at ASC
        LIMIT $3 OFFSET $4
        "#,
        where_recalled
    );

    let rows = sqlx::query(&query_sql)
        .bind(conversation_id)
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await
        .map_err(|e| AppError::StartServer(format!("fetch messages: {e}")))?;

    let result = rows
        .into_iter()
        .map(|r| {
            let id: Uuid = r.get("id");
            let sender_id: Uuid = r.get("sender_id");
            let seq: i64 = r.get("sequence_number");
            let created_at: DateTime<Utc> = r.get("created_at");
            let recalled_at: Option<DateTime<Utc>> = r.get("recalled_at");
            let updated_at: Option<DateTime<Utc>> = r.get("updated_at");
            let version_number: i32 = r.get("version_number");
            let message_type: Option<String> = r.get("message_type");

            // Parse reactions from JSON
            let reactions_json: serde_json::Value = r.get("reactions_json");
            let reactions: Vec<MessageReaction> = serde_json::from_value(reactions_json)
                .unwrap_or_default();

            // Parse attachments from JSON
            let attachments_json: serde_json::Value = r.get("attachments_json");
            let attachments: Vec<MessageAttachment> = serde_json::from_value(attachments_json)
                .unwrap_or_default();

            if use_encryption {
                let ciphertext: Option<Vec<u8>> = r.get("content_encrypted");
                let nonce: Option<Vec<u8>> = r.get("content_nonce");
                MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content: String::new(),
                    encrypted: true,
                    encrypted_payload: ciphertext.as_ref().map(|c| general_purpose::STANDARD.encode(c)),
                    nonce: nonce.as_ref().map(|n| general_purpose::STANDARD.encode(n)),
                    recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                    updated_at: updated_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type,
                    reactions,
                    attachments,
                }
            } else {
                let content: String = r.get("content");
                MessageDto {
                    id,
                    sender_id,
                    sequence_number: seq,
                    created_at: created_at.to_rfc3339(),
                    content,
                    encrypted: false,
                    encrypted_payload: None,
                    nonce: None,
                    recalled_at: recalled_at.map(|t| t.to_rfc3339()),
                    updated_at: updated_at.map(|t| t.to_rfc3339()),
                    version_number,
                    message_type,
                    reactions,
                    attachments,
                }
            }
        })
        .collect();

    Ok(result)
}
```

**Expected improvement:** 2-4x faster (3 queries → 1 query)

#### 2.2 Optimize Feed Candidate Queries
**File:** `backend/content-service/src/services/feed_ranking.rs`

Replace `get_feed_candidates` method:

```rust
pub async fn get_feed_candidates(
    &self,
    user_id: Uuid,
    limit: usize,
) -> Result<Vec<FeedCandidate>> {
    #[derive(clickhouse::Row, serde::Deserialize)]
    struct CandidateRow {
        source: String,
        post_id: String,
        author_id: String,
        likes: u32,
        comments: u32,
        shares: u32,
        impressions: u32,
        freshness_score: f64,
        engagement_score: f64,
        affinity_score: f64,
        combined_score: f64,
        created_at: DateTime<Utc>,
    }

    // SINGLE UNION ALL QUERY instead of 3 separate queries
    let query = r#"
        SELECT
            'followees' as source,
            post_id, author_id, likes, comments, shares, impressions,
            freshness_score, engagement_score, affinity_score, combined_score, created_at
        FROM feed_candidates_followees
        WHERE user_id = ?
        ORDER BY combined_score DESC
        LIMIT ?

        UNION ALL

        SELECT
            'trending' as source,
            post_id, author_id, likes, comments, shares, impressions,
            freshness_score, engagement_score, affinity_score, combined_score, created_at
        FROM feed_candidates_trending
        ORDER BY combined_score DESC
        LIMIT ?

        UNION ALL

        SELECT
            'affinity' as source,
            post_id, author_id, likes, comments, shares, impressions,
            freshness_score, engagement_score, affinity_score, combined_score, created_at
        FROM feed_candidates_affinity
        WHERE user_id = ?
        ORDER BY affinity_score DESC
        LIMIT ?
    "#;

    let rows = self
        .ch_client
        .query_with_params::<CandidateRow, _>(query, |stmt| {
            stmt.bind(user_id)
                .bind(limit as u64)
                .bind(limit as u64)
                .bind(user_id)
                .bind(limit as u64)
        })
        .await?;

    Ok(rows
        .into_iter()
        .map(|row| FeedCandidate {
            post_id: row.post_id,
            author_id: row.author_id,
            likes: row.likes,
            comments: row.comments,
            shares: row.shares,
            impressions: row.impressions,
            freshness_score: row.freshness_score,
            engagement_score: row.engagement_score,
            affinity_score: row.affinity_score,
            combined_score: row.combined_score,
            created_at: row.created_at,
        })
        .collect())
}
```

**Expected improvement:** 1.5-2x faster (3 network round trips → 1)

---

## Phase 3: Cursor Pagination (Week 3)

### Goal
Replace LIMIT OFFSET with cursor-based pagination for efficient deep pagination.

### Code Changes

#### 3.1 Add Cursor Pagination to Posts
**File:** `backend/content-service/src/db/post_repo.rs`

Add new function:

```rust
/// Cursor-based pagination for posts (efficient for deep pagination)
pub async fn find_posts_by_user_cursor(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    cursor_created_at: Option<DateTime<Utc>>,
    cursor_id: Option<Uuid>,
) -> Result<Vec<Post>, sqlx::Error> {
    let posts = sqlx::query_as::<_, Post>(
        r#"
        SELECT id, user_id, caption, image_key, image_sizes, status, content_type, created_at, updated_at, soft_delete
        FROM posts
        WHERE user_id = $1
          AND soft_delete IS NULL
          AND (
              ($2::timestamptz IS NULL)
              OR (created_at, id) < ($2, $3)
          )
        ORDER BY created_at DESC, id DESC
        LIMIT $4
        "#
    )
    .bind(user_id)
    .bind(cursor_created_at)
    .bind(cursor_id)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(posts)
}
```

#### 3.2 Add Cursor Pagination to Messages
**File:** `backend/messaging-service/src/services/message_service.rs`

Add new function:

```rust
/// Cursor-based pagination for messages (efficient for deep pagination)
pub async fn get_message_history_cursor(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
    limit: i64,
    cursor_created_at: Option<DateTime<Utc>>,
    cursor_id: Option<Uuid>,
) -> Result<Vec<MessageDto>, AppError> {
    let query = if cursor_created_at.is_none() {
        // First page
        r#"
        SELECT id, sender_id, sequence_number, created_at, content, ...
        FROM messages
        WHERE conversation_id = $1 AND deleted_at IS NULL
        ORDER BY created_at ASC, id ASC
        LIMIT $2
        "#
    } else {
        // Subsequent pages
        r#"
        SELECT id, sender_id, sequence_number, created_at, content, ...
        FROM messages
        WHERE conversation_id = $1
          AND deleted_at IS NULL
          AND (created_at, id) > ($2, $3)
        ORDER BY created_at ASC, id ASC
        LIMIT $4
        "#
    };

    // ... execute query and return results
}
```

#### 3.3 API Changes
Update API endpoints to support cursor parameter:

**Before:**
```
GET /api/v1/posts?user_id=uuid&limit=20&offset=40
GET /api/v1/messages?conversation_id=uuid&limit=50&offset=100
```

**After:**
```
GET /api/v1/posts?user_id=uuid&limit=20&cursor=base64(2025-10-28T12:00:00Z:uuid)
GET /api/v1/messages?conversation_id=uuid&limit=50&cursor=base64(2025-10-28T12:00:00Z:uuid)
```

**Cursor encoding:**
```rust
use base64::{engine::general_purpose, Engine as _};

pub fn encode_cursor(created_at: DateTime<Utc>, id: Uuid) -> String {
    let cursor_data = format!("{}:{}", created_at.to_rfc3339(), id);
    general_purpose::STANDARD.encode(cursor_data)
}

pub fn decode_cursor(cursor: &str) -> Result<(DateTime<Utc>, Uuid), AppError> {
    let decoded = general_purpose::STANDARD.decode(cursor)
        .map_err(|_| AppError::BadRequest("Invalid cursor".into()))?;
    let cursor_str = String::from_utf8(decoded)
        .map_err(|_| AppError::BadRequest("Invalid cursor encoding".into()))?;

    let parts: Vec<&str> = cursor_str.split(':').collect();
    if parts.len() != 2 {
        return Err(AppError::BadRequest("Invalid cursor format".into()));
    }

    let created_at = DateTime::parse_from_rfc3339(parts[0])
        .map_err(|_| AppError::BadRequest("Invalid timestamp in cursor".into()))?
        .with_timezone(&Utc);
    let id = Uuid::parse_str(parts[1])
        .map_err(|_| AppError::BadRequest("Invalid UUID in cursor".into()))?;

    Ok((created_at, id))
}
```

**Expected improvement:** 10-100x faster for deep pagination

---

## Phase 4: Caching Layer (Week 4)

### Goal
Add Redis caching for hot queries to reduce database load.

### Implementation

#### 4.1 Add Redis Cache Module
**File:** `backend/libs/cache/src/query_cache.rs`

```rust
use redis::{AsyncCommands, Client};
use serde::{de::DeserializeOwned, Serialize};
use std::sync::Arc;
use std::time::Duration;

pub struct QueryCache {
    client: Arc<Client>,
}

impl QueryCache {
    pub fn new(redis_url: &str) -> Result<Self, redis::RedisError> {
        Ok(Self {
            client: Arc::new(Client::open(redis_url)?),
        })
    }

    pub async fn get_or_fetch<T, F, Fut>(
        &self,
        key: &str,
        ttl_seconds: u64,
        fetch_fn: F,
    ) -> Result<T, Box<dyn std::error::Error>>
    where
        T: Serialize + DeserializeOwned,
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T, Box<dyn std::error::Error>>>,
    {
        let mut conn = self.client.get_async_connection().await?;

        // Try cache first
        if let Ok(Some(cached)) = conn.get::<_, Option<String>>(key).await {
            if let Ok(value) = serde_json::from_str(&cached) {
                return Ok(value);
            }
        }

        // Cache miss - fetch from source
        let value = fetch_fn().await?;

        // Store in cache
        let serialized = serde_json::to_string(&value)?;
        let _: () = conn.set_ex(key, serialized, ttl_seconds).await?;

        Ok(value)
    }

    pub async fn invalidate(&self, key: &str) -> Result<(), redis::RedisError> {
        let mut conn = self.client.get_async_connection().await?;
        let _: () = conn.del(key).await?;
        Ok(())
    }

    pub async fn invalidate_pattern(&self, pattern: &str) -> Result<u64, redis::RedisError> {
        let mut conn = self.client.get_async_connection().await?;
        let keys: Vec<String> = conn.keys(pattern).await?;
        if keys.is_empty() {
            return Ok(0);
        }
        conn.del(keys).await
    }
}
```

#### 4.2 Use Cache in Repositories
**Example: Post Repository**

```rust
pub async fn find_post_by_id_cached(
    pool: &PgPool,
    cache: &QueryCache,
    post_id: Uuid,
) -> Result<Option<Post>, sqlx::Error> {
    let cache_key = format!("post:{}", post_id);

    cache
        .get_or_fetch(&cache_key, 300, || async {
            find_post_by_id(pool, post_id)
                .await
                .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)
        })
        .await
        .map_err(|e| sqlx::Error::Io(std::io::Error::new(std::io::ErrorKind::Other, e)))
}

pub async fn update_post_status_cached(
    pool: &PgPool,
    cache: &QueryCache,
    post_id: Uuid,
    status: &str,
) -> Result<(), sqlx::Error> {
    // Update database
    update_post_status(pool, post_id, status).await?;

    // Invalidate cache
    let cache_key = format!("post:{}", post_id);
    cache.invalidate(&cache_key).await.ok();

    Ok(())
}
```

#### 4.3 Cache Strategy by Entity

| Entity | TTL | Invalidation Strategy |
|--------|-----|----------------------|
| Posts | 5 min | On update/delete |
| Conversations | 2 min | On new message |
| User Profiles | 10 min | On profile update |
| Feed Results | 1 min | On new post/follow |
| Message History | 30 sec | On new message |

**Expected improvement:** 10-100x faster for cached queries, 50-80% database load reduction

---

## Testing Strategy

### Performance Benchmarks

Run before and after each phase:

```bash
# Messaging performance
./scripts/benchmark_messaging.sh

# Feed performance
./scripts/benchmark_feed.sh

# Database load
./scripts/monitor_db_load.sh
```

### Load Testing Targets

| Metric | Before | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|--------|--------|---------|---------|---------|---------|
| Message send (1k conv) | 200ms | 20ms | 15ms | 15ms | 10ms |
| Message history (100msg) | 300ms | 250ms | 100ms | 90ms | 30ms |
| Feed generation | 500ms | 100ms | 50ms | 50ms | 20ms |
| Deep pagination (p100) | 1000ms+ | 800ms | 600ms | 50ms | 20ms |
| Conversation fetch | 100ms | 30ms | 25ms | 25ms | 10ms |

---

## Rollback Procedures

Each phase has specific rollback steps documented above. General rollback strategy:

1. **Phase 1 (Migrations):**
   - Run rollback SQL scripts
   - Restart services to clear cached schemas
   - Verify data integrity

2. **Phase 2-4 (Code Changes):**
   - Git revert commits
   - Redeploy previous version
   - Monitor for errors

**Safety measures:**
- All migrations are additive (no data loss risk)
- All code changes are backward compatible
- Keep old endpoints working during transition period

---

## Monitoring Post-Deployment

### Key Metrics to Watch

1. **Query Performance (pg_stat_statements):**
```sql
SELECT
    calls,
    mean_exec_time::int as avg_ms,
    total_exec_time::int as total_ms,
    query
FROM pg_stat_statements
WHERE mean_exec_time > 50
ORDER BY total_exec_time DESC
LIMIT 20;
```

2. **Connection Pool Health:**
```rust
// Log pool stats every minute
tokio::spawn(async move {
    loop {
        tokio::time::sleep(Duration::from_secs(60)).await;
        let size = pool.size();
        let idle = pool.num_idle();
        tracing::info!("Pool stats: size={} idle={}", size, idle);
    }
});
```

3. **Cache Hit Rate:**
```bash
# Redis INFO stats
redis-cli INFO stats | grep keyspace_hits
```

### Alerts to Configure

- Query latency p99 > 500ms
- Connection pool utilization > 80%
- Cache hit rate < 70%
- ClickHouse partition count > 36 (need cleanup)

---

## Success Criteria

### Phase 1
- ✅ Message send latency < 50ms p95
- ✅ All migrations run without errors
- ✅ Zero data loss or corruption
- ✅ Feed service operational with ClickHouse tables

### Phase 2
- ✅ Message history latency < 100ms p95
- ✅ Feed generation latency < 100ms p95
- ✅ All unit tests passing

### Phase 3
- ✅ Deep pagination latency < 50ms p95 (any page)
- ✅ API clients migrated to cursor pagination
- ✅ OFFSET pagination deprecated (but still working)

### Phase 4
- ✅ Cache hit rate > 70%
- ✅ Database query load reduced by 50%
- ✅ Hot query latency < 30ms p95

---

## Timeline Summary

| Phase | Duration | Risk | Impact |
|-------|----------|------|--------|
| Phase 1: Critical Fixes | 1 week | Low | Very High (5-10x) |
| Phase 2: Query Optimization | 1 week | Low | High (2-3x) |
| Phase 3: Cursor Pagination | 1 week | Medium | High (10x for deep pages) |
| Phase 4: Caching Layer | 1 week | Medium | Very High (10-100x for cached) |

**Total Duration:** 4 weeks
**Total Expected Improvement:** 10-50x across all operations
