# Phase 3: Social Graph & Feed - Infrastructure Skeleton

**Status**: ✅ Infrastructure Templates Generated
**Date**: October 17, 2024
**Architecture**: TikTok-style OLTP + OLAP with ClickHouse

---

## 📋 Overview

Phase 3 infrastructure is now ready with 4 critical template files:
1. **Debezium Connector** - CDC pipeline from PostgreSQL to Kafka
2. **ClickHouse Schema** - OLAP layer with ranking algorithms
3. **Feed Service** - Personalized feed ranking engine (Rust + ClickHouse)
4. **Redis Jobs** - Background cache generators (hot posts, suggestions, feed warming)

---

## 📁 Files Generated

### 1. Debezium PostgreSQL Connector Template
**File**: `backend/connectors/debezium-postgres-connector.json`

**Purpose**: Change Data Capture (CDC) configuration to replicate PostgreSQL to Kafka

**Key Features**:
- ✅ Snapshot mode for initial load (posts, follows, comments, likes)
- ✅ Incremental CDC for real-time updates
- ✅ Topic transformation: CDC topics for each table (cdc.posts, cdc.follows, etc.)
- ✅ Error handling and dead-letter queue support
- ✅ JSON serialization for Kafka messages

**Deployment**:
```bash
# Upload to Kafka Connect REST API
curl -X POST http://kafka-connect:8083/connectors \
  -H "Content-Type: application/json" \
  -d @backend/connectors/debezium-postgres-connector.json
```

**Monitoring**:
```bash
# Check connector status
curl http://kafka-connect:8083/connectors/nova-postgres-cdc/status
```

---

### 2. ClickHouse OLAP Schema with Kafka Engine
**File**: `backend/clickhouse/schema.sql`

**Purpose**: Real-time OLAP database for analytics, ranking, and feed generation

**Database Design**:

#### Raw Data Layer
- `events_raw` - MergeTree with 90-day TTL for event streaming
- `events_kafka` - Kafka Engine consumer (standalone setup)
- `posts_cdc`, `follows_cdc`, `comments_cdc`, `likes_cdc` - ReplacingMergeTree for CDC tables

#### Aggregation Layer
- `post_metrics_1h` - SummingMergeTree with hourly metrics (likes, comments, shares, impressions)
- `user_author_90d` - User-author affinity scores (90-day interaction history)
- `hot_posts_1h` - Top posts cache by engagement
- `follow_graph` - Follow relationship cache

#### View Layer
- `mv_events_ingest` - Materialized view for events ingestion
- `mv_post_metrics_1h` - Auto-aggregation from raw events
- `mv_user_author_90d` - Auto-calculation of user affinities
- `feed_recent_follows` - Posts from followed users (last 72h)
- `post_ranking_scores` - Ranking scores with freshness/engagement/affinity

#### Indexes & Optimization
```
ORDER BY Strategy:
- events_raw: (created_at, user_id, post_id) - Time + user filtering
- posts_cdc: (id, created_at) - Post lookups + temporal
- post_metrics_1h: (post_id, metric_hour) - Scoring queries
```

#### TTL Strategy
```
- events_raw: 90 days (real-time retention)
- post_metrics_1h: 30 days (aggregates)
- user_author_90d: 90 days (affinity window)
- hot_posts_1h: 2 days (cache)
- follows_cdc: 365 days (complete history)
```

**Deployment**:
```bash
# Apply schema to ClickHouse
clickhouse-client < backend/clickhouse/schema.sql

# Verify tables
clickhouse-client -q "SHOW TABLES FROM default LIKE '%posts%'"
```

---

### 3. Feed Service - Ranking Algorithm Implementation
**File**: `backend/user-service/src/services/feed_service.rs`

**Purpose**: Personalized feed ranking with 3 candidate sources

**Architecture**:
```
User Request (GET /feed)
    ↓
[Redis Cache Hit?] → YES → Return cached feed (P95 ≤ 150ms)
    ↓ NO
[Query ClickHouse Parallel]
    ├─ F1: Follow candidates (last 72h, max 500 posts)
    ├─ F2: Trending candidates (top 200 by 24h engagement)
    └─ F3: Affinity candidates (high-interaction authors, 90d, max 200)
    ↓
[Merge Candidates + Dedup] → Priority: Follow > Trending > Affinity
    ↓
[Rank by Combined Score]
    Score = 0.30×freshness + 0.40×engagement + 0.30×affinity
    ↓
[Slice & Cache to Redis] → TTL: 60s
    ↓
Return to Client (P95 ≤ 800ms)
```

**Ranking Formulas**:
```
Freshness Score: exp(-λ * age_hours)           [λ = 0.10]
Engagement Score: log1p((L + 2C + 3S) / I)    [Normalized by impressions]
Affinity Score: log1p(interaction_count)       [From 90-day history]
Combined Score: 0.30×F + 0.40×E + 0.30×A      [Weighted average]
```

**Key Functions**:
```rust
pub async fn get_personalized_feed(
    &self,
    user_id: Uuid,
    offset: u32,
    limit: u32,
) -> Result<Vec<FeedItem>>

pub async fn get_follow_candidates(&self, user_id: Uuid) -> Result<Vec<RankedPost>>
pub async fn get_trending_candidates(&self) -> Result<Vec<RankedPost>>
pub async fn get_affinity_candidates(&self, user_id: Uuid) -> Result<Vec<RankedPost>>

fn merge_candidates(...) -> Vec<(RankedPost, String)>  // With deduplication
```

**ClickHouse Query Examples** (embedded in service):
```sql
-- F1: Follow candidates
SELECT fp.id, fp.user_id, pm.likes_count, ...
FROM posts_cdc fp
INNER JOIN follows_cdc f ON fp.user_id = f.following_id
WHERE f.follower_id = :user_id AND fp.created_at > now() - INTERVAL 72 HOUR
ORDER BY combined_score DESC LIMIT 500

-- F2: Trending candidates
SELECT post_id, likes_count, combined_score
FROM post_metrics_1h
WHERE metric_hour >= now() - INTERVAL 24 HOUR
ORDER BY combined_score DESC LIMIT 200

-- F3: Affinity candidates
SELECT fp.id, aa.interaction_count, ...
FROM posts_cdc fp
INNER JOIN user_author_90d aa ON fp.user_id = aa.author_id
WHERE aa.user_id = :user_id
ORDER BY combined_score DESC LIMIT 200
```

**SLO Targets**:
- Cache hit latency: P95 ≤ 150ms
- Cache miss latency: P95 ≤ 800ms
- ClickHouse query: P95 ≤ 500ms per source
- Feed cache hit rate: ≥ 90%

---

### 4. Redis Background Jobs
**File**: `backend/user-service/src/services/redis_job.rs`

**Purpose**: Background cache generators for performance optimization

#### A. Hot Post Generator (60-second refresh)
```rust
pub struct HotPostGenerator {
    config: HotPostJobConfig,
    clickhouse_client: Arc<ClickHouseClient>,
    redis_client: Arc<RedisClient>,
}
```

**Responsibility**:
1. Every 60 seconds, query ClickHouse for top 200 posts (last 1 hour)
2. Calculate engagement score: `0.40×engagement + 0.30×freshness`
3. Cache to Redis at key `hot:posts:1h` with TTL 120s

**Query**:
```sql
SELECT post_id, author_id, likes, comments, shares,
       0.40 * log1p(...) + 0.30 * exp(-0.10 * age_hours) as score
FROM post_metrics_1h
WHERE metric_hour >= now() - INTERVAL 1 HOUR
ORDER BY score DESC LIMIT 200
```

#### B. Suggested Users Generator (5-minute refresh)
```rust
pub struct SuggestedUsersGenerator {
    config: SuggestedUsersJobConfig,
    clickhouse_client: Arc<ClickHouseClient>,
    redis_client: Arc<RedisClient>,
}
```

**Responsibility**:
1. On-demand generation of suggested users per target user
2. Collaborative filtering: Find similar users → Get their followed authors
3. Exclude already-followed users
4. Cache to Redis at key `suggest:users:{user_id}` with TTL 600s

**Query**:
```sql
SELECT aa.author_id, count(distinct aa.user_id) as mutual_followers,
       round(log1p(sum(aa.interaction_count)), 4) as affinity_score
FROM user_author_90d aa
WHERE aa.author_id NOT IN (SELECT following_id FROM follows_cdc WHERE follower_id = :user_id)
GROUP BY aa.author_id
ORDER BY affinity_score DESC LIMIT 20
```

#### C. Feed Cache Warmer (2-minute refresh)
```rust
pub struct FeedCacheWarmer {
    config: FeedCacheWarmerConfig,
    clickhouse_client: Arc<ClickHouseClient>,
    redis_client: Arc<RedisClient>,
}
```

**Responsibility**:
1. Find top 100 active users (from event logs)
2. Pre-generate and cache first page of feed for each
3. Reduce cold-start latency for frequent users
4. Cache key: `feed:v1:{user_id}:0:{page_size}`

**Job Startup** (in main.rs):
```rust
let hot_post_job = HotPostGenerator::new(config, ch_client, redis_client)
    .start();  // Returns JoinHandle

let suggested_users_job = SuggestedUsersGenerator::new(config, ch_client, redis_client)
    .start();

let feed_cache_job = FeedCacheWarmer::new(config, ch_client, redis_client)
    .start();
```

---

## 🔄 Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ PostgreSQL (OLTP)                                           │
│ - users, posts, comments, likes, follows                   │
└────────────────┬────────────────────────────────────────────┘
                 │ CDC (Debezium + Kafka)
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Kafka Topics                                                │
│ - cdc.posts, cdc.follows, cdc.comments, cdc.likes          │
│ - events (behavior: impression, view, like, share)         │
└────────────────┬────────────────────────────────────────────┘
                 │ Kafka Engine + Events SDK
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ ClickHouse (OLAP)                                           │
│ Tables: posts_cdc, follows_cdc, events_raw, ...            │
│ MVs: mv_post_metrics_1h, mv_user_author_90d                │
└────────────────┬────────────────────────────────────────────┘
                 │ Periodic Queries + Aggregation
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Redis Cache                                                 │
│ Keys: hot:posts:1h, suggest:users:{id}, feed:v1:{id}:...  │
│ TTL: 60-600s depending on data type                         │
└────────────────┬────────────────────────────────────────────┘
                 │ API Layer
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Feed Service API                                            │
│ GET /feed → FeedService → Redis (hit) or ClickHouse (miss) │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Next Implementation Steps (H1-H14)

### H1-H2: Infrastructure Setup
- [ ] Set up ClickHouse (Docker or managed instance)
- [ ] Create Kafka topics (cdc.*, events)
- [ ] Deploy Debezium PostgreSQL connector

### H3-H4: ClickHouse Schema & Materialized Views
- [ ] Apply schema.sql to ClickHouse
- [ ] Verify all tables and views created
- [ ] Test Kafka Engine consumption
- [ ] Validate CDC data flow from PostgreSQL

### H5: Data Validation
- [ ] Run initial snapshot load via Debezium
- [ ] Verify OLTP ↔ OLAP consistency
- [ ] Check TTL and partitioning policies

### H6-H7: Ranking & Hot Feed
- [ ] Integrate FeedService into handler layer
- [ ] Connect FeedService to ClickHouse client
- [ ] Start HotPostGenerator job in main.rs
- [ ] Verify hot:posts:1h cache updates

### H8: Feed API Implementation
- [ ] Implement GET /api/v1/feed handler
- [ ] Test cache hit/miss scenarios
- [ ] Performance profiling (P95 latencies)

### H9: Recommendations
- [ ] Implement GET /api/v1/discover/suggested-users
- [ ] Start SuggestedUsersGenerator job
- [ ] Test collaborative filtering results

### H10: Event Streaming
- [ ] Create Events API endpoint (POST /events)
- [ ] Batch event publishing from clients
- [ ] Kafka producer configuration

### H11-H12: Observability & Testing
- [ ] Set up Grafana dashboards
- [ ] Monitor ClickHouse query performance
- [ ] E2E tests: Post → Like → Feed ranking update

### H13-H14: Tuning & Documentation
- [ ] Weight tuning (adjust 0.30/0.40/0.30 ratios)
- [ ] Runbooks and operational guides
- [ ] Canary deployment (10% users)

---

## 🔧 Integration Checklist

### Cargo.toml Updates Required
```toml
[dependencies]
# ClickHouse client
clickhouse-rs = "0.11"
clickhouse = "0.11"

# Redis
redis = "0.24"

# Kafka
rdkafka = "0.35"  # For events publishing

# Background jobs
tokio = { version = "1.35", features = ["full"] }

# Serialization
serde_json = "1.0"
uuid = { version = "1.0", features = ["serde", "v4"] }
chrono = { version = "0.4", features = ["serde"] }
```

### main.rs Integration
```rust
// Initialize ClickHouse client
let ch_client = Arc::new(ClickHouseClient::new(&config.clickhouse_url));

// Initialize Redis client
let redis_client = Arc::new(RedisClient::new(&config.redis_url));

// Start background jobs
let hot_post_job = HotPostGenerator::new(
    HotPostJobConfig::default(),
    ch_client.clone(),
    redis_client.clone(),
).start();

let suggestions_job = SuggestedUsersGenerator::new(
    SuggestedUsersJobConfig::default(),
    ch_client.clone(),
    redis_client.clone(),
).start();

let feed_warmer_job = FeedCacheWarmer::new(
    FeedCacheWarmerConfig::default(),
    ch_client.clone(),
    redis_client.clone(),
).start();

// Initialize FeedService
let feed_service = Arc::new(FeedService::new(
    FeedConfig::default(),
    ch_client,
    redis_client,
));
```

### Handler Example (handlers/feed.rs)
```rust
pub async fn get_feed(
    req: HttpRequest,
    query: Query<FeedQuery>,
    feed_service: web::Data<Arc<FeedService>>,
) -> Result<HttpResponse> {
    let user_id = extract_user_id(&req)?;
    let offset = query.offset.unwrap_or(0);
    let limit = query.limit.unwrap_or(20);

    let feed_items = feed_service
        .get_personalized_feed(user_id, offset, limit)
        .await?;

    Ok(HttpResponse::Ok().json(feed_items))
}
```

---

## 📊 Expected Performance

### Latency SLOs
| Scenario | P95 Latency | Notes |
|----------|------------|-------|
| Redis hit | ≤ 150ms | Hot feed cache |
| ClickHouse query | ≤ 500ms | Per candidate source |
| Full feed miss | ≤ 800ms | 3 queries + merge |
| Hot post refresh | ≤ 2s | Background job |
| Suggested users | ≤ 300ms | CF query |

### Throughput
| Metric | Target | Current |
|--------|--------|---------|
| Feed QPS | 10k | - |
| Event QPS | 1k | - |
| Cache hit rate | ≥ 90% | - |
| Kafka consumer lag | < 10s | - |

---

## 🎯 Success Criteria (Definition of Done)

- [ ] All 4 template files deployed and working
- [ ] Debezium CDC flowing posts/follows/comments/likes into ClickHouse
- [ ] Feed ranking queries execute in < 500ms
- [ ] Hot post cache hits 90%+ within 1 hour
- [ ] 50+ tests passing for social features
- [ ] E2E: Like → Feed ranking update ≤ 5s latency
- [ ] Monitoring dashboards operational
- [ ] Runbooks and deployment guides complete

---

## 📝 Architecture Decisions

### Why ClickHouse for Feed Ranking?
1. **Column-oriented**: Efficient aggregation queries
2. **Materialized Views**: Auto-update metrics without ETL
3. **Fast ranking**: < 500ms for complex scoring
4. **Real-time**: Event streaming via Kafka Engine
5. **Cost-effective**: Better OLAP performance than PostgreSQL

### Why Separate OLTP + OLAP?
1. **Write separation**: PostgreSQL handles transactional writes
2. **Read separation**: ClickHouse handles analytical reads
3. **Scalability**: Each tier scales independently
4. **Performance**: Optimized data structures per use case

### Why 3 Candidate Sources?
1. **F1 (Follow)**: Recent, relevant (highest priority)
2. **F2 (Trending)**: Discovery, viral content
3. **F3 (Affinity)**: Personalization, serendipity
- Balances engagement + discovery + personalization

---

**Next Action**: Implement H1-H2 infrastructure setup (ClickHouse + Kafka topics + Debezium connector)
