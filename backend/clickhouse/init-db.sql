-- ClickHouse initialization for Nova analytics
-- Database: nova_feed (set via CLICKHOUSE_DB env var)

-- Ensure we're using the correct database
CREATE DATABASE IF NOT EXISTS nova_feed;
USE nova_feed;

-- Events stream (generic)
CREATE TABLE IF NOT EXISTS events (
  event_id String,
  event_type String,
  user_id Int64,
  timestamp Int64,
  properties String
) ENGINE = MergeTree
ORDER BY (timestamp, event_type)
SETTINGS index_granularity = 8192;

-- Posts CDC mirror (feed + analytics source of truth)
-- TTL: 1 year retention for posts data
CREATE TABLE IF NOT EXISTS posts_cdc (
  id String,
  user_id String,
  content String,
  media_url Nullable(String),
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY id
TTL created_at + INTERVAL 1 YEAR
SETTINGS index_granularity = 8192;

-- Follows CDC mirror (for feed/trending joins)
-- TTL: 2 years retention for social graph data
-- Note: followee_id = the user being followed (PostgreSQL uses following_id)
CREATE TABLE IF NOT EXISTS follows_cdc (
  follower_id String,
  followee_id String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0,
  follow_count Int8 DEFAULT 1
) ENGINE = SummingMergeTree((follow_count))
ORDER BY (follower_id, followee_id)
TTL created_at + INTERVAL 2 YEAR
SETTINGS index_granularity = 8192;

-- Comments CDC mirror (engagement analytics)
-- TTL: 1 year retention for comments
CREATE TABLE IF NOT EXISTS comments_cdc (
  id String,
  post_id String,
  user_id String,
  content String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY id
TTL created_at + INTERVAL 1 YEAR
SETTINGS index_granularity = 8192;

-- Likes CDC mirror (engagement analytics)
-- TTL: 1 year retention for likes
CREATE TABLE IF NOT EXISTS likes_cdc (
  user_id String,
  post_id String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY (user_id, post_id, created_at)
TTL created_at + INTERVAL 1 YEAR
SETTINGS index_granularity = 8192;

-- Post events (engagement tracking)
-- TTL: 90 days retention for event stream
CREATE TABLE IF NOT EXISTS post_events (
  event_time DateTime DEFAULT now(),
  event_type String,
  user_id String,
  post_id String DEFAULT ''
) ENGINE = MergeTree
ORDER BY (event_time, event_type)
TTL event_time + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Feed candidate tables (materialized by background job)
-- TTL: 30 days retention for feed candidates (refreshed frequently)
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
TTL created_at + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- TTL: 30 days retention for trending candidates
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
TTL created_at + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- TTL: 30 days retention for affinity candidates
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
ORDER BY (user_id, combined_score, post_id)
TTL created_at + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- Dimension helper for latest, non-deleted posts
CREATE VIEW IF NOT EXISTS posts_latest AS
SELECT
  id,
  anyLast(user_id) AS author_id,
  anyLast(is_deleted) AS is_deleted
FROM posts_cdc
GROUP BY id;

-- ============================================================================
-- MATERIALIZED VIEWS FOR REAL-TIME METRICS
-- ============================================================================

-- Target table for hourly likes metrics (incremental)
CREATE TABLE IF NOT EXISTS post_likes_hourly (
  metric_hour DateTime,
  post_id String,
  likes_delta Int64,
  updated_at DateTime DEFAULT now()
) ENGINE = SummingMergeTree(likes_delta)
ORDER BY (metric_hour, post_id)
TTL metric_hour + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Materialized view: incrementally aggregate likes by hour
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_post_likes_hourly
TO post_likes_hourly AS
SELECT
  toStartOfHour(created_at) AS metric_hour,
  post_id,
  if(is_deleted = 1, -1, 1) AS likes_delta,
  now() AS updated_at
FROM likes_cdc;

-- Target table for hourly comments metrics (incremental)
CREATE TABLE IF NOT EXISTS post_comments_hourly (
  metric_hour DateTime,
  post_id String,
  comments_delta Int64,
  updated_at DateTime DEFAULT now()
) ENGINE = SummingMergeTree(comments_delta)
ORDER BY (metric_hour, post_id)
TTL metric_hour + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Materialized view: incrementally aggregate comments by hour
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_post_comments_hourly
TO post_comments_hourly AS
SELECT
  toStartOfHour(created_at) AS metric_hour,
  post_id,
  if(is_deleted = 1, -1, 1) AS comments_delta,
  now() AS updated_at
FROM comments_cdc;

-- Target table for user-author affinity (incremental)
CREATE TABLE IF NOT EXISTS user_author_affinity (
  user_id String,
  author_id String,
  affinity_delta Float64,
  event_time DateTime,
  updated_at DateTime DEFAULT now()
) ENGINE = SummingMergeTree(affinity_delta)
ORDER BY (user_id, author_id)
TTL event_time + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- Materialized view: incrementally track user-author likes affinity
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_author_likes
TO user_author_affinity AS
SELECT
  l.user_id AS user_id,
  p.user_id AS author_id,
  if(l.is_deleted = 1, -1.0, 1.0) AS affinity_delta,
  l.created_at AS event_time,
  now() AS updated_at
FROM likes_cdc l
INNER JOIN posts_cdc p ON p.id = l.post_id;

-- Materialized view: incrementally track user-author comments affinity
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_author_comments
TO user_author_affinity AS
SELECT
  c.user_id AS user_id,
  p.user_id AS author_id,
  if(c.is_deleted = 1, -2.0, 2.0) AS affinity_delta,
  c.created_at AS event_time,
  now() AS updated_at
FROM comments_cdc c
INNER JOIN posts_cdc p ON p.id = c.post_id;

-- ============================================================================
-- QUERY VIEWS (use materialized data for fast queries)
-- ============================================================================

-- Hourly post engagement metrics (reads from materialized tables)
CREATE VIEW IF NOT EXISTS post_metrics_1h AS
SELECT
  coalesce(l.metric_hour, c.metric_hour) AS metric_hour,
  coalesce(l.post_id, c.post_id) AS post_id,
  p.author_id,
  greatest(0, coalesce(l.likes_count, 0)) AS likes_count,
  greatest(0, coalesce(c.comments_count, 0)) AS comments_count,
  toInt64(0) AS shares_count,
  toInt64(0) AS impressions_count
FROM (
  SELECT metric_hour, post_id, sum(likes_delta) AS likes_count
  FROM post_likes_hourly
  GROUP BY metric_hour, post_id
) l
FULL OUTER JOIN (
  SELECT metric_hour, post_id, sum(comments_delta) AS comments_count
  FROM post_comments_hourly
  GROUP BY metric_hour, post_id
) c ON l.metric_hour = c.metric_hour AND l.post_id = c.post_id
LEFT JOIN posts_latest p ON p.id = coalesce(l.post_id, c.post_id)
WHERE p.is_deleted = 0 OR p.is_deleted IS NULL;

-- 90-day user ⇄ author affinity (reads from materialized table)
CREATE VIEW IF NOT EXISTS user_author_90d AS
SELECT
  user_id,
  author_id,
  sum(affinity_delta) AS interaction_count,
  max(event_time) AS last_interaction
FROM user_author_affinity
WHERE event_time >= now() - INTERVAL 90 DAY
GROUP BY user_id, author_id
HAVING interaction_count > 0;
