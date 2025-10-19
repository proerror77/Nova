-- ============================================
-- ClickHouse OLAP Schema for Phase 3
-- Real-time Event Analytics & Feed Ranking
-- ============================================

-- ============================================
-- 1. Raw Events Table (MergeTree)
-- ============================================
CREATE TABLE events_raw ON CLUSTER default (
  event_id UUID,
  user_id UUID,
  post_id Nullable(UUID),
  event_type String,  -- impression, view, like, comment, share, click
  author_id Nullable(UUID),  -- For recommendations
  dwell_ms Nullable(UInt32),
  created_at DateTime,
  timestamp DateTime
) ENGINE = MergeTree()
ORDER BY (created_at, user_id, post_id)
PARTITION BY toYYYYMMDD(created_at)
TTL created_at + INTERVAL 90 DAY;

-- Kafka Engine for direct consumption (only for standalone setup)
CREATE TABLE events_kafka (
  event_id UUID,
  user_id UUID,
  post_id Nullable(UUID),
  event_type String,
  author_id Nullable(UUID),
  dwell_ms Nullable(UInt32),
  created_at DateTime,
  timestamp DateTime
) ENGINE = Kafka()
SETTINGS
  kafka_broker_list = '${KAFKA_BROKER:kafka:9092}',
  kafka_topic_list = 'events',
  kafka_group_id = 'clickhouse-events-consumer',
  kafka_format = 'JSONEachRow',
  kafka_skip_broken_messages = 1,
  kafka_commit_every_batch = 1;

-- ============================================
-- 2. CDC Tables (ReplacingMergeTree)
-- ============================================

-- Posts CDC mapping table
CREATE TABLE posts_cdc (
  id UUID,
  user_id UUID,
  content String,
  image_urls Array(String),
  created_at DateTime,
  updated_at DateTime,
  __op String,
  __deleted Nullable(UInt8)
) ENGINE = ReplacingMergeTree(__updated_at, __deleted)
ORDER BY (id, created_at)
PARTITION BY toYYYYMMDD(created_at);

-- Follows CDC mapping table
CREATE TABLE follows_cdc (
  id UUID,
  follower_id UUID,
  following_id UUID,
  created_at DateTime,
  __op String,
  __deleted Nullable(UInt8)
) ENGINE = ReplacingMergeTree(__deleted)
ORDER BY (follower_id, following_id, created_at)
PARTITION BY toYYYYMMDD(created_at);

-- Comments CDC mapping table
CREATE TABLE comments_cdc (
  id UUID,
  post_id UUID,
  user_id UUID,
  content String,
  parent_comment_id Nullable(UUID),
  created_at DateTime,
  updated_at DateTime,
  soft_delete Nullable(DateTime),
  __op String,
  __deleted Nullable(UInt8)
) ENGINE = ReplacingMergeTree(__updated_at, __deleted)
ORDER BY (post_id, created_at)
PARTITION BY toYYYYMMDD(created_at);

-- Likes CDC mapping table
CREATE TABLE likes_cdc (
  id UUID,
  user_id UUID,
  post_id UUID,
  created_at DateTime,
  __op String,
  __deleted Nullable(UInt8)
) ENGINE = ReplacingMergeTree(__deleted)
ORDER BY (post_id, created_at)
PARTITION BY toYYYYMMDD(created_at);

-- ============================================
-- 3. Materialized View: Raw Events Ingestion
-- ============================================
CREATE MATERIALIZED VIEW mv_events_ingest TO events_raw
AS SELECT * FROM events_kafka;

-- ============================================
-- 4. Aggregation Table: Post Metrics (1-hour buckets)
-- ============================================
CREATE TABLE post_metrics_1h (
  post_id UUID,
  author_id UUID,
  metric_hour DateTime,
  likes_count UInt32,
  comments_count UInt32,
  shares_count UInt32,
  impressions_count UInt32,
  views_count UInt32,
  avg_dwell_ms Float32,
  unique_viewers UInt32,
  updated_at DateTime
) ENGINE = SummingMergeTree((likes_count, comments_count, shares_count, impressions_count, views_count, unique_viewers))
ORDER BY (post_id, metric_hour)
PARTITION BY toYYYYMMDD(metric_hour)
TTL metric_hour + INTERVAL 30 DAY;

-- ============================================
-- 5. Materialized View: Post Metrics Aggregation
-- ============================================
CREATE MATERIALIZED VIEW mv_post_metrics_1h TO post_metrics_1h
AS SELECT
  post_id,
  author_id,
  toStartOfHour(created_at) AS metric_hour,
  sumIf(1, event_type = 'like') AS likes_count,
  sumIf(1, event_type = 'comment') AS comments_count,
  sumIf(1, event_type = 'share') AS shares_count,
  sumIf(1, event_type = 'impression') AS impressions_count,
  sumIf(1, event_type = 'view') AS views_count,
  avg(dwell_ms) AS avg_dwell_ms,
  uniqIf(user_id, event_type IN ('like', 'comment', 'view')) AS unique_viewers,
  now() AS updated_at
FROM events_raw
WHERE post_id IS NOT NULL AND author_id IS NOT NULL
GROUP BY post_id, author_id, metric_hour;

-- ============================================
-- 6. User-Author Affinity (90-day window)
-- ============================================
CREATE TABLE user_author_90d (
  user_id UUID,
  author_id UUID,
  interaction_count UInt32,
  last_interaction DateTime,
  like_count UInt32,
  comment_count UInt32,
  view_count UInt32,
  share_count UInt32,
  avg_dwell_ms Float32,
  follows_author UInt8
) ENGINE = ReplacingMergeTree(last_interaction)
ORDER BY (user_id, author_id)
PARTITION BY toYYYYMM(last_interaction)
TTL last_interaction + INTERVAL 90 DAY;

-- ============================================
-- 7. Materialized View: User Affinity Calculation
-- ============================================
CREATE MATERIALIZED VIEW mv_user_author_90d TO user_author_90d
AS SELECT
  user_id,
  author_id,
  count(*) AS interaction_count,
  max(created_at) AS last_interaction,
  sumIf(1, event_type = 'like') AS like_count,
  sumIf(1, event_type = 'comment') AS comment_count,
  sumIf(1, event_type = 'view') AS view_count,
  sumIf(1, event_type = 'share') AS share_count,
  avg(dwell_ms) AS avg_dwell_ms,
  0 AS follows_author
FROM events_raw
WHERE author_id IS NOT NULL AND created_at > now() - INTERVAL 90 DAY
GROUP BY user_id, author_id;

-- ============================================
-- 8. Helper Table: Current Top Posts (1h)
-- ============================================
CREATE TABLE hot_posts_1h (
  post_id UUID,
  author_id UUID,
  likes UInt32,
  comments UInt32,
  shares UInt32,
  score Float32,
  collected_at DateTime
) ENGINE = ReplacingMergeTree(collected_at)
ORDER BY (collected_at, score DESC)
PARTITION BY toYYYYMMDD(collected_at)
TTL collected_at + INTERVAL 2 DAY;

-- ============================================
-- 9. Helper Table: Follow Graph Cache
-- ============================================
CREATE TABLE follow_graph (
  follower_id UUID,
  following_id UUID,
  created_at DateTime,
  is_active UInt8
) ENGINE = ReplacingMergeTree(created_at)
ORDER BY (follower_id, following_id)
PARTITION BY toYYYYMM(created_at)
TTL created_at + INTERVAL 365 DAY;

-- ============================================
-- 10. Feed Cache View: Recent Follow Posts
-- ============================================
CREATE VIEW feed_recent_follows AS
SELECT
  fp.post_id,
  fp.author_id,
  fp.created_at,
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments,
  sum(pm.shares_count) AS shares,
  max(pm.impressions_count) AS impressions,
  round(1.0 / (1.0 + 0.12 * dateDiff('hour', fp.created_at, now())), 4) AS freshness_score
FROM posts_cdc fp
INNER JOIN follows_cdc f ON fp.user_id = f.following_id
LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 3 HOUR
WHERE f.created_at > now() - INTERVAL 90 DAY
GROUP BY fp.id, fp.author_id, fp.created_at
ORDER BY fp.created_at DESC;

-- ============================================
-- 11. Query Helper: Post Ranking Score
-- (This will be called from Rust/Application layer)
-- ============================================
CREATE VIEW post_ranking_scores AS
SELECT
  post_id,
  author_id,
  likes_count,
  comments_count,
  shares_count,
  impressions_count,
  -- Freshness: exponential decay (λ = 0.08-0.12)
  round(exp(-0.10 * dateDiff('hour', metric_hour, now())), 4) AS freshness_score,
  -- Engagement: log of normalized engagement
  round(log1p((likes_count + 2.0*comments_count + 3.0*shares_count) / greatest(impressions_count, 1)), 4) AS engagement_score,
  -- Combined score for hot posts
  round(0.30 * exp(-0.10 * dateDiff('hour', metric_hour, now())) +
        0.40 * log1p((likes_count + 2.0*comments_count + 3.0*shares_count) / greatest(impressions_count, 1)) +
        0.30 * log1p(avg_dwell_ms / 1000.0), 4) AS combined_score
FROM post_metrics_1h
WHERE metric_hour >= now() - INTERVAL 24 HOUR;

-- ============================================
-- 12. System Tables Setup
-- ============================================
-- Ensure query_log and metric_log are enabled for monitoring
-- Add to config.xml:
-- <query_log>
--   <database>system</database>
--   <table>query_log</table>
--   <partition_by>toYYYYMMDD(event_date)</partition_by>
--   <flush_interval_milliseconds>7500</flush_interval_milliseconds>
-- </query_log>

-- ============================================
-- 13. Dictionary for Follow Relationships
-- ============================================
CREATE DICTIONARY follow_dict (
  follower_id UUID,
  following_id UUID
)
PRIMARY KEY follower_id, following_id
SOURCE(CLICKHOUSE(QUERY SELECT follower_id, following_id FROM follow_graph WHERE is_active = 1))
LAYOUT(COMPLEX_KEY_SPARSE_HASHED())
LIFETIME(MIN 60 MAX 3600);

-- ============================================
-- Index Strategy Notes
-- ============================================
-- MergeTree ORDER BY is the primary index:
-- - events_raw: ORDER BY (created_at, user_id, post_id)
--   Optimizes: Range queries on time, user lookups
-- - posts_cdc: ORDER BY (id, created_at)
--   Optimizes: Post lookups, temporal filtering
-- - post_metrics_1h: ORDER BY (post_id, metric_hour)
--   Optimizes: Scoring queries, time range aggregations

-- ============================================
-- TTL (Time-To-Live) Policy
-- ============================================
-- - events_raw: 90 days (real-time data retention)
-- - post_metrics_1h: 30 days (hourly aggregates)
-- - user_author_90d: 90 days (affinity window)
-- - hot_posts_1h: 2 days (hot list cache)
-- - follows_cdc: 365 days (complete history)

-- ============================================
-- Partitioning Strategy
-- ============================================
-- PARTITION BY toYYYYMMDD(created_at):
--   - Daily partitions for events
--   - Efficient range queries
--   - Easy data lifecycle management (DROP PARTITION for retention)
-- PARTITION BY toYYYYMM(created_at):
--   - Monthly for slower-moving data
--   - user_author_90d affinity tables

-- ============================================
-- Testing Queries
-- ============================================

-- Test 1: Check event ingestion rate (last hour)
-- SELECT count(*) as event_count, event_type, toHour(created_at) as hour
-- FROM events_raw
-- WHERE created_at > now() - INTERVAL 1 HOUR
-- GROUP BY event_type, hour;

-- Test 2: Top posts by engagement (last 24h)
-- SELECT post_id, author_id, likes_count, comments_count, shares_count,
--        round(0.30 * freshness_score + 0.40 * engagement_score, 4) as score
-- FROM post_ranking_scores
-- ORDER BY score DESC
-- LIMIT 10;

-- Test 3: User affinity with authors (last interaction)
-- SELECT user_id, author_id, interaction_count, last_interaction,
--        round(log1p(like_count + 2*comment_count), 4) as affinity_score
-- FROM user_author_90d
-- WHERE user_id = 'YOUR_USER_ID'
-- ORDER BY last_interaction DESC
-- LIMIT 20;

-- Test 4: Follow graph size
-- SELECT count(distinct follower_id) as follower_count,
--        count(distinct following_id) as following_count,
--        count(*) as follow_relationships
-- FROM follow_graph
-- WHERE is_active = 1;
