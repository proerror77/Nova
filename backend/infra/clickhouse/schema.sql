-- ============================================
-- ClickHouse OLAP Schema for Real-Time Analytics
-- Version: 1.0.0
-- Date: 2025-10-18
-- Purpose: Event tracking, feed ranking, user affinity
-- ============================================

-- ============================================
-- Database Setup
-- ============================================
CREATE DATABASE IF NOT EXISTS nova_analytics;
USE nova_analytics;

-- ============================================
-- 1. Raw Events Table (MergeTree)
-- Purpose: Store all user interaction events
-- Retention: 90 days
-- Expected volume: 10M events/day @ scale
-- ============================================
CREATE TABLE IF NOT EXISTS events (
  event_id UUID,
  user_id UUID,
  post_id Nullable(UUID),
  event_type LowCardinality(String),  -- impression, view, like, comment, share, click
  author_id Nullable(UUID),
  dwell_ms Nullable(UInt32),          -- Time spent viewing (milliseconds)
  created_at DateTime,
  event_date Date MATERIALIZED toDate(created_at)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (event_date, user_id, created_at)
TTL created_at + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 2. Posts Dimension Table (ReplacingMergeTree)
-- Purpose: Synced from PostgreSQL via CDC (Debezium)
-- Source: PostgreSQL posts table
-- ============================================
CREATE TABLE IF NOT EXISTS posts (
  id UUID,
  user_id UUID,
  caption String,
  image_key String,
  status LowCardinality(String),     -- pending, processing, published, failed
  created_at DateTime,
  updated_at DateTime,
  soft_delete Nullable(DateTime),
  __op LowCardinality(String),       -- c (create), u (update), d (delete)
  __deleted UInt8 DEFAULT 0,
  __version UInt64                   -- For deduplication
) ENGINE = ReplacingMergeTree(__version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (id, created_at)
SETTINGS index_granularity = 8192;

-- ============================================
-- 3. Follows Dimension Table (ReplacingMergeTree)
-- Purpose: Synced from PostgreSQL via CDC
-- Source: PostgreSQL follows table
-- ============================================
CREATE TABLE IF NOT EXISTS follows (
  id UUID,
  follower_id UUID,
  following_id UUID,
  created_at DateTime,
  __op LowCardinality(String),
  __deleted UInt8 DEFAULT 0,
  __version UInt64
) ENGINE = ReplacingMergeTree(__version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (follower_id, following_id, created_at)
SETTINGS index_granularity = 8192;

-- ============================================
-- 4. Comments Dimension Table (ReplacingMergeTree)
-- Purpose: Synced from PostgreSQL via CDC
-- Source: PostgreSQL comments table
-- ============================================
CREATE TABLE IF NOT EXISTS comments (
  id UUID,
  post_id UUID,
  user_id UUID,
  content String,
  parent_comment_id Nullable(UUID),
  created_at DateTime,
  updated_at DateTime,
  soft_delete Nullable(DateTime),
  __op LowCardinality(String),
  __deleted UInt8 DEFAULT 0,
  __version UInt64
) ENGINE = ReplacingMergeTree(__version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, created_at, id)
SETTINGS index_granularity = 8192;

-- ============================================
-- 5. Likes Dimension Table (ReplacingMergeTree)
-- Purpose: Synced from PostgreSQL via CDC
-- Source: PostgreSQL likes table
-- ============================================
CREATE TABLE IF NOT EXISTS likes (
  id UUID,
  user_id UUID,
  post_id UUID,
  created_at DateTime,
  __op LowCardinality(String),
  __deleted UInt8 DEFAULT 0,
  __version UInt64
) ENGINE = ReplacingMergeTree(__version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, user_id, created_at)
SETTINGS index_granularity = 8192;

-- ============================================
-- 6. Post Metrics Aggregation (SummingMergeTree)
-- Purpose: Hourly aggregated metrics per post
-- Retention: 30 days
-- Query pattern: Get metrics for feed ranking
-- ============================================
CREATE TABLE IF NOT EXISTS post_metrics_1h (
  post_id UUID,
  author_id UUID,
  metric_hour DateTime,
  likes_count UInt32,
  comments_count UInt32,
  shares_count UInt32,
  impressions_count UInt32,
  views_count UInt32,
  avg_dwell_ms Float32,
  unique_viewers AggregateFunction(uniq, UUID),
  updated_at DateTime DEFAULT now()
) ENGINE = SummingMergeTree((likes_count, comments_count, shares_count, impressions_count, views_count))
PARTITION BY toYYYYMM(metric_hour)
ORDER BY (post_id, metric_hour)
TTL metric_hour + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 7. User-Author Affinity (ReplacingMergeTree)
-- Purpose: Track user interaction patterns with authors
-- Window: 90 days rolling
-- Query pattern: Personalized feed ranking
-- ============================================
CREATE TABLE IF NOT EXISTS user_author_affinity (
  user_id UUID,
  author_id UUID,
  interaction_count UInt32,
  last_interaction DateTime,
  like_count UInt32,
  comment_count UInt32,
  view_count UInt32,
  share_count UInt32,
  avg_dwell_ms Float32,
  follows_author UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree(last_interaction)
PARTITION BY toYYYYMM(last_interaction)
ORDER BY (user_id, author_id)
TTL last_interaction + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 8. Hot Posts Cache (ReplacingMergeTree)
-- Purpose: Pre-computed top posts for discovery feed
-- Refresh: Every hour
-- Retention: 2 days
-- ============================================
CREATE TABLE IF NOT EXISTS hot_posts (
  post_id UUID,
  author_id UUID,
  score Float32,
  likes UInt32,
  comments UInt32,
  shares UInt32,
  impressions UInt32,
  created_at DateTime,
  collected_at DateTime
) ENGINE = ReplacingMergeTree(collected_at)
PARTITION BY toDate(collected_at)
ORDER BY (collected_at, score)
TTL collected_at + INTERVAL 2 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- Index Strategy Comments
-- ============================================
-- ORDER BY choices are critical for query performance:
--
-- events: (event_date, user_id, created_at)
--   - Range queries on date are most common
--   - User-level filtering is primary use case
--   - Chronological order for time-series analysis
--
-- posts: (id, created_at)
--   - Lookup by post_id (primary key)
--   - Temporal filtering for recent posts
--
-- follows: (follower_id, following_id, created_at)
--   - Get all followings for a user (feed generation)
--   - Reverse lookup for follower lists
--
-- post_metrics_1h: (post_id, metric_hour)
--   - Aggregate metrics per post
--   - Time-range queries for trending analysis
--
-- user_author_affinity: (user_id, author_id)
--   - Personalized ranking (user-centric queries)
--   - Author lookup for discovery

-- ============================================
-- Partition Strategy Comments
-- ============================================
-- Monthly partitions (toYYYYMM) for all tables:
--   - Balance between partition count and data per partition
--   - Efficient DROP PARTITION for TTL enforcement
--   - Optimal for 90-day retention windows
--
-- Daily partitions (toDate) only for hot_posts:
--   - Short retention (2 days) requires finer granularity
--   - Frequent updates/replacements

-- ============================================
-- TTL (Time-To-Live) Policy
-- ============================================
-- events: 90 days
--   - Keeps raw events for user behavior analysis
--   - Balances storage cost vs analytical value
--
-- posts/follows/comments/likes: No TTL
--   - Dimension data retained indefinitely
--   - Soft deletes handled via __deleted flag
--
-- post_metrics_1h: 30 days
--   - Aggregated metrics for recent content only
--   - Older posts use cold storage or archival
--
-- user_author_affinity: 90 days
--   - Matches events retention window
--   - Ensures consistency for scoring calculations
--
-- hot_posts: 2 days
--   - Real-time cache, refreshed hourly
--   - No need for historical hot lists

-- ============================================
-- Performance Optimization Notes
-- ============================================
-- 1. LowCardinality for enum-like fields:
--    - event_type, status, __op
--    - Reduces storage by 80%+ for these columns
--    - Faster filtering and aggregation
--
-- 2. MATERIALIZED columns:
--    - event_date calculated from created_at
--    - Avoids runtime computation in queries
--
-- 3. index_granularity = 8192 (default):
--    - Good balance for most workloads
--    - Adjust to 1024 for very selective queries
--    - Adjust to 65536 for large scans
--
-- 4. ReplacingMergeTree for CDC:
--    - Handles out-of-order updates
--    - Deduplication via __version
--    - Query with FINAL for latest state
--
-- 5. SummingMergeTree for metrics:
--    - Auto-aggregates on merge
--    - Significantly reduces storage for counters
--    - Query with sum() for accurate totals

-- ============================================
-- Query Patterns & Expected Performance
-- ============================================
-- Q1: Get post metrics for feed ranking (50 posts)
--     Expected: P95 < 100ms
--     SELECT post_id, sum(likes_count), sum(views_count)
--     FROM post_metrics_1h
--     WHERE post_id IN (...)
--     GROUP BY post_id
--
-- Q2: Get user affinity for personalized ranking
--     Expected: P95 < 50ms
--     SELECT author_id, interaction_count, avg_dwell_ms
--     FROM user_author_affinity
--     WHERE user_id = ?
--     ORDER BY last_interaction DESC
--
-- Q3: Get hot posts for discovery
--     Expected: P95 < 20ms (cached)
--     SELECT post_id, score, likes, comments
--     FROM hot_posts
--     WHERE collected_at = (SELECT max(collected_at) FROM hot_posts)
--     ORDER BY score DESC
--     LIMIT 50
--
-- Q4: Event ingestion rate monitoring
--     Expected: P95 < 200ms
--     SELECT event_type, count(*) as cnt
--     FROM events
--     WHERE created_at > now() - INTERVAL 1 HOUR
--     GROUP BY event_type

-- ============================================
-- Migration Notes
-- ============================================
-- This schema is idempotent (safe to run multiple times).
-- All tables use IF NOT EXISTS.
--
-- For production deployment:
-- 1. Create database first
-- 2. Run this schema on all cluster nodes
-- 3. Set up Kafka engines (see kafka-engines.sql)
-- 4. Create materialized views (see materialized-views.sql)
-- 5. Initialize permissions (see init.sh)
--
-- For development:
-- 1. Use docker-compose.yml to start local ClickHouse
-- 2. Run init.sh to set up everything automatically
-- 3. Test with sample data (see queries/test-data.sql)

-- ============================================
-- Monitoring Queries
-- ============================================
-- Check table sizes:
-- SELECT
--   database,
--   table,
--   formatReadableSize(sum(bytes)) as size,
--   sum(rows) as rows,
--   max(modification_time) as latest_data
-- FROM system.parts
-- WHERE database = 'nova_analytics'
-- GROUP BY database, table
-- ORDER BY sum(bytes) DESC;
--
-- Check partition count:
-- SELECT
--   table,
--   count() as partition_count,
--   min(partition) as oldest_partition,
--   max(partition) as newest_partition
-- FROM system.parts
-- WHERE database = 'nova_analytics' AND active
-- GROUP BY table;
--
-- Check query performance:
-- SELECT
--   query_duration_ms,
--   query,
--   read_rows,
--   formatReadableSize(read_bytes) as read_size
-- FROM system.query_log
-- WHERE event_date = today()
--   AND query NOT LIKE '%system.%'
-- ORDER BY query_duration_ms DESC
-- LIMIT 10;
