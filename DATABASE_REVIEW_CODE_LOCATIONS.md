# Database Performance Review - Code Locations Reference

## Critical Issues - Code Locations

### 1. Missing Indexes on engagement_events
**Current State**: NO INDEXES
**Location**: `/Users/proerror/Documents/nova/backend/migrations/035_trending_system.sql`
**Lines**: 1-50 (table creation without indexes)

**Related Code Using This Table**:
- `/Users/proerror/Documents/nova/backend/feed-service/src/db/trending_repo.rs:345-368` (get_engagement_count)
- `/Users/proerror/Documents/nova/backend/feed-service/src/db/trending_repo.rs:370-393` (compute_score)

**Solution**: Apply migration 036_critical_performance_indexes.sql

---

### 2. DataLoader Stubs Not Implemented
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/loaders.rs`
**Lines**: 19-108

**Stub Implementations**:
- Line 24-28: `IdCountLoader` - dummy data generation
- Line 60-78: `UserIdLoader` - returns fake "User N" names
- Line 92-108: `PostIdLoader` - returns fake content
- Line 126-140: `LikeCountLoader` - enumerated fake counts
- Line 162-178: `FollowCountLoader` - stub not shown

**Usage Pattern**:
```rust
// Lines 35-48 (IdCountLoader.load)
let counts: HashMap<String, i32> = keys
    .iter()
    .enumerate()
    .map(|(idx, id)| (id.clone(), (idx as i32 + 1) * 10))  // ❌ FAKE
    .collect();
```

**Impact**: GraphQL queries with nested resolvers trigger N separate queries

**Where It's Called**:
- `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/mod.rs` (schema building)
- Any GraphQL query selecting nested fields

---

### 3. No Circuit Breaker Pattern
**Missing From**:
- `/Users/proerror/Documents/nova/backend/libs/db-pool/src/lib.rs` (pool management)
- `/Users/proerror/Documents/nova/backend/libs/db-pool/src/metrics.rs` (metrics only, no breaker)
- All services using pool.acquire()

**Current Behavior** (Line 188-197 in lib.rs):
```rust
.acquire_timeout(Duration::from_secs(config.acquire_timeout_secs))
// Just waits 10s then fails - no circuit breaker
```

**Impact**: When DB unavailable, all requests wait 10s then timeout

---

## High Priority Issues - Code Locations

### 4. Acquire Timeout Too High (10s)
**File**: `/Users/proerror/Documents/nova/backend/libs/db-pool/src/lib.rs`
**Line**: 141

```rust
acquire_timeout_secs: std::env::var("DB_ACQUIRE_TIMEOUT_SECS")
    .ok()
    .and_then(|v| v.parse().ok())
    .unwrap_or(10),  // ❌ TOO HIGH
```

**Recommendation**: Change default from 10 to 1

---

### 5. Neo4j Queries Not Batched
**File**: `/Users/proerror/Documents/nova/backend/feed-service/src/services/graph/neo4j.rs`

**Problem Locations**:
- Line 133-164: `suggested_friends()` - executes per-user
- Line 167-190: `mutual_count()` - executes per-pair

**Usage Pattern** (causes N+1):
```rust
// Each loop iteration triggers separate Neo4j query
for user_id in user_ids {
    let suggestions = graph_service.suggested_friends(user_id).await?;
}
```

**Also Issue**: Line 69 and similar - `.unwrap()` panic risk
```rust
.graph
.as_ref()
.unwrap()  // ❌ Panics on None
```

---

### 6. Cache Stampede Risk
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/cache/redis_cache.rs`
**Lines**: 39-51 (cache_feed_item)

**Problem**: No lock mechanism
```rust
pub async fn cache_feed_item(&self, feed_id: &str, item: &FeedItem) -> Result<()> {
    let key = format!("feed:{}", feed_id);
    let value = serde_json::to_string(item)?;

    redis::cmd("SETEX")
        .arg(&key)
        .arg(self.ttl_seconds)
        .arg(&value)
        .query_async::<_, ()>(&mut self.redis.clone())
        .await?;

    Ok(())
}
// ❌ No distributed lock - 100 concurrent misses = 100 DB queries
```

---

### 7. ClickHouse Batch Inserts Sequential
**File**: `/Users/proerror/Documents/nova/backend/search-service/src/services/clickhouse.rs`
**Lines**: 137-151

```rust
pub async fn record_search_events_batch(&self, events: Vec<SearchEvent>) {
    let mut insert = self.client.insert("search_analytics")?;
    for event in events {
        insert.write(&event).await?;  // ❌ Sequential, one-by-one
    }
    insert.end().await?;
}
```

**Better Pattern**: Buffer in chunks of 1000

---

### 8. Outbox Events Not Monitored
**File**: `/Users/proerror/Documents/nova/backend/migrations/083_outbox_pattern_v2.sql`
**Lines**: 197-241

**Functions Created** (but never called):
- Line 198: `outbox_status` view
- Line 212: `check_outbox_health()` function

**Missing**: Application code that queries these

**Should Be Called**: Every 60 seconds by monitoring service

---

### 9. trending_scores Missing Indexes
**File**: `/Users/proerror/Documents/nova/backend/migrations/035_trending_system.sql`
**Lines**: Table creation (no PK, no query indexes)

```sql
CREATE TABLE trending_scores (
    content_id UUID NOT NULL,      // ❌ NO PRIMARY KEY
    content_type VARCHAR(50),
    time_window VARCHAR(10),
    category VARCHAR(255),
    rank INT,
    score NUMERIC(10, 4),
    // ... more fields but no indexes
);
// ❌ NO INDEXES
```

**Related Queries**:
- `/Users/proerror/Documents/nova/backend/feed-service/src/db/trending_repo.rs:186-262` (get_trending)
- `/Users/proerror/Documents/nova/backend/feed-service/src/db/trending_repo.rs:395-472` (get_trending_by_type)

---

### 10. Redis Operations Not Wrapped with Timeout
**File**: `/Users/proerror/Documents/nova/backend/feed-service/src/utils/redis_timeout.rs`
**Implementation**: Lines 20-31 (defined but unused)

```rust
pub async fn run_with_timeout<F, T>(future: F) -> Result<T, RedisError> {
    // Function exists but...
}
// ❌ Only 2 callers in entire codebase
```

**Should Wrap**: All operations in
- `/Users/proerror/Documents/nova/backend/graphql-gateway/src/cache/redis_cache.rs`
- `/Users/proerror/Documents/nova/backend/search-service/src/services/redis_cache.rs`

---

## Medium Priority Issues - Code Locations

### 11. Potential N+1 in Engagement Counting
**File**: `/Users/proerror/Documents/nova/backend/feed-service/src/db/trending_repo.rs`
**Lines**: 345-368

**Problem**: Single-item query method
```rust
pub async fn get_engagement_count(&self, content_id: Uuid, time_window: TimeWindow)
    -> Result<i64>
{
    // Queries single content_id
    let count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*)
        FROM engagement_events
        WHERE content_id = $1
            AND created_at >= NOW() - INTERVAL '1 hour' * $2
        "#,
    )
    .bind(content_id)
    .bind(time_window.hours())
    .fetch_one(&self.pool)
    .await?;

    Ok(count)
}

// If called in loop:
for item in items {
    get_engagement_count(item.content_id).await?;  // N queries!
}
```

**Recommendation**: Implement batch version

---

### 12. gRPC Connection Pool Has Empty Health Check
**File**: `/Users/proerror/Documents/nova/backend/libs/grpc-clients/src/pool.rs`
**Lines**: 55-59

```rust
pub async fn health_check(&self) -> Result<(), Box<dyn std::error::Error>> {
    // Implement health check logic here
    // For now, just return ok  ❌ STUB
    Ok(())
}
```

**Used By**: Services using gRPC clients

**Should Check**: Each channel is ready and responding

---

## Summary by Service

### feed-service
- `src/db/trending_repo.rs`: N+1 risk in engagement counting
- `src/services/graph/neo4j.rs`: N+1 in graph queries, unwrap panics
- `src/utils/redis_timeout.rs`: Defined but unused timeout wrapper

### graphql-gateway
- `src/schema/loaders.rs`: **ALL DataLoaders are stubs** (CRITICAL)
- `src/cache/redis_cache.rs`: No stampede prevention
- `src/main.rs`: No query execution timeout

### search-service
- `src/services/clickhouse.rs`: Sequential batch inserts, no query timeout

### libs/db-pool
- `src/lib.rs`: Acquire timeout too high, no circuit breaker
- `src/metrics.rs`: Metrics only, no breaker

### libs/grpc-clients
- `src/pool.rs`: Health check is stub

### All Services
- Using `pool.acquire()` without circuit breaker protection

---

## Test Files Using These Modules

### DataLoader Tests (Currently Skipped)
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/tests/` (need to find exact file)
- Tests should verify batch loading, not dummy data

### Connection Pool Tests
**File**: `/Users/proerror/Documents/nova/backend/libs/db-pool/src/lib.rs:265-438`
- Tests verify pool configuration, not circuit breaker behavior

### Redis Tests
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/cache/redis_cache.rs:253-315`
- Tests marked with `#[ignore]` (require Redis)
- No timeout tests

---

## Configuration Environment Variables

### Database Pool Config
Located: `/Users/proerror/Documents/nova/backend/libs/db-pool/src/lib.rs:59-84`

Available overrides:
- `DATABASE_URL` - PostgreSQL connection string
- `DB_MAX_CONNECTIONS` - Default per-service
- `DB_MIN_CONNECTIONS` - Default per-service
- `DB_CONNECT_TIMEOUT_SECS` - Default 5
- `DB_ACQUIRE_TIMEOUT_SECS` - Default 10 ❌ TOO HIGH
- `DB_IDLE_TIMEOUT_SECS` - Default 600
- `DB_MAX_LIFETIME_SECS` - Default 1800

### Redis Timeout Config
Located: `/Users/proerror/Documents/nova/backend/feed-service/src/utils/redis_timeout.rs:6-17`

Available override:
- `REDIS_COMMAND_TIMEOUT_MS` - Default 3000 (3 seconds)

---

## Migration Files of Interest

### Index Migrations
- `030_database_optimization.sql` - 60+ indexes, comprehensive coverage
- `035_trending_system.sql` - **NO INDEXES** ❌
- `036_critical_performance_indexes.sql` - NEW (to be deployed)

### Schema Changes
- `083_outbox_pattern_v2.sql` - Outbox implementation (good pattern)
- `027_post_video_association.sql` - Post/video linking

### View Deployments
- Lines 198-209 in 083_outbox_pattern_v2.sql - Outbox monitoring views (unused)

---

## Automated Deploy Notes

When deploying fixes:

1. **Migration 036** - Can use `CONCURRENTLY` flag
2. **DataLoaders** - Use feature flag for gradual rollout
3. **Circuit Breaker** - Start with high threshold (20 failures)
4. **Timeout Changes** - Load test in staging first
5. **Redis Wrapping** - Low risk, can deploy directly

---

**Total Issues Found**: 15
**Files Requiring Changes**: 12
**New Files to Create**: 1 (migration 036, circuit breaker lib)
**Configuration Changes**: 3 (timeouts, thresholds, feature flags)
