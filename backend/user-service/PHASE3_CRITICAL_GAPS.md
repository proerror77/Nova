# Phase 3: Critical Gaps & Missing Implementations

## BLOCKING ISSUES (Phase 3 cannot complete without these)

### 1. CDC Consumer Service - NOT IMPLEMENTED
**Status**: 🔴 CRITICAL BLOCKER
**Impact**: Events from PostgreSQL never reach ClickHouse
**Severity**: P0

**What's Missing**:
```rust
// File: src/services/cdc_consumer.rs (DOES NOT EXIST)
pub struct CdcConsumer {
    consumer: StreamConsumer,
    ch_client: ClickHouseClient,
    metrics: CdcMetrics,
}

impl CdcConsumer {
    pub async fn start(&self) -> Result<()> {
        // Subscribe to: cdc.posts, cdc.users, cdc.comments, cdc.likes, cdc.follows
        // Transform Debezium envelope → ClickHouse schema
        // Batch insert with offset commit
    }
}
```

**Why it's critical**: Without this, all changes to PostgreSQL (new posts, likes, follows) don't flow to ClickHouse. The entire data pipeline breaks at this point.

**Integration point**: `/Users/proerror/Documents/nova/specs/phase-3-architecture/debezium-connector-config.json`

---

### 2. Events Stream Consumer - NOT IMPLEMENTED
**Status**: 🔴 CRITICAL BLOCKER
**Impact**: Client events ingested via REST API don't persist to ClickHouse
**Severity**: P0

**What's Missing**:
```rust
// File: src/services/events_consumer.rs (DOES NOT EXIST)
pub struct EventsConsumer {
    consumer: StreamConsumer,
    ch_client: ClickHouseClient,
    dedup_cache: Redis,
}

impl EventsConsumer {
    pub async fn start(&self) -> Result<()> {
        // Subscribe to `events` topic
        // Deduplication check (Redis cache)
        // Batch transform & insert to post_events
        // Commit offset
    }
}
```

**Why it's critical**: The REST `/events` endpoint currently publishes to Kafka but there's NO consumer to process those events. They're just buffered in Kafka forever.

**Flow today**:
```
Client → POST /events → EventRecord → Kafka → (nobody listening) ❌
```

**Flow after Phase 3**:
```
Client → POST /events → EventRecord → Kafka → EventsConsumer → ClickHouse post_events table ✅
```

---

### 3. Event Deduplication - NOT IMPLEMENTED
**Status**: 🟠 HIGH
**Impact**: Duplicate events processed multiple times (database consistency issues)
**Severity**: P1

**What's Missing**:
```rust
// Should be checked before any event processing
pub async fn check_and_store_idempotency_key(
    redis: &ConnectionManager,
    event_id: &str,
    timestamp_ms: i64
) -> Result<bool> {
    let key = format!("event_idempotency:{}:{}", event_id, timestamp_ms);
    
    if redis.exists::<_, bool>(&key).await? {
        return Ok(false); // Already processed
    }
    
    // Store with 24-hour TTL
    redis.set_ex(&key, "1", 86400).await?;
    Ok(true) // Process this event
}
```

**Why it matters**: Network retries could send the same event twice:
- Event A: "User liked post X"
- Network timeout, client retries
- Event A arrives again
- Without deduplication: post like_count incremented twice ❌

---

### 4. Materialized Views - NOT IMPLEMENTED
**Status**: 🟠 HIGH
**Impact**: Job queries run slowly (2-10s), can't support real-time features
**Severity**: P1

**What's Missing** (ClickHouse DDL):
```sql
-- MISSING: This MV would speed up trending queries 10x
CREATE MATERIALIZED VIEW post_engagement_hourly
ENGINE = MergeTree()
ORDER BY (hour, score)
POPULATE AS
SELECT 
  toStartOfHour(event_time) as hour,
  post_id,
  countIf(event_type='post_view') as views,
  countIf(event_type='post_like') as likes,
  countIf(event_type='post_comment') as comments,
  countIf(event_type='post_share') as shares,
  views * 0.1 + likes * 2 + comments * 3 + shares * 5 as score
FROM post_events
GROUP BY hour, post_id;

-- MISSING: User relationship caching
CREATE MATERIALIZED VIEW user_relationships_current
ENGINE = ReplacingMergeTree()
ORDER BY (follower_id, followee_id)
AS
SELECT 
  follower_id,
  followee_id,
  status,
  created_at
FROM user_relationships
WHERE status = 'active';
```

**Why it's critical**:
- Current trending query scans 1 hour of raw post_events (full table scan)
- With MV: query pre-aggregated data (point lookup)
- Performance: 5-10 seconds → <100ms

---

## HIGH PRIORITY GAPS

### 5. Real-time Cache Invalidation - NOT IMPLEMENTED
**Status**: 🟠 HIGH
**File**: `src/cache/feed_cache.rs`
**Current behavior**: Cache expires by TTL only (120s default)
**Missing**: Event-driven invalidation

**What should happen**:
```
Event: "User A likes post X"
  → Posted to Kafka (✅ working)
  → CDC consumer consumes (❌ not implemented)
  → Should trigger cache invalidation for:
    - Followers of post author (their feed changed)
    - User A (their feed changed - now they see their own like)
  → Invalidate Redis keys matching feed:v1:{user_id}:*
```

**Current flow**:
```
Event: "User A likes post X"
  → Posted to Kafka
  → Job runs every 60s, re-queries ClickHouse
  → Cache updated (if it hasn't expired)
  → Result: 60 second stale data ❌
```

---

### 6. Circuit Breaker Pattern - NOT IMPLEMENTED
**Status**: 🟠 HIGH
**Impact**: Cascade failures (if ClickHouse down, entire system fails)
**File**: All places calling `ch_client`

**Current behavior**: Every ClickHouse call can fail
**Missing**: Graceful degradation

**What should exist**:
```rust
pub struct CircuitBreaker {
    state: CircuitState, // Closed (normal), Open (failing), HalfOpen (testing)
    failure_threshold: u32,
    success_threshold: u32,
    timeout: Duration,
}

impl CircuitBreaker {
    pub async fn call<F, T>(&self, operation: F) -> Result<T> {
        match self.state {
            CircuitState::Closed => operation().await,
            CircuitState::Open => Err(CircuitBreakerOpen), // Fast-fail
            CircuitState::HalfOpen => {
                match operation().await {
                    Ok(result) => { self.reset(); Ok(result) }
                    Err(e) => { self.open(); Err(e) }
                }
            }
        }
    }
}
```

**Scenario today**:
- ClickHouse goes down
- All trending queries fail
- All suggested_users queries fail
- Users can't see feeds
- System cascades

**With circuit breaker**:
- ClickHouse goes down
- Circuit opens (fast-fail after 3 failures)
- Return cached/stale data from Redis
- Users see old but working feeds ✅

---

### 7. Metrics for CDC Pipeline - NOT IMPLEMENTED (TODOs exist)
**Status**: 🟠 HIGH
**File**: `src/metrics/mod.rs`
**Missing metrics**:

```rust
// CDC Lag (time from event in Postgres → event in ClickHouse)
pub static ref CDC_LAG_SECONDS: HistogramVec;
pub static ref CDC_OFFSET_COMMITS_TOTAL: CounterVec;
pub static ref CDC_OFFSET_COMMITS_FAILED: CounterVec;

// Event processing
pub static ref EVENT_PROCESSING_DURATION_SECONDS: HistogramVec;
pub static ref EVENT_PROCESSING_ERRORS_TOTAL: CounterVec;
pub static ref EVENT_DEDUPLICATION_HITS: CounterVec;

// Cache invalidation
pub static ref CACHE_INVALIDATION_LAG_MS: HistogramVec;
pub static ref CACHE_HIT_RATIO: GaugeVec;

// Job metrics (currently TODOs)
pub static ref JOB_REFRESH_DURATION_SECONDS: HistogramVec;
pub static ref JOB_REFRESH_TOTAL: CounterVec;

// ClickHouse metrics
pub static ref CLICKHOUSE_QUERY_DURATION_SECONDS: HistogramVec;
pub static ref CLICKHOUSE_BATCH_INSERT_DURATION_SECONDS: HistogramVec;
pub static ref CLICKHOUSE_ERRORS_TOTAL: CounterVec;

// Materialized views
pub static ref MATERIALIZED_VIEW_STALENESS_SECONDS: GaugeVec;
pub static ref MATERIALIZED_VIEW_REFRESH_DURATION_SECONDS: HistogramVec;
```

**Why it matters**: Without metrics, you can't see:
- How far behind is ClickHouse from Postgres?
- Are events being deduplicated?
- Why are trending queries slow?
- Is the system healthy?

---

## MEDIUM PRIORITY GAPS

### 8. Dead Letter Queue for Failed Events - NOT IMPLEMENTED
**Status**: 🟡 MEDIUM
**Impact**: Failed events silently dropped, data loss
**File**: `src/services/kafka_producer.rs`, `src/services/events_consumer.rs` (missing)

**Current behavior**: 
- Event fails to process → logged → dropped ❌

**Needed**:
```rust
// If processing fails 3 times, send to DLT
pub async fn handle_failed_event(&self, event: EventRecord, error: &str) -> Result<()> {
    let dlq_topic = "events-dlq";
    let dlq_event = FailedEventRecord {
        original_event: event,
        error: error.to_string(),
        failed_at: Utc::now(),
        retry_count: 3,
    };
    
    self.producer.send_json(
        &event.user_id.to_string(),
        &serde_json::to_string(&dlq_event)?
    ).await?;
    
    Ok(())
}
```

---

### 9. Schema Evolution Support - NOT IMPLEMENTED
**Status**: 🟡 MEDIUM
**Impact**: Can't add new event fields without breaking consumers
**File**: Event models, Kafka serialization

**Current approach**: Plain JSON (no schema)
**Needed**: Schema Registry or Protobuf

**Example problem**:
- v1 Events: {user_id, post_id, action}
- Add new field: {user_id, post_id, action, device_id}
- Old consumers see extra field → might crash
- New consumers see old events missing device_id → might crash

---

### 10. Dynamic Job Registration - NOT IMPLEMENTED
**Status**: 🟡 MEDIUM
**Impact**: Can't add/remove jobs without recompiling binary
**File**: `src/bin/job_worker.rs`

**Current**: Jobs hardcoded
```rust
// Every new job requires code change + recompile
let trending_job = Arc::new(TrendingGeneratorJob::new(config));
let suggestion_job = Arc::new(SuggestedUsersJob::new(config));
jobs.push((trending_job as Arc<dyn CacheRefreshJob>, ctx.clone()));
jobs.push((suggestion_job as Arc<dyn CacheRefreshJob>, ctx.clone()));
```

**Needed**: Load jobs from database/config
```rust
// Jobs loaded at runtime, no recompile needed
let job_configs = db.list_active_jobs().await?;
for config in job_configs {
    let job = create_job_from_config(&config)?;
    jobs.push((job, ctx.clone()));
}
```

---

## PHASE 3 DEPENDENCY MAP

```
Critical Path (Week 1):
  CDC Consumer ──┐
                ├──> ClickHouse post_events table (populated)
  Events Consumer─┘
        ↓
  Test E2E Flow (Postgres change → ClickHouse)
        ↓
        ├──> Materialized Views (Week 2)
        │      ↓
        │    Update Trending Job (Week 2)
        │      ↓
        │    Performance Test
        │
        ├──> Real-time Cache Invalidation (Week 3)
        │      ↓
        │    Subscribe to Kafka → Invalidate Redis
        │
        └──> Metrics + Circuit Breaker (Week 3-4)
               ↓
        Production Ready
```

---

## FILE LOCATIONS

| Component | File | Status |
|-----------|------|--------|
| CDC Consumer | `src/services/cdc_consumer.rs` | ❌ MISSING |
| Events Consumer | `src/services/events_consumer.rs` | ❌ MISSING |
| Circuit Breaker | `src/middleware/circuit_breaker.rs` | ❌ MISSING |
| Deduplication | `src/services/deduplication.rs` | ❌ MISSING |
| Error types | `src/error.rs` | ⚠️ Needs CDC types |
| Metrics | `src/metrics/mod.rs` | ⚠️ TODOs exist |
| Feed Cache | `src/cache/feed_cache.rs` | ⚠️ Needs invalidation |
| ClickHouse DDL | (separate) | ❌ MISSING MVs |
| Config | `src/config/mod.rs` | ✅ Ready |

---

## ESTIMATED EFFORT

| Task | Effort | Blocker |
|------|--------|---------|
| CDC Consumer | 3-5 days | YES |
| Events Consumer | 2-3 days | YES |
| Deduplication | 1 day | NO |
| Circuit Breaker | 1 day | NO |
| Materialized Views | 1 day | NO |
| Metrics | 2 days | NO |
| Cache Invalidation | 2 days | NO |
| Integration Tests | 2-3 days | NO |
| **TOTAL** | **15-20 days** | - |

---

## RECOMMENDED SPRINT PLAN

**Sprint 1 (Days 1-5): CDC Foundation**
- [ ] Implement CDC Consumer service
- [ ] Offset management & commit
- [ ] Transform Debezium envelope
- [ ] Test with docker-compose (Kafka + ClickHouse)

**Sprint 2 (Days 6-10): Events Pipeline**
- [ ] Events Consumer service
- [ ] Event deduplication
- [ ] Batch insert optimization
- [ ] End-to-end integration test

**Sprint 3 (Days 11-15): Performance**
- [ ] Materialized views
- [ ] Update trending job
- [ ] Circuit breaker wrapper
- [ ] Benchmark vs batch approach

**Sprint 4 (Days 16-20): Production Readiness**
- [ ] CDC pipeline metrics
- [ ] Cache invalidation
- [ ] Error handling + retries
- [ ] Load testing

---

## NEXT ACTION ITEMS

1. **Review** this document with backend team
2. **Assign** CDC Consumer to senior engineer (most complex)
3. **Create** PR template for Phase 3 work
4. **Setup** local docker-compose with Kafka + ClickHouse + Postgres
5. **Begin** CDC Consumer implementation

---

**Document Generated**: 2025-10-18
**Severity**: All CRITICAL items block Phase 3 completion
**Status**: Awaiting prioritization and resource allocation
