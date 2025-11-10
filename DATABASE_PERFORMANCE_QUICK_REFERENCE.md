# Database Performance Optimization - Quick Reference Guide

**Last Updated**: November 11, 2025

---

## 🚨 Critical Issues (Fix These First)

### 1. Missing Indexes on Hot Tables
**File**: `/Users/proerror/Documents/nova/backend/migrations/035_trending_system.sql`

**Add to new migration (036_critical_indexes.sql)**:
```sql
-- engagement_events: zero indexes - causing 12.5s queries
CREATE INDEX idx_engagement_events_content_id
    ON engagement_events(content_id)
    WHERE created_at >= NOW() - INTERVAL '30 days';

CREATE INDEX idx_engagement_events_trending
    ON engagement_events(content_id, event_type, created_at DESC)
    WHERE created_at >= NOW() - INTERVAL '30 days';

-- trending_scores: no primary key or query indexes
ALTER TABLE trending_scores
    ADD CONSTRAINT pk_trending_scores
    PRIMARY KEY (content_id, time_window, category);

CREATE INDEX idx_trending_scores_rank
    ON trending_scores(time_window, category, score DESC);

ANALYZE engagement_events;
ANALYZE trending_scores;
```

**Impact**: 12.5s queries → 0.5ms (25x improvement)

---

### 2. DataLoader Stubs Not Implemented
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/loaders.rs`

**Current (Broken)**:
```rust
// Lines 66-78: Just returns dummy data, doesn't query database
let users: HashMap<String, String> = keys
    .iter()
    .map(|id| (id.clone(), format!("User {}", id)))  // ❌ FAKE DATA
    .collect();
```

**Fix - Replace with Actual Queries**:
```rust
#[async_trait::async_trait]
impl Loader<Uuid> for UserIdLoader {
    type Value = User;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        let users = sqlx::query_as::<_, User>(
            "SELECT id, name, email FROM users WHERE id = ANY($1)"
        )
        .bind(keys)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| e.to_string())?;

        Ok(users.into_iter().map(|u| (u.id, u)).collect())
    }
}
```

**Requirement**: Add `pool: PgPool` field to loader struct

**Impact**: 6.7x fewer queries, 100-500ms latency improvement per request

---

### 3. No Circuit Breaker for Database Failures
**Missing From**: All services

**Add to libs/db-pool/src/circuit_breaker.rs**:
```rust
pub struct DatabaseCircuitBreaker {
    failures: Arc<AtomicU32>,
    last_failure: Arc<RwLock<Option<Instant>>>,
    threshold: u32,
    timeout: Duration,
}

impl DatabaseCircuitBreaker {
    pub async fn execute<F, T>(&self, f: F) -> Result<T, CircuitBreakerError>
    where
        F: Fn() -> BoxFuture<'static, Result<T, sqlx::Error>>,
    {
        if self.is_open() {
            return Err(CircuitBreakerError::CircuitOpen);  // Fast fail
        }

        match f().await {
            Ok(result) => {
                self.failures.store(0, Ordering::Relaxed);
                Ok(result)
            }
            Err(e) => {
                let count = self.failures.fetch_add(1, Ordering::Relaxed) + 1;
                *self.last_failure.write().unwrap() = Some(Instant::now());

                if count >= self.threshold {
                    Err(CircuitBreakerError::CircuitOpen)  // Trip immediately
                } else {
                    Err(CircuitBreakerError::DatabaseError(e))
                }
            }
        }
    }

    fn is_open(&self) -> bool {
        if let Some(last) = *self.last_failure.read().unwrap() {
            if last.elapsed() < Duration::from_secs(30) {
                self.failures.load(Ordering::Relaxed) >= self.threshold
            } else {
                false  // Try recovery
            }
        } else {
            false
        }
    }
}
```

**Impact**: Fast-fail on database outage (10s timeout → immediate failure)

---

## ⚠️ High Priority Issues

### 4. Database Acquire Timeout Too High
**File**: `/Users/proerror/Documents/nova/backend/libs/db-pool/src/lib.rs:141`

**Current**:
```rust
acquire_timeout_secs: std::env::var("DB_ACQUIRE_TIMEOUT_SECS")
    .ok()
    .and_then(|v| v.parse().ok())
    .unwrap_or(10),  // ❌ 10 seconds = too high
```

**Change To**:
```rust
acquire_timeout_secs: std::env::var("DB_ACQUIRE_TIMEOUT_SECS")
    .ok()
    .and_then(|v| v.parse().ok())
    .unwrap_or(1),  // ✅ 1 second = reasonable default
```

**Testing**: Load test in staging, monitor p99 latency

---

### 5. Neo4j Queries Not Batched
**File**: `/Users/proerror/Documents/nova/backend/feed-service/src/services/graph/neo4j.rs:133-164`

**Current (N+1 Problem)**:
```rust
// Executes once per user
pub async fn suggested_friends(&self, user_id: Uuid, limit: usize) -> Result<Vec<(Uuid, u64)>> {
    // Single user query...
}

// Usage causing N queries:
for user_id in user_ids {
    let friends = graph_service.suggested_friends(user_id, 5).await?;
}
```

**Solution - Implement Batch**:
```rust
pub async fn batch_suggested_friends(
    &self,
    user_ids: &[Uuid],
    limit: usize,
) -> Result<HashMap<Uuid, Vec<(Uuid, u64)>>> {
    let cypher = r#"
        UNWIND $users AS uid
        MATCH (me:User {id: uid})-[:FOLLOWS]->(:User)-[:FOLLOWS]->(c:User)
        WHERE c.id <> uid AND NOT (me)-[:FOLLOWS]->(c)
        RETURN uid, c.id AS candidate_id, count(*) AS mutuals
        ORDER BY mutuals DESC
        LIMIT $limit
    "#;

    let mut result = self.graph.as_ref().unwrap()
        .execute(
            query(cypher)
                .param("users", user_ids.iter().map(|id| id.to_string()).collect::<Vec<_>>())
                .param("limit", limit as i64)
        )
        .await?;

    let mut suggestions: HashMap<Uuid, Vec<(Uuid, u64)>> = HashMap::new();
    // ... parse results ...
    Ok(suggestions)
}
```

---

### 6. Cache Stampede Risk
**File**: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/cache/redis_cache.rs:39-51`

**Problem**: When cache expires, 100 concurrent requests all query database

**Solution - Implement Lock**:
```rust
pub async fn get_feed_item_with_lock(&self, feed_id: &str) -> Result<FeedItem> {
    let cache_key = format!("feed:{}", feed_id);
    let lock_key = format!("feed:lock:{}", feed_id);

    // Try cache
    if let Ok(cached) = self.get_feed_item(feed_id).await {
        return Ok(cached);
    }

    // Try lock (only one thread succeeds)
    let acquired = redis::cmd("SET")
        .arg(&lock_key)
        .arg("1")
        .arg("EX").arg(5)
        .arg("NX")
        .query_async::<_, bool>(&mut self.redis.clone())
        .await
        .unwrap_or(false);

    if acquired {
        // Winner: fetch from DB
        let item = fetch_from_db(feed_id).await?;
        self.cache_feed_item(feed_id, &item).await?;

        redis::cmd("DEL").arg(&lock_key)
            .query_async::<_, ()>(&mut self.redis.clone()).await.ok();

        Ok(item)
    } else {
        // Loser: wait for winner's cache
        for _ in 0..50 {
            tokio::time::sleep(Duration::from_millis(100)).await;
            if let Ok(cached) = self.get_feed_item(feed_id).await {
                return Ok(cached);
            }
        }

        // Fallback: direct fetch
        fetch_from_db(feed_id).await
    }
}
```

---

## 📊 Performance Baselines

### Before Optimizations
| Operation | Latency | Connections | Notes |
|-----------|---------|-------------|-------|
| List trending (10 items) | 2-5s | High | N+1 queries |
| GraphQL post with creator | 500-1000ms | 2-3 | DataLoader stubs |
| Suggested friends (100 users) | 15-30s | Many | Per-user Neo4j queries |
| Cache stampede | +5-10s | 100x spike | All query DB |
| DB down | +10s timeout | Exhausted | No fast-fail |

### After Optimizations (Est.)
| Operation | Latency | Connections | Improvement |
|-----------|---------|-------------|-------------|
| List trending (10 items) | 50-100ms | Normal | 25-50x faster |
| GraphQL post with creator | 50-100ms | 1 | 5-10x faster |
| Suggested friends (100 users) | 100-200ms | 1-2 | 50-100x faster |
| Cache stampede | None | Normal | Prevented |
| DB down | Immediate | None | Instant fail |

---

## 🔧 Implementation Checklist

### Week 1: Critical Path
- [ ] Create migration 036 with engagement_events indexes
- [ ] Create migration 036 with trending_scores indexes
- [ ] Test trending queries (target: <100ms)
- [ ] Begin DataLoader implementation
- [ ] Start circuit breaker development

### Week 2: High Priority
- [ ] Complete DataLoader implementation
- [ ] Add comprehensive tests for DataLoaders
- [ ] Deploy circuit breaker to all services
- [ ] Reduce acquire timeout to 1s
- [ ] Load test in staging
- [ ] Implement batch Neo4j queries

### Week 3: Medium Priority
- [ ] Cache stampede prevention
- [ ] Outbox monitoring/alerting
- [ ] Redis timeout wrapping
- [ ] ClickHouse view optimization

---

## 📈 Monitoring Metrics

### Key Metrics to Track
```sql
-- Query performance
SELECT
    query_time,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY query_time) as p95,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY query_time) as p99
FROM query_logs;

-- Connection pool health
SELECT
    service,
    idle_connections,
    active_connections,
    max_connections,
    (active_connections::float / max_connections) * 100 as utilization_pct
FROM db_pool_metrics;

-- Index usage
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Slow queries
SELECT
    query,
    mean_exec_time,
    calls,
    mean_exec_time * calls as total_time
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY total_time DESC;
```

### Grafana Dashboard
Create dashboard with:
- Database query latency p50/p95/p99
- Connection pool utilization
- Index usage stats
- Outbox event lag (ms)
- Cache hit ratio
- Circuit breaker trips

---

## 🚀 Deployment Strategy

### Phase 1: Indexes (Zero Downtime)
```bash
# 1. Create indexes with CONCURRENTLY (doesn't lock table)
CREATE INDEX CONCURRENTLY idx_engagement_events_content_id
    ON engagement_events(content_id);

# 2. Verify indexes are used
EXPLAIN ANALYZE SELECT ... FROM engagement_events WHERE content_id = $1;

# 3. Deploy migration
```

### Phase 2: DataLoaders (Feature Flag)
```rust
// Use feature flag for gradual rollout
#[cfg(feature = "dataloader_v2")]
pub use loaders_v2::*;

#[cfg(not(feature = "dataloader_v2"))]
pub use loaders_v1::*;

// In Cargo.toml, enable via deployment config
```

### Phase 3: Circuit Breaker (Canary)
```rust
// Start with high threshold (allow lots of failures)
let breaker = CircuitBreaker::new(
    threshold: 20,     // Trip after 20 failures
    timeout: Duration::from_secs(60),
);

// Monitor in staging, gradually lower threshold
// week 1: threshold=20
// week 2: threshold=10
// week 3: threshold=5
```

---

## 🆘 Troubleshooting

### Queries Still Slow After Index Creation
```sql
-- Verify index is being used
EXPLAIN ANALYZE SELECT * FROM engagement_events WHERE content_id = $1;

-- If not using index:
-- 1. Check table statistics
ANALYZE engagement_events;

-- 2. Rebuild index
REINDEX INDEX idx_engagement_events_content_id;

-- 3. Check for locks
SELECT * FROM pg_locks WHERE NOT granted;

-- 4. Force index usage in query
SELECT /*+ IndexScan(engagement_events idx_engagement_events_content_id) */
    * FROM engagement_events WHERE content_id = $1;
```

### DataLoader Returns Empty Results
```rust
// Debug checklist:
// 1. Verify pool is connected: dbg!(&self.pool.acquire().await);
// 2. Check SQL query: println!("SQL: SELECT * FROM users WHERE id = {:?}", keys);
// 3. Add logging: tracing::info!("Loaded {} users", users.len());
// 4. Test with hardcoded data first
```

### Circuit Breaker Always Open
```rust
// Debugging:
// 1. Lower threshold temporarily: CircuitBreaker::new(1, ...)
// 2. Check database connectivity: pool.acquire().await
// 3. Verify timeout duration is long enough
// 4. Check if errors are transient or persistent
```

---

## 📚 Additional Resources

- Full Review: `/Users/proerror/Documents/nova/DATABASE_PERFORMANCE_REVIEW.md`
- DB Pool Config: `/Users/proerror/Documents/nova/backend/libs/db-pool/src/lib.rs`
- Migrations: `/Users/proerror/Documents/nova/backend/migrations/`
- GraphQL Schema: `/Users/proerror/Documents/nova/backend/graphql-gateway/src/schema/`

---

**Questions?** See the comprehensive review for detailed explanations and code examples.
