-- ============================================================================
-- Nova ClickHouse CDC Schema - Single Source of Truth
-- ============================================================================
-- This file contains the canonical CDC table definitions for the Nova platform.
-- All CDC tables should be created using this schema.
--
-- Schema Mapping (PostgreSQL → ClickHouse):
--   follows.following_id → follows_cdc.followee_id
--
-- Last Updated: 2024-12-19
-- ============================================================================

-- Ensure database exists
CREATE DATABASE IF NOT EXISTS nova_feed;
USE nova_feed;

-- ============================================================================
-- POSTS CDC TABLE
-- ============================================================================
-- Source: PostgreSQL content-service.posts
-- Engine: ReplacingMergeTree for deduplication by cdc_timestamp
-- ============================================================================
CREATE TABLE IF NOT EXISTS posts_cdc (
    id UUID,
    user_id UUID,
    content String,
    media_key String DEFAULT '',
    media_type String DEFAULT '',
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    deleted_at Nullable(DateTime),
    is_deleted UInt8 DEFAULT 0,
    -- CDC metadata
    cdc_operation Int8,
    cdc_timestamp DateTime DEFAULT now(),
    media_url Nullable(String),
    -- Indexes
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_created_at (created_at) TYPE minmax GRANULARITY 1
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- ============================================================================
-- FOLLOWS CDC TABLE
-- ============================================================================
-- Source: PostgreSQL graph-service.follows
-- Engine: SummingMergeTree for aggregation (+1 follow, -1 unfollow)
-- Note: PostgreSQL uses 'following_id', ClickHouse uses 'followee_id'
-- ============================================================================
CREATE TABLE IF NOT EXISTS follows_cdc (
    follower_id String,
    followee_id String,  -- Maps from PostgreSQL following_id
    created_at DateTime DEFAULT now(),
    -- CDC metadata
    cdc_operation Int8,
    cdc_timestamp DateTime DEFAULT now(),
    -- For SummingMergeTree: +1 for INSERT, -1 for DELETE
    follow_count Int8,
    -- Indexes
    INDEX idx_follower_id (follower_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_followee_id (followee_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree((follow_count))
PARTITION BY toYYYYMM(created_at)
ORDER BY (followee_id, follower_id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- ============================================================================
-- COMMENTS CDC TABLE
-- ============================================================================
-- Source: PostgreSQL content-service.comments
-- Engine: ReplacingMergeTree for deduplication by cdc_timestamp
-- ============================================================================
CREATE TABLE IF NOT EXISTS comments_cdc (
    id String,
    post_id String,
    user_id String,
    content String,
    parent_comment_id String,
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    soft_delete DateTime DEFAULT toDateTime(0),
    -- CDC metadata
    cdc_operation Int8,
    cdc_timestamp DateTime DEFAULT now(),
    -- Indexes
    INDEX idx_post_id (post_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_parent_comment_id (parent_comment_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- ============================================================================
-- LIKES CDC TABLE
-- ============================================================================
-- Source: PostgreSQL social-service.likes
-- Engine: SummingMergeTree for aggregation (+1 like, -1 unlike)
-- ============================================================================
CREATE TABLE IF NOT EXISTS likes_cdc (
    post_id String,
    user_id String,
    created_at DateTime DEFAULT now(),
    -- CDC metadata
    cdc_operation Int8,
    cdc_timestamp DateTime DEFAULT now(),
    -- For SummingMergeTree: +1 for INSERT, -1 for DELETE
    like_count Int8,
    -- Indexes
    INDEX idx_post_id (post_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree((like_count))
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, user_id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- ============================================================================
-- USERS CDC TABLE (for nova_auth database)
-- ============================================================================
-- Source: PostgreSQL identity-service.users
-- Engine: ReplacingMergeTree for deduplication
-- ============================================================================
CREATE TABLE IF NOT EXISTS users_cdc (
    id UUID,
    username String,
    display_name String DEFAULT '',
    email String DEFAULT '',
    avatar_url String DEFAULT '',
    bio String DEFAULT '',
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    deleted_at Nullable(DateTime),
    -- CDC metadata
    cdc_operation Int8,
    cdc_timestamp DateTime DEFAULT now(),
    -- Indexes
    INDEX idx_username (username) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_created_at (created_at) TYPE minmax GRANULARITY 1
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (id, cdc_timestamp)
TTL created_at + INTERVAL 730 DAY;  -- 2 years for user data

-- ============================================================================
-- MATERIALIZED VIEWS
-- ============================================================================

-- Post engagement hourly aggregation
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_post_engagement_hourly
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (post_id, hour)
AS SELECT
    post_id,
    toStartOfHour(cdc_timestamp) AS hour,
    countIf(cdc_operation = 1) AS new_likes,
    countIf(cdc_operation = 2) AS removed_likes
FROM likes_cdc
GROUP BY post_id, hour;

-- User activity daily aggregation
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_activity_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (user_id, day)
AS SELECT
    user_id,
    toStartOfDay(created_at) AS day,
    count() AS posts_count
FROM posts_cdc
WHERE cdc_operation = 1
GROUP BY user_id, day;

-- Follower growth daily tracking
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_follower_growth_daily
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (user_id, day)
AS SELECT
    followee_id AS user_id,
    toStartOfDay(cdc_timestamp) AS day,
    sum(follow_count) AS net_followers
FROM follows_cdc
GROUP BY followee_id, day;

-- ============================================================================
-- QUERY VIEWS
-- ============================================================================

-- Latest non-deleted posts
CREATE VIEW IF NOT EXISTS v_posts_latest AS
SELECT
    id,
    argMax(user_id, cdc_timestamp) AS author_id,
    argMax(content, cdc_timestamp) AS content,
    argMax(media_key, cdc_timestamp) AS media_key,
    argMax(created_at, cdc_timestamp) AS created_at,
    argMax(deleted_at, cdc_timestamp) AS deleted_at,
    max(cdc_timestamp) AS last_updated
FROM posts_cdc
GROUP BY id
HAVING deleted_at IS NULL;

-- User follower counts
CREATE VIEW IF NOT EXISTS v_user_follower_counts AS
SELECT
    followee_id AS user_id,
    sum(follow_count) AS follower_count
FROM follows_cdc
GROUP BY followee_id
HAVING follower_count > 0;

-- Post engagement totals
CREATE VIEW IF NOT EXISTS v_post_engagement AS
SELECT
    post_id,
    sum(like_count) AS total_likes
FROM likes_cdc
GROUP BY post_id
HAVING total_likes > 0;
