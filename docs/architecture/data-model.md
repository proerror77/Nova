# Data Model Documentation: Phase 3 Feed Ranking System

**Version**: 1.0
**Last Updated**: 2025-10-18

---

## Overview

This document describes all data models used in the Phase 3 feed ranking system, including PostgreSQL tables, ClickHouse tables, Redis keys, and Kafka topics.

---

## PostgreSQL Tables (Source of Truth)

### 1. `posts`

**Purpose**: Stores all user posts

```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    content TEXT NOT NULL,
    media_urls TEXT[],
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP,
    is_public BOOLEAN DEFAULT true
);

CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
```

**CDC Sync**: Replicated to ClickHouse `posts_cdc` table via Debezium

---

### 2. `follows`

**Purpose**: User follow relationships

```sql
CREATE TABLE follows (
    follower_id UUID NOT NULL REFERENCES users(id),
    followed_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (follower_id, followed_id)
);

CREATE INDEX idx_follows_follower ON follows(follower_id);
CREATE INDEX idx_follows_followed ON follows(followed_id);
```

**CDC Sync**: Replicated to ClickHouse `follows_cdc` table

---

### 3. `likes`

**Purpose**: Post likes

```sql
CREATE TABLE likes (
    user_id UUID NOT NULL REFERENCES users(id),
    post_id UUID NOT NULL REFERENCES posts(id),
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (user_id, post_id)
);

CREATE INDEX idx_likes_post_id ON likes(post_id);
```

**CDC Sync**: Replicated to ClickHouse `likes_cdc` table

---

### 4. `comments`

**Purpose**: Post comments

```sql
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id),
    user_id UUID NOT NULL REFERENCES users(id),
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP
);

CREATE INDEX idx_comments_post_id ON comments(post_id);
```

**CDC Sync**: Replicated to ClickHouse `comments_cdc` table

---

## ClickHouse Tables (Analytical Database)

### 1. `events` (Raw Events)

**Purpose**: Store all user interaction events

```sql
CREATE TABLE events (
    event_id String,
    event_time DateTime64(3),
    user_id UUID,
    post_id UUID,
    author_id UUID,
    action Enum8(
        'view' = 1,
        'like' = 2,
        'comment' = 3,
        'share' = 4,
        'click' = 5
    ),
    dwell_ms UInt32,
    device Enum8('ios' = 1, 'android' = 2, 'web' = 3),
    app_ver String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (user_id, event_time)
TTL event_time + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;
```

**Indexes**:
- Primary key: `(user_id, event_time)` - optimized for user-specific queries
- Secondary: `(post_id, event_time)` - for post engagement queries

**Partitioning**:
- Daily partitions (`toYYYYMMDD(event_time)`)
- Automatic partition pruning for date-range queries

**TTL**:
- 90-day retention (events older than 90 days are automatically deleted)

**Data Volume**:
- Current: 10M+ rows
- Growth: ~500K events/day
- Disk usage: ~2 GB (compressed)

---

### 2. `posts_cdc` (CDC Sync)

**Purpose**: Mirror of PostgreSQL `posts` table for join queries

```sql
CREATE TABLE posts_cdc (
    id UUID,
    user_id UUID,
    content String,
    media_urls Array(String),
    created_at DateTime,
    updated_at DateTime,
    deleted_at Nullable(DateTime),
    is_public UInt8,
    _version UInt64  -- CDC version for idempotency
)
ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at, id)
SETTINGS index_granularity = 8192;
```

**ReplacingMergeTree**: Deduplicates rows with same primary key, keeps latest `_version`

**Update Frequency**: Real-time (Debezium CDC, typically <2s lag)

---

### 3. `follows_cdc`

```sql
CREATE TABLE follows_cdc (
    follower_id UUID,
    followed_id UUID,
    created_at DateTime,
    _version UInt64
)
ENGINE = ReplacingMergeTree(_version)
ORDER BY (follower_id, followed_id)
SETTINGS index_granularity = 8192;
```

---

### 4. `likes_cdc`

```sql
CREATE TABLE likes_cdc (
    user_id UUID,
    post_id UUID,
    created_at DateTime,
    _version UInt64
)
ENGINE = ReplacingMergeTree(_version)
ORDER BY (post_id, created_at)
SETTINGS index_granularity = 8192;
```

---

### 5. `comments_cdc`

```sql
CREATE TABLE comments_cdc (
    id UUID,
    post_id UUID,
    user_id UUID,
    content String,
    created_at DateTime,
    deleted_at Nullable(DateTime),
    _version UInt64
)
ENGINE = ReplacingMergeTree(_version)
ORDER BY (post_id, created_at)
SETTINGS index_granularity = 8192;
```

---

### 6. `post_metrics_1h` (Materialized View)

**Purpose**: Hourly aggregated post engagement metrics

```sql
CREATE MATERIALIZED VIEW post_metrics_1h
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMMDD(window_start)
ORDER BY (post_id, window_start)
POPULATE
AS
SELECT
    post_id,
    toStartOfHour(event_time) AS window_start,
    countIf(action = 'view') AS impressions,
    countIf(action = 'like') AS likes,
    countIf(action = 'comment') AS comments,
    countIf(action = 'share') AS shares,
    countIf(action = 'click') AS clicks,
    avg(dwell_ms) AS avg_dwell_ms,
    count(DISTINCT user_id) AS unique_users
FROM events
WHERE event_time >= now() - INTERVAL 24 HOUR
GROUP BY post_id, window_start;
```

**Refresh Schedule**: Every 10 minutes (ClickHouse automatic refresh)

**Query Optimization**:
- Pre-aggregated data reduces query time from 3-5s → 200-300ms
- Only stores last 24 hours (older data dropped)

**Example Query**:
```sql
SELECT
    post_id,
    sum(impressions) AS total_impressions,
    sum(likes) AS total_likes,
    sum(comments) AS total_comments
FROM post_metrics_1h
WHERE window_start >= now() - INTERVAL 24 HOUR
GROUP BY post_id
ORDER BY total_likes DESC
LIMIT 100;
```

---

### 7. `user_author_90d` (Affinity Table)

**Purpose**: User-author affinity scores (90-day interaction history)

```sql
CREATE MATERIALIZED VIEW user_author_90d
ENGINE = SummingMergeTree()
ORDER BY (user_id, author_id)
POPULATE
AS
SELECT
    user_id,
    author_id,
    countIf(action IN ('like', 'comment', 'share')) AS interaction_count,
    count() AS total_views,
    max(event_time) AS last_interaction
FROM events
WHERE event_time >= now() - INTERVAL 90 DAY
  AND action IN ('view', 'like', 'comment', 'share')
GROUP BY user_id, author_id
HAVING interaction_count > 0;
```

**Refresh Schedule**: Daily (at 02:00 UTC)

**Purpose in Ranking**:
- `affinity_score = log1p(interaction_count)` in three-dimensional ranking
- Higher interaction count = higher affinity = more likely to rank posts from this author

**Example Query**:
```sql
-- Get user's top 20 most-interacted-with authors
SELECT
    author_id,
    interaction_count,
    total_views,
    last_interaction
FROM user_author_90d
WHERE user_id = '550e8400-e29b-41d4-a716-446655440001'
ORDER BY interaction_count DESC
LIMIT 20;
```

---

## Redis Keys (Cache Layer)

### 1. `feed:v1:{user_id}`

**Purpose**: Cached personalized feed

**Type**: String (JSON)

**Value Format**:
```json
{
  "posts": ["uuid1", "uuid2", ...],
  "cursor": "MTY5ODM3MjAwMA==",
  "has_more": true,
  "generated_at": "2025-10-18T10:15:00Z"
}
```

**TTL**: 5 minutes (300 seconds)

**Invalidation**:
- Automatic (TTL expiration)
- Manual (admin endpoint)

**Example**:
```redis
SETEX feed:v1:550e8400-e29b-41d4-a716-446655440001 300 '{"posts":["..."]}'
GET feed:v1:550e8400-e29b-41d4-a716-446655440001
```

---

### 2. `hot:posts:1h`

**Purpose**: Cached trending posts (1-hour window)

**Type**: String (JSON)

**Value Format**:
```json
{
  "posts": [
    {"post_id": "uuid", "score": 127.5, "likes": 342, ...}
  ],
  "window": "1h",
  "generated_at": "2025-10-18T10:15:00Z"
}
```

**TTL**: 10 minutes (600 seconds)

---

### 3. `suggest:users:{user_id}`

**Purpose**: Cached suggested users

**Type**: String (JSON)

**Value Format**:
```json
{
  "users": [
    {"user_id": "uuid", "affinity_score": 0.85, ...}
  ],
  "generated_at": "2025-10-18T10:15:00Z"
}
```

**TTL**: 1 hour (3600 seconds)

---

### 4. `events:dedup:{event_id}`

**Purpose**: Event deduplication tracker

**Type**: String (value irrelevant, existence checked)

**Value**: `"1"`

**TTL**: 1 hour (3600 seconds)

**Purpose**:
- Prevent duplicate event ingestion
- If key exists, skip event
- If key doesn't exist, insert event + create key

**Example**:
```redis
EXISTS events:dedup:evt_bob_123
  -> 1 (exists, skip event)
  -> 0 (not exists, process event)

SETEX events:dedup:evt_bob_123 3600 "1"
```

---

### 5. `seen:{user_id}`

**Purpose**: Track posts user has already seen

**Type**: Set (of post UUIDs)

**TTL**: 24 hours (86400 seconds)

**Purpose**:
- Avoid showing same post twice in feed
- Deduplicate across pagination

**Example**:
```redis
SADD seen:550e8400-e29b-41d4-a716-446655440001 "post_uuid_1" "post_uuid_2"
SISMEMBER seen:550e8400-e29b-41d4-a716-446655440001 "post_uuid_1"
  -> 1 (seen, skip)
  -> 0 (not seen, include)
```

---

## Kafka Topics (Event Streaming)

### 1. `events`

**Purpose**: User interaction events from clients

**Partitions**: 12

**Replication Factor**: 3

**Retention**: 7 days

**Message Format** (JSON):
```json
{
  "event_id": "evt_550e8400_1698372000",
  "event_time": "2025-10-18T10:15:30Z",
  "user_id": "550e8400-e29b-41d4-a716-446655440001",
  "post_id": "550e8400-e29b-41d4-a716-446655440010",
  "author_id": "550e8400-e29b-41d4-a716-446655440020",
  "action": "like",
  "dwell_ms": 5000,
  "device": "ios",
  "app_ver": "1.2.3"
}
```

**Producers**: Events Handler (`POST /api/v1/events`)

**Consumers**: Events Consumer Service

**Throughput**: ~500 events/sec (peak: 1000/sec)

---

### 2. `cdc.posts`

**Purpose**: PostgreSQL posts table changes (Debezium CDC)

**Partitions**: 6

**Replication Factor**: 3

**Retention**: 3 days

**Message Format** (Debezium):
```json
{
  "schema": {...},
  "payload": {
    "before": null,
    "after": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "user_id": "...",
      "content": "Hello world",
      "created_at": 1698372000000
    },
    "source": {
      "version": "2.0.0.Final",
      "connector": "postgresql",
      "name": "nova-cdc",
      "ts_ms": 1698372000123,
      "db": "nova_prod",
      "schema": "public",
      "table": "posts"
    },
    "op": "c",  // c=create, u=update, d=delete
    "ts_ms": 1698372000123
  }
}
```

**Producers**: Debezium PostgreSQL Connector

**Consumers**: CDC Consumer Service

---

### 3. `cdc.follows`, `cdc.likes`, `cdc.comments`

**Purpose**: CDC for follows, likes, comments tables

**Configuration**: Same as `cdc.posts`

**Message Format**: Same Debezium structure

---

## Data Flow Summary

```
[PostgreSQL]
   ↓ CDC (Debezium)
[Kafka: cdc.*]
   ↓ Consume
[ClickHouse: *_cdc tables]

[Client Apps]
   ↓ POST /events
[Kafka: events]
   ↓ Consume + Dedup (Redis)
[ClickHouse: events]
   ↓ Aggregation (Materialized Views)
[ClickHouse: post_metrics_1h, user_author_90d]

[Feed Ranking Service]
   ↓ Query ClickHouse + Join with CDC tables
   ↓ Apply 3D ranking algorithm
[Redis: feed:v1:{user_id}]
   ↓ Return cached feed
[Client Apps]
```

---

## Data Retention Policies

| Data Store         | Table/Topic         | Retention      | Reason                          |
|--------------------|---------------------|----------------|---------------------------------|
| PostgreSQL         | posts, users, etc.  | Indefinite     | Source of truth                 |
| ClickHouse         | events              | 90 days        | Sufficient for affinity         |
| ClickHouse         | *_cdc               | Indefinite     | Mirror PostgreSQL               |
| ClickHouse         | post_metrics_1h     | 24 hours       | Only recent metrics needed      |
| ClickHouse         | user_author_90d     | 90 days        | Rolling window affinity         |
| Redis              | feed:v1:*           | 5 minutes      | TTL-based cache                 |
| Redis              | events:dedup:*      | 1 hour         | Dedup window                    |
| Kafka              | events              | 7 days         | Replay capability               |
| Kafka              | cdc.*               | 3 days         | CDC sync buffer                 |

---

## Query Patterns

### Pattern 1: Get Personalized Feed

```sql
-- Step 1: Get candidate posts (500)
SELECT
    p.id AS post_id,
    p.created_at,
    pm.impressions,
    pm.likes,
    pm.comments,
    pm.shares,
    ua.interaction_count
FROM posts_cdc p
JOIN follows_cdc f ON p.user_id = f.followed_id
LEFT JOIN post_metrics_1h pm ON p.id = pm.post_id
LEFT JOIN user_author_90d ua ON (ua.user_id = :user_id AND ua.author_id = p.user_id)
WHERE f.follower_id = :user_id
  AND pm.window_start >= now() - INTERVAL 24 HOUR
  AND p.is_public = 1
  AND p.deleted_at IS NULL
ORDER BY p.created_at DESC
LIMIT 500;

-- Step 2: Apply ranking algorithm in application layer
```

### Pattern 2: Get Trending Posts

```sql
SELECT
    post_id,
    sum(likes) AS total_likes,
    sum(comments) AS total_comments,
    sum(shares) AS total_shares,
    sum(impressions) AS total_impressions
FROM post_metrics_1h
WHERE window_start >= now() - INTERVAL 1 HOUR
GROUP BY post_id
HAVING total_impressions > 100  -- Filter low-impression posts
ORDER BY (total_likes + 2*total_comments + 3*total_shares) DESC
LIMIT 200;
```

### Pattern 3: Get User Affinity

```sql
SELECT
    author_id,
    interaction_count,
    total_views,
    last_interaction
FROM user_author_90d
WHERE user_id = :user_id
ORDER BY interaction_count DESC
LIMIT 50;
```

---

## Index Strategy

### ClickHouse Indexes

**Primary Keys** (always indexed):
- `events`: `(user_id, event_time)`
- `posts_cdc`: `(user_id, created_at, id)`
- `post_metrics_1h`: `(post_id, window_start)`

**Secondary Indexes** (ClickHouse doesn't support traditional secondary indexes):
- Use `SKIP INDEX` for selective queries
- Use partitioning for date-based pruning

### PostgreSQL Indexes

**Critical Indexes**:
- `posts(user_id)` - for author post lookups
- `posts(created_at DESC)` - for timeline queries
- `follows(follower_id, followed_id)` - for follow graph
- `likes(post_id)` - for post engagement counts

---

## Data Consistency

**Eventual Consistency Model**:
- PostgreSQL → ClickHouse: Typically <2s lag (CDC)
- Kafka → ClickHouse: <5s lag (event ingestion)
- ClickHouse MV refresh: Up to 10 minutes (post_metrics_1h)

**Idempotency Guarantees**:
- Events Consumer: Redis dedup + ClickHouse ReplacingMergeTree
- CDC Consumer: `_version` field in ReplacingMergeTree

**Conflict Resolution**:
- ClickHouse uses `_version` to keep latest row
- Redis uses last-write-wins (TTL-based)

---

## Backup & Recovery

**PostgreSQL**:
- Continuous WAL archiving to S3
- Point-in-time recovery (PITR) up to 30 days

**ClickHouse**:
- Daily full backups to S3
- Incremental backups every 6 hours
- Retention: 30 days

**Redis**:
- RDB snapshots every 5 minutes
- AOF (Append-Only File) for durability

---

## References

- [Architecture Overview](phase3-overview.md)
- [Ranking Algorithm](ranking-algorithm.md)
- [Operational Runbook](../operations/runbook.md)
