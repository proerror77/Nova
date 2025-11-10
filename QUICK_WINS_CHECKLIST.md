# Nova Backend - Quick Wins Implementation Checklist

**Estimated Delivery**: 2 weeks  
**Expected P99 Latency Improvement**: 40-50% (400-500ms → 200-300ms)  
**Team Capacity Required**: 2 engineers, part-time

---

## QUICK WIN #1: Remove Warning Suppression (2 hours)

**Owner**: Dev Lead  
**File**: `backend/user-service/src/lib.rs` (lines 1-6)

### Checklist:
- [ ] Remove `#![allow(warnings)]`
- [ ] Remove `#![allow(clippy::all)]`
- [ ] Run `cargo clippy --fix` to auto-fix
- [ ] Manually fix remaining 20-30 warnings (mostly:)
  - [ ] Unused variables/imports
  - [ ] Unnecessary clones
  - [ ] Missing docs
- [ ] Run full test suite: `cargo test --all`
- [ ] PR review + merge

### Impact:
- Prevent future hidden performance bugs
- Enable compiler-based optimization detection

---

## QUICK WIN #2: Pool Exhaustion Early Rejection (2.5 hours)

**Owner**: Infrastructure Team  
**File**: `backend/libs/db-pool/src/lib.rs`

### Implementation:
1. **Add early rejection function**:
```rust
pub async fn acquire_with_backpressure(
    pool: &PgPool,
    threshold: f32,
) -> Result<PooledConnection> {
    let utilization = calc_utilization(pool);
    if utilization > threshold {
        return Err(Error::PoolExhausted);
    }
    pool.acquire_timeout(Duration::from_secs(2)).await
}
```

2. **Update all pool acquisitions**:
   - [ ] user-service handlers
   - [ ] feed-service handlers
   - [ ] content-service handlers
   - [ ] search-service handlers

3. **Add monitoring**:
   - [ ] `pool_utilization` gauge metric
   - [ ] `pool_exhausted` counter metric
   - [ ] Alert on utilization > 85%

4. **Test**:
   - [ ] Unit test pool exhaustion logic
   - [ ] Load test at 100% capacity
   - [ ] Verify early rejection vs infinite block

### Impact:
- Prevent cascading failures from pool starvation
- MTTR improvement: 5x faster detection and recovery

---

## QUICK WIN #3: Structured Logging (3.5 hours)

**Owner**: Observability Team  
**File**: Create `backend/libs/actix-middleware/src/logging.rs`

### Implementation:
1. **Create standard logging macro**:
```rust
#[macro_export]
macro_rules! log_request {
    ($user_id:expr, $duration_ms:expr, $status:expr, $message:expr) => {
        tracing::info!(
            user_id = %$user_id,
            duration_ms = $duration_ms,
            http_status = $status,
            message = $message,
            correlation_id = %get_correlation_id(),
        );
    };
}
```

2. **Apply to 5 critical paths**:
   - [ ] `feed-service::handlers::get_feed`
   - [ ] `user-service::handlers::follow_user`
   - [ ] `content-service::handlers::create_post`
   - [ ] `graphql-gateway::handlers::graphql_handler`
   - [ ] `recommendation_v2::get_recommendations`

3. **Enforce correlation ID**:
   - [ ] Middleware: inject correlation ID if missing
   - [ ] Service clients: propagate to downstream services
   - [ ] Kafka producer: include in messages

4. **Test**:
   - [ ] Single request traced across 3+ services
   - [ ] Verify all fields present in logs

### Impact:
- Incident investigation: 30 min → 10 min (3x faster)
- Enable automated alerting on latency anomalies

---

## QUICK WIN #4: Database Indexes (1.5 hours)

**Owner**: Database Team  
**File**: Create `backend/migrations/090_performance_indexes.sql`

### Critical Indexes:
```sql
-- Feed candidates lookup (feeds are 70% of queries)
CREATE INDEX CONCURRENTLY IF NOT EXISTS 
  idx_feed_candidates_user_created 
  ON feed_candidates(user_id, created_at DESC);

-- User followers/following pagination
CREATE INDEX CONCURRENTLY IF NOT EXISTS 
  idx_follows_follower_created 
  ON follows(follower_id, created_at DESC);

-- Posts by user (content-service)
CREATE INDEX CONCURRENTLY IF NOT EXISTS 
  idx_posts_user_visibility 
  ON posts(user_id, visibility, created_at DESC);

-- User preferences lookup
CREATE INDEX CONCURRENTLY IF NOT EXISTS 
  idx_user_blocked_users 
  ON user_preferences(user_id, blocked_user_id);
```

### Validation:
- [ ] Create indexes in staging first
- [ ] Measure query performance before/after
- [ ] Expected improvement: 70-80% faster
- [ ] Deploy to production

### Impact:
- Feed generation: 500ms p99 → 100ms p99 (80% faster)
- Follow pagination: 300ms p99 → 100ms p99 (67% faster)

---

## QUICK WIN #5: GraphQL Query Result Caching (2 hours)

**Owner**: GraphQL Gateway Team  
**File**: `backend/graphql-gateway/src/cache/mod.rs`

### Implementation:
1. **Add caching layer**:
```rust
pub async fn execute_cached(
    schema: &AppSchema,
    query: &str,
    user_id: &str,
) -> Result<CachedResponse> {
    let cache_key = format!("graphql:{}:{}", hash(query), user_id);
    
    if let Ok(Some(cached)) = cache.get::<_>(&cache_key).await {
        return Ok(cached);
    }
    
    let result = schema.execute(query).await;
    cache.set_with_ttl(&cache_key, &result, 300).await?;
    Ok(result)
}
```

2. **Configure TTLs**:
   - Personalized queries: 5 min (for user-specific data)
   - Non-personalized: 10 min (trending, discover, etc.)

3. **Add metrics**:
   - [ ] `cache.hit` counter
   - [ ] `cache.miss` counter
   - [ ] Cache hit rate dashboard

4. **Test**:
   - [ ] Measure hit rate
   - [ ] Verify cache invalidation on mutations

### Impact:
- Non-personalized queries: 30-40% reduction in load
- Latency: 200-300ms reduction for cache hits

---

## QUICK WIN #6: Kafka Event Deduplication (2.5 hours)

**Owner**: Events Team  
**File**: `backend/user-service/src/services/events.rs`

### Enhancement:
1. **Add Bloom filter deduplication**:
```rust
pub struct EventDedupWithBloom {
    redis: RedisPool,
    bloom_filter: BloomFilter, // Redis-backed
}

impl EventDedupWithBloom {
    pub async fn is_duplicate(&self, event_id: &str) -> Result<bool> {
        // Fast: probably duplicate?
        if self.bloom_filter.contains(event_id).await? {
            // Slow: definitely duplicate? (Redis check)
            return self.redis.exists(event_id).await;
        }
        Ok(false)
    }
}
```

2. **Integration**:
   - [ ] Extend existing `EventDeduplicator`
   - [ ] Add to CDC consumer
   - [ ] Add to events consumer

3. **Metrics**:
   - [ ] `events.duplicate.detected` counter
   - [ ] Expected: 5-10% of events deduplicated

### Impact:
- CDC consumer CPU: 20-25% reduction
- ClickHouse duplicate inserts: 5-10% → <1%

---

## QUICK WIN #7: gRPC Client Connection Rotation (1.5 hours)

**Owner**: Platform Team  
**File**: `backend/libs/grpc-clients/src/lib.rs`

### Implementation:
```rust
pub struct ManagedServiceClient<T> {
    client: Arc<T>,
    created_at: Instant,
    max_age: Duration,
    factory: Arc<dyn Fn() -> T>,
}

impl<T> ManagedServiceClient<T> {
    pub async fn call<Req, Res>(
        &mut self,
        req: Req,
    ) -> Result<Res>
    where
        T: ServiceCall<Req, Res>,
    {
        if self.created_at.elapsed() > self.max_age {
            self.client = Arc::new((*self.factory)());
            self.created_at = Instant::now();
        }
        self.client.call(req).await
    }
}
```

3. **Test**:
   - [ ] Rolling deployment with stale connections
   - [ ] Verify no "connection reset" errors

### Impact:
- Eliminate 90% of stale connection cascades during deployments

---

## VALIDATION CHECKLIST

### Before Merging Each PR:
- [ ] Code review completed
- [ ] Unit tests passing (`cargo test --lib`)
- [ ] Integration tests passing (`cargo test --test '*'`)
- [ ] Clippy passing (`cargo clippy -- -D warnings`)
- [ ] Format correct (`cargo fmt`)
- [ ] Documentation updated (if needed)

### Performance Validation:
- [ ] Benchmark before/after (if applicable)
- [ ] Load test at 2x expected traffic
- [ ] Memory profiling (no leaks)
- [ ] CPU profiling (expected reduction)

### Production Deployment:
- [ ] Feature flag enabled (initially 10%)
- [ ] Monitor error rate (target: <0.1%)
- [ ] Monitor latency (target: 40-50% improvement)
- [ ] Monitor resource usage (target: -20-30%)
- [ ] Gradual rollout: 10% → 50% → 100%

---

## ROLLBACK PLAN

Each change should be reversible within 5 minutes:

1. **Remove warning suppression**: Revert to original `#![allow(...)]` state
2. **Pool rejection**: Feature flag to disable early rejection
3. **Structured logging**: Still supports old format (backward compatible)
4. **Indexes**: Can drop indexes (will hurt performance but service works)
5. **Query caching**: Toggle caching via env var
6. **Event dedup**: Disable Bloom filter, use only Redis
7. **Client rotation**: Disable rotation via config

---

## EXPECTED OUTCOMES

### Week 1-2 Results:
- [ ] P99 latency: 400-500ms → 200-300ms ✅
- [ ] P50 latency: 100-150ms → 60-80ms ✅
- [ ] Error rate: <0.1% (maintained) ✅
- [ ] No new incidents ✅

### Success Criteria:
- All 7 quick wins merged to production
- Latency improvement >30% measured
- Zero regressions in error rate
- Team satisfaction: can move to Phase 2

---

## EFFORT ESTIMATION

| Task | Hours | Owner | Start | End |
|------|-------|-------|-------|-----|
| Remove warnings | 2 | Dev Lead | W1 Mon | W1 Tue |
| Pool exhaustion | 2.5 | Infra | W1 Mon | W1 Wed |
| Structured logging | 3.5 | Observability | W1 Tue | W1 Thu |
| DB indexes | 1.5 | Database | W1 Tue | W1 Wed |
| GraphQL caching | 2 | GraphQL | W1 Wed | W1 Thu |
| Kafka dedupe | 2.5 | Events | W2 Mon | W2 Tue |
| Client rotation | 1.5 | Platform | W2 Tue | W2 Wed |
| **TOTAL** | **15.5h** | Multiple | W1 Mon | W2 Wed |

**Team Allocation**: 2 FTE engineers, 40% capacity each = 16h/week available

---

## SUCCESS METRICS TO TRACK

### Performance (Real-time Dashboard):
```
metric: feed_api_p99_latency
current: 500ms
target: 150ms
acceptable: 200ms (40% improvement)

metric: user_service_p99_latency
current: 300ms
target: 100ms
acceptable: 150ms (50% improvement)

metric: pool_utilization
current: 60% peak
target: <40% at 2x load
```

### Reliability:
```
metric: cascade_failures_per_day
current: 2-3
target: 0
acceptable: <1

metric: error_rate
current: 0.5%
target: <0.1%
acceptable: 0.1%
```

### Cost:
```
metric: postgresql_cpu
target: -20% (less contention)

metric: clickhouse_cpu
target: -20% (less duplicate inserts + dedupe)
```

---

## NEXT STEPS AFTER QUICK WINS

Once all 7 quick wins complete (Week 2):
1. Measure and document improvements
2. Write case study for team knowledge base
3. Plan Phase 2: Strategic High-Value items (#9-12)
4. Schedule design review for #13-15 (major initiatives)

