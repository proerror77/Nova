-- ClickHouse CDC Tables for Content Service
-- This schema should be executed on ClickHouse (not PostgreSQL)
-- Migration: 20251201_create_clickhouse_cdc_tables
-- Description: Create CDC tables for posts, likes, comments, and follows for analytics

-- Posts CDC Table (ReplacingMergeTree for deduplication)
CREATE TABLE IF NOT EXISTS posts_cdc (
    id UUID,
    user_id UUID,
    content String,
    media_key String,
    media_type String,
    created_at DateTime64(3) DEFAULT now64(3),
    updated_at DateTime64(3) DEFAULT now64(3),
    deleted_at Nullable(DateTime64(3)),
    -- CDC metadata
    cdc_operation Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3),
    cdc_timestamp DateTime64(3) DEFAULT now64(3),
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_created_at (created_at) TYPE minmax GRANULARITY 1
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- Likes CDC Table (SummingMergeTree for aggregation)
CREATE TABLE IF NOT EXISTS likes_cdc (
    post_id UUID,
    user_id UUID,
    created_at DateTime64(3) DEFAULT now64(3),
    -- CDC metadata
    cdc_operation Enum8('INSERT' = 1, 'DELETE' = 2),
    cdc_timestamp DateTime64(3) DEFAULT now64(3),
    -- For SummingMergeTree: +1 for INSERT, -1 for DELETE
    likes_count Int8,
    INDEX idx_post_id (post_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree((likes_count))
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, user_id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- Comments CDC Table (ReplacingMergeTree for deduplication)
CREATE TABLE IF NOT EXISTS comments_cdc (
    id UUID,
    post_id UUID,
    user_id UUID,
    content String,
    parent_comment_id Nullable(UUID),
    created_at DateTime64(3) DEFAULT now64(3),
    updated_at DateTime64(3) DEFAULT now64(3),
    soft_delete Nullable(DateTime64(3)),
    -- CDC metadata
    cdc_operation Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3),
    cdc_timestamp DateTime64(3) DEFAULT now64(3),
    INDEX idx_post_id (post_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_parent_comment_id (parent_comment_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- Follows CDC Table (for social graph analytics)
CREATE TABLE IF NOT EXISTS follows_cdc (
    follower_id UUID,
    followee_id UUID,  -- The user being followed
    created_at DateTime64(3) DEFAULT now64(3),
    -- CDC metadata
    cdc_operation Enum8('INSERT' = 1, 'DELETE' = 2),
    cdc_timestamp DateTime64(3) DEFAULT now64(3),
    -- For SummingMergeTree: +1 for INSERT, -1 for DELETE
    follow_count Int8,
    INDEX idx_follower_id (follower_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_followee_id (followee_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree((follow_count))
PARTITION BY toYYYYMM(created_at)
ORDER BY (followee_id, follower_id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- Materialized view for post engagement statistics (hourly aggregation)
CREATE MATERIALIZED VIEW IF NOT EXISTS post_engagement_hourly
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (post_id, hour)
AS SELECT
    post_id,
    toStartOfHour(cdc_timestamp) AS hour,
    countIf(cdc_operation = 'INSERT') AS new_likes,
    countIf(cdc_operation = 'DELETE') AS removed_likes
FROM likes_cdc
GROUP BY post_id, hour;

-- Materialized view for user activity statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS user_activity_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (user_id, day)
AS SELECT
    user_id,
    toStartOfDay(created_at) AS day,
    count() AS posts_count
FROM posts_cdc
WHERE cdc_operation = 'INSERT'
GROUP BY user_id, day;

-- Materialized view for follower growth tracking
CREATE MATERIALIZED VIEW IF NOT EXISTS follower_growth_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (followee_id, day)
AS SELECT
    followee_id AS user_id,
    toStartOfDay(cdc_timestamp) AS day,
    sum(follow_count) AS net_followers
FROM follows_cdc
GROUP BY followee_id, day;

-- Sample queries:
-- 1. Get total likes for a post:
--    SELECT post_id, sum(likes_count) as total_likes FROM likes_cdc
--    WHERE post_id = 'uuid' GROUP BY post_id

-- 2. Get user's post count by day:
--    SELECT day, sum(posts_count) as total_posts FROM user_activity_daily
--    WHERE user_id = 'uuid' AND day >= today() - 30
--    GROUP BY day ORDER BY day

-- 3. Get follower growth for a user:
--    SELECT day, sum(net_followers) as followers_gained FROM follower_growth_daily
--    WHERE user_id = 'uuid' AND day >= today() - 30
--    GROUP BY day ORDER BY day

-- 4. Get engagement metrics for posts in a time range:
--    SELECT post_id, sum(new_likes) as total_new_likes FROM post_engagement_hourly
--    WHERE hour >= now() - INTERVAL 24 HOUR
--    GROUP BY post_id ORDER BY total_new_likes DESC LIMIT 10
