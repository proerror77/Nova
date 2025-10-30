-- ClickHouse Feed Candidate Tables
-- These tables store pre-computed feed candidates for fast feed generation
-- They should be populated by ETL jobs from CDC data

-- ============================================
-- 1. Feed candidates from followed users (personalized)
-- ============================================
CREATE TABLE IF NOT EXISTS feed_candidates_followees (
    user_id String,
    post_id String,
    author_id String,
    likes UInt32,
    comments UInt32,
    shares UInt32,
    impressions UInt32,
    freshness_score Float64,
    engagement_score Float64,
    affinity_score Float64,
    combined_score Float64,
    created_at DateTime,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, combined_score, post_id)
SETTINGS index_granularity = 8192;

-- ============================================
-- 2. Feed candidates from trending posts (global)
-- ============================================
CREATE TABLE IF NOT EXISTS feed_candidates_trending (
    post_id String,
    author_id String,
    likes UInt32,
    comments UInt32,
    shares UInt32,
    impressions UInt32,
    freshness_score Float64,
    engagement_score Float64,
    affinity_score Float64,
    combined_score Float64,
    created_at DateTime,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (combined_score, post_id)
SETTINGS index_granularity = 8192;

-- ============================================
-- 3. Feed candidates from affinity (collaborative filtering)
-- ============================================
CREATE TABLE IF NOT EXISTS feed_candidates_affinity (
    user_id String,
    post_id String,
    author_id String,
    likes UInt32,
    comments UInt32,
    shares UInt32,
    impressions UInt32,
    freshness_score Float64,
    engagement_score Float64,
    affinity_score Float64,
    combined_score Float64,
    created_at DateTime,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, affinity_score, post_id)
SETTINGS index_granularity = 8192;

-- ============================================
-- 4. Materialized view for user-author affinity
-- ============================================
-- Replace the regular view with a materialized view for performance

DROP VIEW IF EXISTS user_author_90d;

CREATE MATERIALIZED VIEW IF NOT EXISTS user_author_90d_mv
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(last_interaction)
ORDER BY (user_id, author_id)
POPULATE AS
WITH
  like_events AS (
    SELECT
      user_id,
      post_id,
      created_at AS event_time,
      if(is_deleted = 1, -1.0, 1.0) AS weight
    FROM likes_cdc
    WHERE created_at >= now() - INTERVAL 90 DAY
  ),
  comment_events AS (
    SELECT
      user_id,
      post_id,
      created_at AS event_time,
      if(is_deleted = 1, -2.0, 2.0) AS weight
    FROM comments_cdc
    WHERE created_at >= now() - INTERVAL 90 DAY
  ),
  all_events AS (
    SELECT * FROM like_events
    UNION ALL
    SELECT * FROM comment_events
  )
SELECT
  events.user_id,
  posts_latest.author_id,
  sum(events.weight) AS interaction_count,
  max(events.event_time) AS last_interaction
FROM all_events AS events
INNER JOIN posts_latest ON posts_latest.id = events.post_id
WHERE (posts_latest.is_deleted = 0 OR posts_latest.is_deleted IS NULL)
GROUP BY events.user_id, posts_latest.author_id
HAVING interaction_count > 0;

-- ============================================
-- 5. Materialized view for hourly post metrics
-- ============================================

DROP VIEW IF EXISTS post_metrics_1h;

CREATE MATERIALIZED VIEW IF NOT EXISTS post_metrics_1h_mv
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(metric_hour)
ORDER BY (metric_hour, post_id)
POPULATE AS
WITH
  likes AS (
    SELECT
      toStartOfHour(created_at) AS metric_hour,
      post_id,
      sum(if(is_deleted = 1, -1, 1)) AS likes_count
    FROM likes_cdc
    WHERE created_at >= now() - INTERVAL 90 DAY
    GROUP BY metric_hour, post_id
  ),
  comments AS (
    SELECT
      toStartOfHour(created_at) AS metric_hour,
      post_id,
      sum(if(is_deleted = 1, -1, 1)) AS comments_count
    FROM comments_cdc
    WHERE created_at >= now() - INTERVAL 90 DAY
    GROUP BY metric_hour, post_id
  ),
  union_metrics AS (
    SELECT metric_hour, post_id FROM likes
    UNION ALL
    SELECT metric_hour, post_id FROM comments
  ),
  combined AS (
    SELECT metric_hour, post_id
    FROM union_metrics
    GROUP BY metric_hour, post_id
  )
SELECT
  combined.metric_hour,
  combined.post_id,
  posts_latest.author_id,
  greatest(0, ifNull(likes.likes_count, 0)) AS likes_count,
  greatest(0, ifNull(comments.comments_count, 0)) AS comments_count,
  toInt64(0) AS shares_count,
  toInt64(0) AS impressions_count
FROM combined
LEFT JOIN likes ON likes.metric_hour = combined.metric_hour AND likes.post_id = combined.post_id
LEFT JOIN comments ON comments.metric_hour = combined.metric_hour AND comments.post_id = combined.post_id
LEFT JOIN posts_latest ON posts_latest.id = combined.post_id
WHERE posts_latest.is_deleted = 0 OR posts_latest.is_deleted IS NULL;

-- ============================================
-- 6. Add partitioning to existing CDC tables
-- ============================================

-- NOTE: Cannot add PARTITION BY to existing tables
-- Must recreate tables with partitioning

-- Backup existing tables (optional, for safety)
CREATE TABLE IF NOT EXISTS posts_cdc_backup AS posts_cdc;
CREATE TABLE IF NOT EXISTS follows_cdc_backup AS follows_cdc;
CREATE TABLE IF NOT EXISTS comments_cdc_backup AS comments_cdc;
CREATE TABLE IF NOT EXISTS likes_cdc_backup AS likes_cdc;
CREATE TABLE IF NOT EXISTS post_events_backup AS post_events;

-- Drop existing tables
DROP TABLE IF EXISTS posts_cdc;
DROP TABLE IF EXISTS follows_cdc;
DROP TABLE IF EXISTS comments_cdc;
DROP TABLE IF EXISTS likes_cdc;
DROP TABLE IF EXISTS post_events;

-- Recreate with partitioning
CREATE TABLE IF NOT EXISTS posts_cdc (
  id String,
  user_id String,
  content String,
  media_url Nullable(String),
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, id)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS follows_cdc (
  follower_id String,
  followee_id String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (follower_id, followee_id, created_at)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS comments_cdc (
  id String,
  post_id String,
  user_id String,
  content String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (created_at, id)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS likes_cdc (
  user_id String,
  post_id String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, post_id, created_at)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS post_events (
  event_time DateTime DEFAULT now(),
  event_type String,
  user_id String,
  post_id String DEFAULT ''
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, event_type)
SETTINGS index_granularity = 8192;

-- Restore data from backups
INSERT INTO posts_cdc SELECT * FROM posts_cdc_backup;
INSERT INTO follows_cdc SELECT * FROM follows_cdc_backup;
INSERT INTO comments_cdc SELECT * FROM comments_cdc_backup;
INSERT INTO likes_cdc SELECT * FROM likes_cdc_backup;
INSERT INTO post_events SELECT * FROM post_events_backup;

-- Drop backup tables (optional, can keep for safety)
-- DROP TABLE IF EXISTS posts_cdc_backup;
-- DROP TABLE IF EXISTS follows_cdc_backup;
-- DROP TABLE IF EXISTS comments_cdc_backup;
-- DROP TABLE IF EXISTS likes_cdc_backup;
-- DROP TABLE IF EXISTS post_events_backup;

-- ============================================
-- 7. Optimize partitions and merge settings
-- ============================================

-- Set up partition retention (drop partitions older than 90 days)
-- This should be run periodically via cron or scheduled job
-- Example: ALTER TABLE posts_cdc DROP PARTITION '202310';

-- Optimize tables to merge parts
OPTIMIZE TABLE feed_candidates_followees FINAL;
OPTIMIZE TABLE feed_candidates_trending FINAL;
OPTIMIZE TABLE feed_candidates_affinity FINAL;
OPTIMIZE TABLE posts_cdc FINAL;
OPTIMIZE TABLE follows_cdc FINAL;
OPTIMIZE TABLE comments_cdc FINAL;
OPTIMIZE TABLE likes_cdc FINAL;
OPTIMIZE TABLE post_events FINAL;

-- NOTE: OPTIMIZE FINAL is expensive, should be done during low-traffic periods
-- For production, use OPTIMIZE TABLE without FINAL and let background merges handle it
