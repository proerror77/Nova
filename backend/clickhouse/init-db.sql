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
SETTINGS index_granularity = 8192;

-- Follows CDC mirror (for feed/trending joins)
CREATE TABLE IF NOT EXISTS follows_cdc (
  follower_id String,
  followee_id String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY (follower_id, followee_id)
SETTINGS index_granularity = 8192;

-- Comments CDC mirror (engagement analytics)
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
SETTINGS index_granularity = 8192;

-- Likes CDC mirror (engagement analytics)
CREATE TABLE IF NOT EXISTS likes_cdc (
  user_id String,
  post_id String,
  created_at DateTime,
  cdc_timestamp UInt64,
  is_deleted UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(cdc_timestamp)
ORDER BY (user_id, post_id, created_at)
SETTINGS index_granularity = 8192;

-- Post events (engagement tracking)
CREATE TABLE IF NOT EXISTS post_events (
  event_time DateTime DEFAULT now(),
  event_type String,
  user_id String,
  post_id String DEFAULT ''
) ENGINE = MergeTree
ORDER BY (event_time, event_type)
SETTINGS index_granularity = 8192;

-- Feed candidate tables (materialized by background job)
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
SETTINGS index_granularity = 8192;

-- Dimension helper for latest, non-deleted posts
CREATE VIEW IF NOT EXISTS posts_latest AS
SELECT
  id,
  anyLast(user_id) AS author_id,
  anyLast(is_deleted) AS is_deleted
FROM posts_cdc
GROUP BY id;

-- Hourly post engagement metrics sourced from CDC tables
CREATE VIEW IF NOT EXISTS post_metrics_1h AS
WITH
  likes AS (
    SELECT
      toStartOfHour(created_at) AS metric_hour,
      post_id,
      sum(if(is_deleted = 1, -1, 1)) AS likes_count
    FROM likes_cdc
    GROUP BY metric_hour, post_id
  ),
  comments AS (
    SELECT
      toStartOfHour(created_at) AS metric_hour,
      post_id,
      sum(if(is_deleted = 1, -1, 1)) AS comments_count
    FROM comments_cdc
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

-- 90-day user ⇄ author affinity view sourced from engagement CDC tables
CREATE VIEW IF NOT EXISTS user_author_90d AS
WITH
  like_events AS (
    SELECT
      user_id,
      post_id,
      created_at AS event_time,
      if(is_deleted = 1, -1.0, 1.0) AS weight
    FROM likes_cdc
  ),
  comment_events AS (
    SELECT
      user_id,
      post_id,
      created_at AS event_time,
      if(is_deleted = 1, -2.0, 2.0) AS weight
    FROM comments_cdc
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
  AND events.event_time >= now() - INTERVAL 90 DAY
GROUP BY events.user_id, posts_latest.author_id
HAVING interaction_count > 0;
