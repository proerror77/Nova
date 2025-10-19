-- ClickHouse Schema for Nova CDC and Events
-- Created: 2025-10-18
-- Description: Tables for Change Data Capture (CDC) and application events analytics

-- ========================================
-- CDC Tables (ReplacingMergeTree for upserts)
-- ========================================

-- Posts CDC Table
-- Captures all changes to posts (create, update, delete)
CREATE TABLE IF NOT EXISTS posts_cdc (
    id Int64,
    user_id Int64,
    content String,
    media_url Nullable(String),
    created_at DateTime,
    cdc_timestamp Int64,  -- Debezium transaction timestamp
    is_deleted UInt8,     -- Soft delete flag (1 = deleted)
    _version UInt64 DEFAULT cdc_timestamp  -- ReplacingMergeTree version column
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (id, cdc_timestamp);

-- Follows CDC Table
-- Captures all follow relationships (create, delete)
CREATE TABLE IF NOT EXISTS follows_cdc (
    follower_id Int64,
    followee_id Int64,
    created_at DateTime,
    cdc_timestamp Int64,
    is_deleted UInt8,
    _version UInt64 DEFAULT cdc_timestamp
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (follower_id, followee_id, cdc_timestamp);

-- Comments CDC Table
-- Captures all changes to comments
CREATE TABLE IF NOT EXISTS comments_cdc (
    id Int64,
    post_id Int64,
    user_id Int64,
    content String,
    created_at DateTime,
    cdc_timestamp Int64,
    is_deleted UInt8,
    _version UInt64 DEFAULT cdc_timestamp
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (id, cdc_timestamp);

-- Likes CDC Table
-- Captures all like events
CREATE TABLE IF NOT EXISTS likes_cdc (
    user_id Int64,
    post_id Int64,
    created_at DateTime,
    cdc_timestamp Int64,
    is_deleted UInt8,
    _version UInt64 DEFAULT cdc_timestamp
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, post_id, cdc_timestamp);

-- ========================================
-- Events Table (MergeTree for append-only analytics)
-- ========================================

-- Application Events Table
-- Stores all user behavior events for analytics
CREATE TABLE IF NOT EXISTS events (
    event_id String,        -- Unique event ID (UUID v4)
    event_type String,      -- Event type (e.g., "post_created", "like_added")
    user_id Int64,          -- User who triggered the event
    timestamp Int64,        -- Event timestamp (milliseconds since epoch)
    properties String,      -- Event-specific properties (JSON string)
    _date Date DEFAULT toDate(timestamp / 1000)  -- For partitioning
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(_date)
ORDER BY (event_type, user_id, timestamp);

-- ========================================
-- Indexes for Query Performance
-- ========================================

-- Index on posts_cdc for user timeline queries
ALTER TABLE posts_cdc ADD INDEX idx_user_created (user_id, created_at) TYPE minmax GRANULARITY 3;

-- Index on events for analytics queries
ALTER TABLE events ADD INDEX idx_event_type (event_type) TYPE bloom_filter GRANULARITY 1;
ALTER TABLE events ADD INDEX idx_user_timestamp (user_id, timestamp) TYPE minmax GRANULARITY 3;

-- ========================================
-- Aggregation Tables (for feed ranking)
-- ========================================

-- Post Metrics (1-hour granularity)
-- Aggregates engagement metrics for ranking algorithm
CREATE TABLE IF NOT EXISTS post_metrics_1h (
    post_id Int64,
    author_id Int64,
    metric_hour DateTime,
    likes_count UInt32,
    comments_count UInt32,
    shares_count UInt32,
    impressions_count UInt32,
    watch_time_seconds UInt32,  -- for video content (Phase 4)
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(metric_hour)
ORDER BY (post_id, metric_hour);

-- User-Author Affinity (90-day window)
-- Tracks user interactions with authors for affinity scoring
CREATE TABLE IF NOT EXISTS user_author_90d (
    user_id Int64,
    author_id Int64,
    interaction_count UInt32,
    last_interaction DateTime,
    interaction_score Float32,  -- normalized [0, 1]
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id, author_id);

-- ========================================
-- Materialized Views for Common Queries
-- ========================================

-- Active posts count by user (excluding deleted)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_active_posts_by_user
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at)
AS SELECT
    user_id,
    toDate(created_at) as created_at,
    count() as post_count
FROM posts_cdc
WHERE is_deleted = 0
GROUP BY user_id, created_at;

-- Event counts by type and day
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_event_counts_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_type, event_date)
AS SELECT
    event_type,
    toDate(timestamp / 1000) as event_date,
    count() as event_count
FROM events
GROUP BY event_type, event_date;

-- Post metrics hourly materialized view
-- Aggregates likes, comments, shares from events in 1-hour buckets
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_post_metrics_1h
ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(metric_hour)
ORDER BY (post_id, metric_hour)
AS SELECT
    JSONExtractInt(properties, 'post_id') as post_id,
    JSONExtractInt(properties, 'author_id') as author_id,
    toStartOfHour(fromUnixTimestamp(timestamp / 1000)) as metric_hour,
    countIf(event_type = 'like_added') as likes_count,
    countIf(event_type = 'comment_added') as comments_count,
    countIf(event_type = 'share_added') as shares_count,
    countIf(event_type = 'post_viewed') as impressions_count,
    sum(JSONExtractInt(properties, 'watch_seconds')) as watch_time_seconds,
    now64() as _version
FROM events
WHERE event_type IN ('like_added', 'comment_added', 'share_added', 'post_viewed')
GROUP BY post_id, author_id, metric_hour;

-- User-author affinity materialized view (90-day rolling window)
-- Updates interaction count between users and authors
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_author_90d
ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id, author_id)
AS SELECT
    user_id,
    JSONExtractInt(properties, 'author_id') as author_id,
    count() as interaction_count,
    max(fromUnixTimestamp(timestamp / 1000)) as last_interaction,
    min(1.0, count() / 100.0) as interaction_score,
    now64() as _version
FROM events
WHERE event_type IN ('like_added', 'comment_added', 'post_viewed')
    AND timestamp >= (now64() - 90 * 86400 * 1000)
GROUP BY user_id, author_id;

-- ========================================
-- Query Examples
-- ========================================

-- Get active posts for a user (excluding deleted)
-- SELECT * FROM posts_cdc WHERE user_id = 123 AND is_deleted = 0 ORDER BY created_at DESC LIMIT 20;

-- Get follow relationships for a user
-- SELECT * FROM follows_cdc WHERE follower_id = 123 AND is_deleted = 0;

-- Get event counts by type in last 7 days
-- SELECT event_type, count() as count FROM events
-- WHERE _date >= today() - 7
-- GROUP BY event_type
-- ORDER BY count DESC;

-- Get user activity timeline
-- SELECT event_type, timestamp, properties FROM events
-- WHERE user_id = 123
-- ORDER BY timestamp DESC
-- LIMIT 100;
