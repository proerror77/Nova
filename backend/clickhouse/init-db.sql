-- ClickHouse Initialization Script
-- Creates all necessary tables for Nova feed ranking system
-- Run this script when ClickHouse starts

-- ==============================================
-- CDC Tables (ReplacingMergeTree for upserts)
-- ==============================================

-- Posts CDC Table
CREATE TABLE IF NOT EXISTS posts_cdc (
    id Int64,
    user_id Int64,
    content String,
    media_url Nullable(String),
    created_at DateTime,
    cdc_timestamp Int64,
    is_deleted UInt8,
    _version UInt64 DEFAULT cdc_timestamp
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (id, cdc_timestamp);

-- Follows CDC Table
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

-- ==============================================
-- Events Table (MergeTree for append-only)
-- ==============================================

CREATE TABLE IF NOT EXISTS events (
    event_id String,
    event_type String,
    user_id Int64,
    timestamp Int64,
    properties String,
    _date Date DEFAULT toDate(timestamp / 1000)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(_date)
ORDER BY (event_type, user_id, timestamp);

-- ==============================================
-- Aggregation Tables (for feed ranking)
-- ==============================================

-- Post Metrics (1-hour granularity)
CREATE TABLE IF NOT EXISTS post_metrics_1h (
    post_id Int64,
    author_id Int64,
    metric_hour DateTime,
    likes_count UInt32,
    comments_count UInt32,
    shares_count UInt32,
    impressions_count UInt32,
    watch_time_seconds UInt32,
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(metric_hour)
ORDER BY (post_id, metric_hour);

-- User-Author Affinity (90-day window)
CREATE TABLE IF NOT EXISTS user_author_90d (
    user_id Int64,
    author_id Int64,
    interaction_count UInt32,
    last_interaction DateTime,
    interaction_score Float32,
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id, author_id);

-- ==============================================
-- Indexes
-- ==============================================

ALTER TABLE posts_cdc ADD INDEX IF NOT EXISTS idx_user_created (user_id, created_at) TYPE minmax GRANULARITY 3;
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_event_type (event_type) TYPE bloom_filter GRANULARITY 1;
ALTER TABLE events ADD INDEX IF NOT EXISTS idx_user_timestamp (user_id, timestamp) TYPE minmax GRANULARITY 3;

-- ==============================================
-- Materialized Views
-- ==============================================

-- Active posts count by user
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

-- Post metrics hourly
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

-- User-author affinity (90-day rolling window)
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

-- ==============================================
-- Video Ranking Tables (Phase 4 Phase 3)
-- ==============================================

-- Video Ranking Signals (1-hour aggregation)
CREATE TABLE IF NOT EXISTS video_ranking_signals_1h (
    video_id UUID,
    hour DateTime,
    completion_rate Float32,
    engagement_score Float32,
    affinity_boost Float32,
    deep_model_score Float32,
    view_count UInt32,
    like_count UInt32,
    share_count UInt32,
    comment_count UInt32,
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, video_id)
TTL hour + INTERVAL 90 DAY;

-- User Watch History (Real-time for deduplication)
CREATE TABLE IF NOT EXISTS user_watch_history_realtime (
    user_id UUID,
    video_id UUID,
    watched_at DateTime,
    completion_percent UInt8,
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id, video_id)
TTL watched_at + INTERVAL 30 DAY;

-- Trending Sounds (Hourly calculation)
CREATE TABLE IF NOT EXISTS trending_sounds_hourly (
    sound_id String,
    hour DateTime,
    video_count UInt32,
    usage_rank UInt32,
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, sound_id)
TTL hour + INTERVAL 90 DAY;

-- Trending Hashtags (Hourly calculation)
CREATE TABLE IF NOT EXISTS trending_hashtags_hourly (
    hashtag String,
    hour DateTime,
    post_count UInt32,
    trend_rank UInt32,
    _version UInt64 DEFAULT now64()
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, hashtag)
TTL hour + INTERVAL 90 DAY;

-- ==============================================
-- Video Ranking Indexes
-- ==============================================

ALTER TABLE video_ranking_signals_1h ADD INDEX IF NOT EXISTS idx_video_hour (video_id, hour) TYPE minmax GRANULARITY 3;
ALTER TABLE user_watch_history_realtime ADD INDEX IF NOT EXISTS idx_user_video (user_id, video_id) TYPE minmax GRANULARITY 1;
ALTER TABLE trending_sounds_hourly ADD INDEX IF NOT EXISTS idx_sound_hour (sound_id, hour) TYPE minmax GRANULARITY 3;
ALTER TABLE trending_hashtags_hourly ADD INDEX IF NOT EXISTS idx_hashtag_hour (hashtag, hour) TYPE minmax GRANULARITY 3;

-- ==============================================
-- Video Ranking Materialized Views
-- ==============================================

-- Video Ranking Signals from Events (1-hour aggregation)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_video_ranking_signals_1h
ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, video_id)
TTL hour + INTERVAL 90 DAY
AS SELECT
    UUID(JSONExtractString(properties, 'video_id')) as video_id,
    toStartOfHour(fromUnixTimestamp(timestamp / 1000)) as hour,
    avg(JSONExtractFloat(properties, 'completion_percent')) / 100.0 as completion_rate,
    countIf(event_type = 'like_added') / max(nullIf(countIf(event_type = 'video_viewed'), 0), 1) as engagement_score,
    0.0 as affinity_boost,
    0.0 as deep_model_score,
    countIf(event_type = 'video_viewed') as view_count,
    countIf(event_type = 'like_added') as like_count,
    countIf(event_type = 'share_added') as share_count,
    countIf(event_type = 'comment_added') as comment_count,
    now64() as _version
FROM events
WHERE event_type IN ('like_added', 'comment_added', 'share_added', 'video_viewed', 'video_completed')
GROUP BY video_id, hour;

-- Trending Sounds from Video Events
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_trending_sounds_hourly
ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, sound_id)
TTL hour + INTERVAL 90 DAY
AS SELECT
    JSONExtractString(properties, 'sound_id') as sound_id,
    toStartOfHour(fromUnixTimestamp(timestamp / 1000)) as hour,
    count(DISTINCT JSONExtractString(properties, 'video_id')) as video_count,
    dense_rank() OVER (PARTITION BY hour ORDER BY count(DISTINCT JSONExtractString(properties, 'video_id')) DESC) as usage_rank,
    now64() as _version
FROM events
WHERE event_type IN ('video_created', 'video_viewed')
    AND JSONExtractString(properties, 'sound_id') != ''
    AND timestamp >= (now64() - 24 * 3600 * 1000)
GROUP BY sound_id, hour;

-- Trending Hashtags from Video Events
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_trending_hashtags_hourly
ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMMDD(hour)
ORDER BY (hour, hashtag)
TTL hour + INTERVAL 90 DAY
AS SELECT
    arrayJoin(splitByString(',', JSONExtractString(properties, 'hashtags'))) as hashtag,
    toStartOfHour(fromUnixTimestamp(timestamp / 1000)) as hour,
    count(DISTINCT JSONExtractString(properties, 'video_id')) as post_count,
    dense_rank() OVER (PARTITION BY hour ORDER BY count(DISTINCT JSONExtractString(properties, 'video_id')) DESC) as trend_rank,
    now64() as _version
FROM events
WHERE event_type IN ('video_created', 'video_viewed')
    AND JSONExtractString(properties, 'hashtags') != ''
    AND timestamp >= (now64() - 24 * 3600 * 1000)
GROUP BY hashtag, hour;
