# Phase 3 Architecture Overview: Real-time Personalized Feed Ranking

**Version**: 1.0
**Last Updated**: 2025-10-18
**Status**: Implementation Complete

---

## Executive Summary

Phase 3 introduces a **real-time personalized feed ranking system** that leverages ClickHouse for analytical queries, Kafka for event streaming, and Redis for caching. The system delivers sub-150ms P95 latency for cached feeds and implements a three-dimensional ranking algorithm (freshness + engagement + affinity).

**Key Capabilities**:
- **Real-time Event Processing**: 1000+ events/sec ingestion with <5s event-to-visible latency
- **Personalized Ranking**: Three-dimensional scoring (freshness + engagement + affinity)
- **High Availability**: Circuit breaker pattern with automatic PostgreSQL fallback
- **Deduplication**: >95% accuracy using Redis-based dedup + ClickHouse idempotency
- **Performance**: P95 latency ≤150ms (cache), ≤800ms (ClickHouse query)

---

## System Architecture

### High-Level Components

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Client Applications                              │
│                    (iOS, Android, Web, API Clients)                       │
└─────────────────────────────┬────────────────────────────────────────────┘
                              │
                              │ HTTPS/JSON
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         API Gateway / Load Balancer                       │
│                          (Nginx / AWS ALB)                                │
└─────────────────────────────┬────────────────────────────────────────────┘
                              │
                              │ Rate Limiting + JWT Auth
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                          Nova User Service                                │
│                            (Rust/Actix-Web)                               │
│                                                                            │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                │
│  │ Feed Handler  │  │Events Handler │  │ Discover API  │                │
│  │ GET /feed     │  │POST /events   │  │GET /suggested │                │
│  └───────┬───────┘  └───────┬───────┘  └───────────────┘                │
│          │                   │                                            │
│          │                   │ Produce to Kafka                           │
│          │                   ▼                                            │
│          │          ┌────────────────┐                                    │
│          │          │ Kafka Producer │                                    │
│          │          └────────┬───────┘                                    │
│          │                   │                                            │
│          ▼                   │                                            │
│  ┌──────────────────┐       │                                            │
│  │ Feed Ranking     │       │                                            │
│  │ Service          │       │                                            │
│  │ (3D Algorithm)   │       │                                            │
│  └────┬─────────────┘       │                                            │
│       │ Query CH             │                                            │
│       │ Cache Redis          │                                            │
└───────┼──────────────────────┼────────────────────────────────────────────┘
        │                      │
        │                      │
        ▼                      ▼
┌──────────────┐     ┌──────────────────┐
│ Redis Cache  │     │ Kafka Cluster    │
│ (Feed Cache) │     │ Topics:          │
│ TTL: 5 min   │     │ - events         │
│ Hit Rate:80% │     │ - cdc.posts      │
└──────────────┘     │ - cdc.follows    │
                     │ - cdc.likes      │
                     │ - cdc.comments   │
                     └─────┬────────────┘
                           │
                           │ Consume
                           ▼
        ┌──────────────────────────────────────────┐
        │     Event Processing Pipeline             │
        │                                           │
        │  ┌─────────────────┐  ┌────────────────┐ │
        │  │ CDC Consumer    │  │Events Consumer │ │
        │  │ (Debezium →CH)  │  │ (Events →CH)   │ │
        │  └────────┬────────┘  └────────┬───────┘ │
        │           │                     │         │
        │           │ Insert              │ Insert  │
        │           ▼                     ▼         │
        │      ┌──────────────────────────────┐    │
        │      │  ClickHouse Cluster          │    │
        │      │  (Analytical Database)       │    │
        │      │                               │    │
        │      │  Tables:                      │    │
        │      │  - events (10M+ rows)         │    │
        │      │  - posts_cdc                  │    │
        │      │  - follows_cdc                │    │
        │      │  - likes_cdc                  │    │
        │      │                               │    │
        │      │  Materialized Views:          │    │
        │      │  - post_metrics_1h            │    │
        │      │  - user_author_90d            │    │
        │      └──────────────────────────────┘    │
        └──────────────────────────────────────────┘
                           ▲
                           │ Query
                           │
              ┌────────────┴──────────┐
              │ Feed Ranking Service  │
              └───────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│                     PostgreSQL (Primary Database)                         │
│  Tables: users, posts, follows, likes, comments                           │
│  Role: Source of truth + Fallback for feeds                              │
│  CDC: Debezium captures changes → Kafka                                  │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### 1. API Layer

**Components**:
- **Feed Handler** (`src/handlers/feed.rs`)
  - Endpoint: `GET /api/v1/feed`
  - Handles personalized feed requests
  - Query parameters: `algo`, `limit`, `cursor`
  - Integrates with Feed Ranking Service

- **Events Handler** (`src/handlers/events.rs`)
  - Endpoint: `POST /api/v1/events`
  - Batch event ingestion (up to 1000 events/request)
  - Produces to Kafka `events` topic
  - Returns ingestion metrics

- **Discover Handler** (`src/handlers/discover.rs`)
  - Endpoint: `GET /api/v1/discover/suggested-users`
  - User recommendations based on affinity
  - Powered by ClickHouse user-author affinity table

**Responsibilities**:
- Request validation
- JWT authentication
- Rate limiting (60 req/min per user)
- Response formatting

---

### 2. Feed Ranking Service

**Path**: `src/services/feed_ranking.rs`

**Three-Dimensional Ranking Formula**:
```rust
final_score = 0.30 * freshness + 0.40 * engagement + 0.30 * affinity

where:
  freshness = exp(-0.1 * age_hours)
  engagement = log1p((likes + 2*comments + 3*shares) / max(1, impressions))
  affinity = log1p(user_author_interactions_90d)
```

**Key Features**:
- **Deduplication**: Eliminates duplicate posts (keeps highest-scoring)
- **Saturation Control**: Max 1 post per author in top-5, distance ≥3
- **Circuit Breaker**: Automatic fallback to PostgreSQL if ClickHouse fails
- **Caching**: Redis cache with 5-minute TTL (80%+ hit rate)

**Algorithm Flow**:
```
1. Check Redis cache (key: feed:v1:{user_id})
   └─ HIT: Return cached feed (latency <50ms)
   └─ MISS: Continue to step 2

2. Query ClickHouse for candidate posts (800ms)
   - Join events with post_metrics_1h
   - Join with user_author_90d for affinity
   - Filter: posts from followed authors
   - Limit: 500 candidates

3. Apply three-dimensional ranking
   - Calculate freshness, engagement, affinity
   - Compute weighted final_score
   - Sort by final_score DESC

4. Apply deduplication
   - Group by content_hash (if duplicate content)
   - Keep highest-scoring version

5. Apply saturation control
   - Ensure diversity (max 1 post per author in top-5)
   - Enforce distance constraint (≥3 posts between same author)

6. Cache result in Redis (TTL 5 min)

7. Return top N posts (default 50)
```

---

### 3. Event Processing Pipeline

#### 3.1 CDC Consumer Service

**Path**: `src/services/cdc/consumer.rs`

**Purpose**: Synchronize PostgreSQL changes to ClickHouse via Debezium CDC

**Data Flow**:
```
PostgreSQL (posts, follows, likes, comments)
  ↓ Logical Replication
Debezium Connector (captures changes)
  ↓ Publish to Kafka
Kafka Topics (cdc.posts, cdc.follows, cdc.likes, cdc.comments)
  ↓ Consume
CDC Consumer Service (Rust)
  ↓ Transform & Insert
ClickHouse CDC Tables (posts_cdc, follows_cdc, ...)
```

**Key Features**:
- **Offset Management**: PostgreSQL-backed offset store (no data loss)
- **Idempotency**: Deduplicate by primary key + version
- **Error Handling**: Retry with exponential backoff, dead-letter queue
- **Monitoring**: CDC lag metrics (target: <10s P95)

**CDC Message Format** (Debezium):
```json
{
  "table": "posts",
  "op": "c",  // c=create, u=update, d=delete, r=read
  "ts_ms": 1698372000000,
  "before": null,
  "after": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "user_id": "...",
    "content": "...",
    "created_at": "2025-10-18T10:15:00Z"
  }
}
```

---

#### 3.2 Events Consumer Service

**Path**: `src/services/events/consumer.rs`

**Purpose**: Ingest user interaction events into ClickHouse for ranking

**Data Flow**:
```
Client (iOS/Android/Web)
  ↓ POST /api/v1/events
Events Handler
  ↓ Produce to Kafka
Kafka Topic (events)
  ↓ Consume
Events Consumer Service (Rust)
  ↓ Dedup (Redis) + Insert
ClickHouse events table
```

**Deduplication Strategy**:
```rust
// Redis-based dedup (1-hour TTL)
key = "events:dedup:{event_id}"
if EXISTS key:
    skip_event()
else:
    SETEX key 3600 "1"
    insert_to_clickhouse()
```

**Event Schema**:
```sql
CREATE TABLE events (
    event_id String,
    event_time DateTime64(3),
    user_id UUID,
    post_id UUID,
    author_id UUID,
    action Enum('view', 'like', 'comment', 'share', 'click'),
    dwell_ms UInt32,
    device Enum('ios', 'android', 'web'),
    app_ver String
) ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (user_id, event_time)
TTL event_time + INTERVAL 90 DAY;
```

**Performance**:
- Throughput: 1000+ events/sec
- Dedup Rate: >95%
- Event-to-visible latency: <5s (P95)

---

### 4. ClickHouse Analytical Layer

**Role**: High-performance OLAP database for feed ranking queries

**Tables**:

#### 4.1 `events` (Raw Events)
- **Size**: 10M+ rows (growing)
- **Retention**: 90 days (TTL)
- **Indexes**: Primary key on `(user_id, event_time)`
- **Partitioning**: Daily partitions

#### 4.2 `posts_cdc` (CDC Sync)
- **Source**: PostgreSQL `posts` table
- **Update Frequency**: Real-time (Debezium CDC)
- **Schema**: Mirrors PostgreSQL schema + `_version`

#### 4.3 `follows_cdc`, `likes_cdc`, `comments_cdc`
- **Source**: PostgreSQL via CDC
- **Purpose**: Join with events for ranking

#### 4.4 `post_metrics_1h` (Materialized View)
- **Source**: Aggregated from `events`
- **Update**: Every 10 minutes
- **Schema**:
```sql
CREATE MATERIALIZED VIEW post_metrics_1h
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMMDD(window_start)
ORDER BY (post_id, window_start)
AS
SELECT
    post_id,
    toStartOfHour(event_time) AS window_start,
    countIf(action = 'view') AS impressions,
    countIf(action = 'like') AS likes,
    countIf(action = 'comment') AS comments,
    countIf(action = 'share') AS shares,
    avg(dwell_ms) AS avg_dwell_ms
FROM events
WHERE event_time >= now() - INTERVAL 24 HOUR
GROUP BY post_id, window_start;
```

#### 4.5 `user_author_90d` (Affinity Table)
- **Source**: Aggregated from `events`
- **Update**: Daily
- **Schema**:
```sql
CREATE MATERIALIZED VIEW user_author_90d
ENGINE = SummingMergeTree()
ORDER BY (user_id, author_id)
AS
SELECT
    user_id,
    author_id,
    countIf(action IN ('like', 'comment', 'share')) AS interaction_count,
    count() AS total_views
FROM events
WHERE event_time >= now() - INTERVAL 90 DAY
GROUP BY user_id, author_id
HAVING interaction_count > 0;
```

**Query Optimization**:
- Materialized views reduce query time from 3-5s → 200-300ms
- Hourly aggregation keeps data fresh (10-min update frequency)
- 90-day affinity window balances recency with historical data

---

### 5. Redis Cache Layer

**Purpose**: Reduce ClickHouse load and improve latency

**Keys**:
- `feed:v1:{user_id}` - Personalized feed (TTL: 5 min)
- `hot:posts:1h` - Trending posts (TTL: 10 min)
- `suggest:users:{user_id}` - Suggested users (TTL: 1 hour)
- `events:dedup:{event_id}` - Dedup tracker (TTL: 1 hour)
- `seen:{user_id}` - User-seen posts (TTL: 24 hours)

**Cache Strategy**:
```
Cache-Aside Pattern:

GET /api/v1/feed?user_id=X
  1. Check Redis: GET feed:v1:X
  2. If HIT: return cached feed (latency <50ms)
  3. If MISS:
     - Query ClickHouse (latency 200-800ms)
     - Rank posts with 3D algorithm
     - SETEX feed:v1:X 300 <feed_json>
     - Return feed
```

**Cache Invalidation**:
- **TTL-based**: Automatic expiration after 5 minutes
- **Event-driven** (future): Invalidate on new post from followed user
- **Manual**: Admin endpoint `POST /api/v1/feed/invalidate`

**Performance Metrics**:
- Hit Rate: 80%+ (target)
- Latency (hit): <50ms P95
- Latency (miss): 200-800ms P95

---

### 6. Circuit Breaker & Fallback

**Pattern**: Circuit Breaker with Automatic Fallback

**Implementation**: `src/middleware/circuit_breaker.rs`

**States**:
```
CLOSED (normal operation)
  ↓ ClickHouse errors > threshold (5 failures in 10s)
OPEN (fallback to PostgreSQL)
  ↓ Wait 30s
HALF-OPEN (test ClickHouse)
  ↓ Success → CLOSED
  ↓ Failure → OPEN (wait 60s)
```

**Fallback Logic**:
```rust
match circuit_breaker.state() {
    State::Closed => {
        match query_clickhouse().await {
            Ok(posts) => posts,
            Err(_) => {
                circuit_breaker.record_failure();
                fallback_to_postgres().await?
            }
        }
    },
    State::Open | State::HalfOpen => {
        fallback_to_postgres().await?
    }
}
```

**PostgreSQL Fallback Query**:
```sql
-- Simple time-based feed (no ranking, just recency)
SELECT p.id
FROM posts p
JOIN follows f ON p.user_id = f.followed_id
WHERE f.follower_id = $1
  AND p.created_at < $2  -- cursor
ORDER BY p.created_at DESC
LIMIT $3;
```

**Monitoring**:
- Metric: `feed_circuit_breaker_state{state}` (0=closed, 1=open, 2=half-open)
- Alert: Page on-call if `state=open` for >15 minutes

---

## Data Flow: End-to-End Example

### Scenario: User "Alice" Opens Feed

```
T=0ms:  iOS App → GET /api/v1/feed?user_id=alice&limit=50
        ↓
T=5ms:  API Gateway → JWT auth + rate limiting
        ↓
T=10ms: Feed Handler → Check Redis cache (feed:v1:alice)
        ↓
        [CACHE MISS]
        ↓
T=15ms: Feed Ranking Service → Query ClickHouse
        ↓
        SELECT p.id, pm.impressions, pm.likes, ...
        FROM posts_cdc p
        JOIN follows_cdc f ON p.user_id = f.followed_id
        LEFT JOIN post_metrics_1h pm ON p.id = pm.post_id
        LEFT JOIN user_author_90d ua ON (ua.user_id = 'alice' AND ua.author_id = p.user_id)
        WHERE f.follower_id = 'alice'
          AND pm.window_start >= now() - INTERVAL 24 HOUR
        ORDER BY p.created_at DESC
        LIMIT 500;
        ↓
T=200ms: ClickHouse returns 500 candidate posts
        ↓
T=205ms: Feed Ranking Service → Apply 3D algorithm
        ↓
        For each post:
          freshness = exp(-0.1 * age_hours)
          engagement = log1p((likes + 2*comments + 3*shares) / impressions)
          affinity = log1p(user_author_interactions_90d)
          final_score = 0.3*freshness + 0.4*engagement + 0.3*affinity
        ↓
T=215ms: Sort by final_score DESC → Take top 50
        ↓
T=220ms: Apply deduplication (remove duplicates, keep highest score)
        ↓
T=225ms: Apply saturation (max 1 post per author in top-5)
        ↓
T=230ms: Cache result in Redis (SETEX feed:v1:alice 300 <json>)
        ↓
T=235ms: Return feed to client
        ↓
Total Latency: 235ms (target: <800ms for cache miss)
```

---

### Scenario: User "Bob" Likes a Post

```
T=0ms:  iOS App → POST /api/v1/events
        Body: {
          "event_id": "evt_bob_123",
          "user_id": "bob",
          "post_id": "post_456",
          "action": "like",
          "event_time": "2025-10-18T10:15:30Z"
        }
        ↓
T=10ms: Events Handler → Validate event
        ↓
T=15ms: Kafka Producer → Publish to "events" topic
        ↓
        [Event in Kafka Queue]
        ↓
T=100ms: Events Consumer → Poll Kafka (batch of 100 events)
        ↓
T=105ms: Redis Dedup Check → EXISTS events:dedup:evt_bob_123
        ↓
        [NOT EXISTS → New event]
        ↓
T=110ms: ClickHouse Insert → INSERT INTO events VALUES (...)
        ↓
T=150ms: Redis Dedup Mark → SETEX events:dedup:evt_bob_123 3600 "1"
        ↓
T=160ms: Commit Kafka offset
        ↓
        [Event now visible in ClickHouse]
        ↓
T=600s (10 min): Materialized View Refresh (post_metrics_1h updates)
        ↓
        [Next feed query will include updated engagement metrics]
        ↓
Total Event-to-Visible Latency: ~10 minutes (for aggregated metrics)
                                  <5s (for raw event visibility)
```

---

## Monitoring & Observability

### Key Metrics (Prometheus)

**Feed Performance**:
- `feed_requests_total{endpoint, status, algorithm}`
- `feed_latency_seconds{endpoint, algorithm, percentile}`
- `feed_cache_hit_rate{algorithm}`
- `feed_dedup_rate`

**Event Processing**:
- `events_ingested_total{status}`
- `events_deduped_total`
- `events_consumer_lag_seconds`
- `cdc_consumer_lag_seconds`

**ClickHouse Health**:
- `clickhouse_query_duration_seconds{query_type}`
- `clickhouse_insert_errors_total`
- `clickhouse_connection_pool_active`

**Circuit Breaker**:
- `feed_circuit_breaker_state{state}` (0=closed, 1=open, 2=half-open)
- `feed_fallback_triggered_total`

### Dashboards (Grafana)

1. **Feed Performance Dashboard**
   - P50/P95/P99 latency (cache vs. ClickHouse)
   - Cache hit rate
   - Request rate by endpoint

2. **Event Pipeline Dashboard**
   - Events ingested/sec
   - Dedup rate
   - Kafka consumer lag
   - CDC lag

3. **System Health Dashboard**
   - ClickHouse query performance
   - Redis memory usage
   - PostgreSQL replication lag
   - Circuit breaker state

---

## Scaling Considerations

### Horizontal Scaling

**Component**           | **Current** | **Max Capacity** | **Scaling Strategy**
------------------------|-------------|------------------|----------------------
API Servers             | 3 instances | 20 instances     | Auto-scale on CPU >70%
CDC Consumers           | 1 instance  | 12 instances     | Kafka partition count
Events Consumers        | 1 instance  | 12 instances     | Kafka partition count
ClickHouse Nodes        | 1 node      | 10 nodes         | Sharding + replication
Redis Cluster           | 1 node      | 6 nodes          | Redis Cluster mode
Kafka Brokers           | 3 brokers   | 9 brokers        | Add brokers for throughput

### Vertical Scaling Limits

- **ClickHouse**: 64 CPU cores, 256 GB RAM (single node max)
- **PostgreSQL**: 32 CPU cores, 128 GB RAM (with read replicas)
- **Redis**: 16 GB RAM per node (cluster mode for >100 GB)

---

## Security

**Authentication**: JWT tokens (RSA256)
**Authorization**: Role-based access control (RBAC)
**Encryption**: TLS 1.3 for all traffic
**Data Privacy**: PII data not stored in ClickHouse (only UUIDs)
**Rate Limiting**: 60 req/min per user (sliding window)
**DDoS Protection**: AWS WAF + CloudFront

---

## Disaster Recovery

**RTO**: 15 minutes (Recovery Time Objective)
**RPO**: 5 minutes (Recovery Point Objective)

**Backup Strategy**:
- PostgreSQL: Continuous WAL archiving (S3)
- ClickHouse: Daily snapshots + incremental backups
- Redis: RDB snapshots every 5 minutes

**Failover Procedures**:
- PostgreSQL: Automatic failover to read replica (Patroni)
- ClickHouse: Manual failover to replica (requires DNS update)
- Redis: Redis Sentinel for automatic failover

---

## Future Enhancements (Phase 4+)

1. **Real-time Cache Invalidation**: Subscribe to Kafka events, invalidate feed cache when followed user posts
2. **Machine Learning Ranking**: Replace hand-tuned weights with ML model (train on engagement data)
3. **Multi-Region Deployment**: Deploy ClickHouse clusters in EU/APAC for lower latency
4. **A/B Testing Framework**: Test ranking algorithm variants with controlled experiments
5. **Personalized Trending**: Generate trending posts per user (not global)
6. **Video Feed Support**: Handle video content with different engagement metrics

---

## References

- [Data Model Documentation](data-model.md)
- [Ranking Algorithm Deep Dive](ranking-algorithm.md)
- [Operational Runbook](../operations/runbook.md)
- [Deployment Guide](../deployment/phase3-deployment.md)
