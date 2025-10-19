-- ============================================
-- Feed Ranking Query Template
-- Version: 1.0.0
-- Date: 2025-10-18
-- Purpose: Personalized feed ranking for users
-- Performance Target: P95 < 800ms for 50 candidates
-- ============================================

-- ============================================
-- Query 1: Personalized Feed (Following + Affinity)
-- Use Case: Main feed for authenticated users
-- Expected Performance: P95 < 500ms
-- ============================================
--
-- Parameters:
--   {user_id}: Current user UUID
--   {limit}: Number of posts to return (default 50)
--   {offset}: Pagination offset (default 0)
--   {min_score}: Minimum score threshold (default 0.1)
--   {lookback_hours}: Time window for recent posts (default 72)

SELECT
  p.id AS post_id,
  p.user_id AS author_id,
  p.caption,
  p.created_at,

  -- Image URLs (from latest variants)
  any(pi_thumb.url) AS thumbnail_url,
  any(pi_medium.url) AS medium_url,

  -- Engagement metrics (last 24 hours)
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments,
  sum(pm.shares_count) AS shares,
  sum(pm.views_count) AS views,

  -- Ranking score components
  round(
    0.30 * exp(-0.10 * dateDiff('hour', p.created_at, now())) +  -- Freshness (30%)
    0.25 * log1p(sum(pm.likes_count) + 2*sum(pm.comments_count) + 3*sum(pm.shares_count)) / greatest(sum(pm.impressions_count), 1) +  -- Engagement (25%)
    0.20 * coalesce(ua.interaction_count / 100.0, 0.01) +  -- User affinity (20%)
    0.15 * if(ua.follows_author = 1, 1.0, 0.0) +  -- Follow bonus (15%)
    0.10 * log1p(avg(pm.avg_dwell_ms) / 1000.0),  -- Dwell time (10%)
    4
  ) AS score

FROM posts AS p FINAL

-- Join follows to get user's network
INNER JOIN follows AS f FINAL
  ON f.following_id = p.user_id
  AND f.follower_id = {user_id:UUID}
  AND f.__deleted = 0

-- Join post metrics for engagement data
LEFT JOIN post_metrics_1h AS pm
  ON pm.post_id = p.id
  AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 24 HOUR

-- Join user affinity for personalization
LEFT JOIN user_author_affinity AS ua
  ON ua.user_id = {user_id:UUID}
  AND ua.author_id = p.user_id

-- Join image variants (thumbnail and medium)
LEFT JOIN (
  SELECT post_id, url
  FROM (
    SELECT post_id, url, row_number() OVER (PARTITION BY post_id ORDER BY created_at DESC) AS rn
    FROM post_images FINAL
    WHERE size_variant = 'thumbnail' AND status = 'completed' AND __deleted = 0
  )
  WHERE rn = 1
) AS pi_thumb ON pi_thumb.post_id = p.id

LEFT JOIN (
  SELECT post_id, url
  FROM (
    SELECT post_id, url, row_number() OVER (PARTITION BY post_id ORDER BY created_at DESC) AS rn
    FROM post_images FINAL
    WHERE size_variant = 'medium' AND status = 'completed' AND __deleted = 0
  )
  WHERE rn = 1
) AS pi_medium ON pi_medium.post_id = p.id

-- Filters (use PREWHERE for better performance)
PREWHERE
  p.status = 'published'
  AND p.soft_delete IS NULL
  AND p.__deleted = 0
  AND p.created_at >= now() - INTERVAL {lookback_hours:UInt16} HOUR

GROUP BY
  p.id,
  p.user_id,
  p.caption,
  p.created_at,
  ua.interaction_count,
  ua.follows_author

HAVING score >= {min_score:Float32}

ORDER BY score DESC

LIMIT {limit:UInt16} OFFSET {offset:UInt32};


-- ============================================
-- Query 2: Discovery Feed (No Following Required)
-- Use Case: Explore page, new users, cold start
-- Expected Performance: P95 < 300ms
-- ============================================
--
-- Parameters:
--   {user_id}: Current user UUID (optional, for deduplication)
--   {limit}: Number of posts to return (default 50)
--   {offset}: Pagination offset (default 0)
--   {lookback_hours}: Time window (default 48)

SELECT
  post_id,
  author_id,
  likes,
  comments,
  shares,
  impressions,
  score,
  created_at,
  collected_at
FROM hot_posts
WHERE collected_at = (SELECT max(collected_at) FROM hot_posts)
ORDER BY score DESC
LIMIT {limit:UInt16} OFFSET {offset:UInt32};


-- ============================================
-- Query 3: Author-Specific Feed
-- Use Case: View all posts from a specific author
-- Expected Performance: P95 < 200ms
-- ============================================
--
-- Parameters:
--   {author_id}: Author's user UUID
--   {limit}: Number of posts (default 50)
--   {offset}: Pagination offset (default 0)

SELECT
  p.id AS post_id,
  p.user_id AS author_id,
  p.caption,
  p.created_at,

  -- Image URLs
  any(pi_thumb.url) AS thumbnail_url,
  any(pi_medium.url) AS medium_url,

  -- Engagement metrics
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments,
  sum(pm.shares_count) AS shares,
  sum(pm.views_count) AS views

FROM posts AS p FINAL

LEFT JOIN post_metrics_1h AS pm
  ON pm.post_id = p.id
  AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 24 HOUR

LEFT JOIN (
  SELECT post_id, url, row_number() OVER (PARTITION BY post_id ORDER BY created_at DESC) AS rn
  FROM post_images FINAL
  WHERE size_variant = 'thumbnail' AND status = 'completed' AND __deleted = 0
) AS pi_thumb ON pi_thumb.post_id = p.id AND pi_thumb.rn = 1

LEFT JOIN (
  SELECT post_id, url, row_number() OVER (PARTITION BY post_id ORDER BY created_at DESC) AS rn
  FROM post_images FINAL
  WHERE size_variant = 'medium' AND status = 'completed' AND __deleted = 0
) AS pi_medium ON pi_medium.post_id = p.id AND pi_medium.rn = 1

PREWHERE
  p.user_id = {author_id:UUID}
  AND p.status = 'published'
  AND p.soft_delete IS NULL
  AND p.__deleted = 0

GROUP BY
  p.id,
  p.user_id,
  p.caption,
  p.created_at

ORDER BY p.created_at DESC

LIMIT {limit:UInt16} OFFSET {offset:UInt32};


-- ============================================
-- Query 4: Get Post Metrics by IDs (Batch)
-- Use Case: Enrich posts with latest metrics
-- Expected Performance: P95 < 100ms for 50 posts
-- ============================================
--
-- Parameters:
--   {post_ids}: Array of post UUIDs (e.g., ['uuid1', 'uuid2', ...])

SELECT
  post_id,
  sum(likes_count) AS likes,
  sum(comments_count) AS comments,
  sum(shares_count) AS shares,
  sum(views_count) AS views,
  sum(impressions_count) AS impressions,
  avg(avg_dwell_ms) AS avg_dwell_ms,
  uniqMerge(unique_viewers) AS unique_viewers
FROM post_metrics_1h
WHERE post_id IN {post_ids:Array(UUID)}
  AND metric_hour >= toStartOfHour(now()) - INTERVAL 24 HOUR
GROUP BY post_id;


-- ============================================
-- Query 5: User Affinity Scores (Personalization)
-- Use Case: Get user's top authors for recommendations
-- Expected Performance: P95 < 50ms
-- ============================================
--
-- Parameters:
--   {user_id}: User UUID
--   {limit}: Number of authors (default 100)

SELECT
  author_id,
  interaction_count,
  last_interaction,
  like_count,
  comment_count,
  view_count,
  share_count,
  avg_dwell_ms,
  follows_author,

  -- Affinity score calculation
  round(
    0.40 * log1p(like_count + 2*comment_count + 3*share_count) +
    0.30 * log1p(interaction_count) +
    0.20 * if(follows_author = 1, 1.0, 0.0) +
    0.10 * exp(-0.05 * dateDiff('day', last_interaction, now())),
    4
  ) AS affinity_score

FROM user_author_affinity FINAL

WHERE user_id = {user_id:UUID}

ORDER BY affinity_score DESC

LIMIT {limit:UInt16};


-- ============================================
-- Query 6: Trending Posts (Last 24 Hours)
-- Use Case: Homepage trending section
-- Expected Performance: P95 < 200ms
-- ============================================
--
-- Parameters:
--   {limit}: Number of posts (default 20)
--   {min_impressions}: Minimum impressions threshold (default 100)

SELECT
  pm.post_id,
  pm.author_id,
  p.caption,
  p.created_at,

  -- Engagement metrics
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments,
  sum(pm.shares_count) AS shares,
  sum(pm.views_count) AS views,
  sum(pm.impressions_count) AS impressions,

  -- Trending score (velocity-based)
  round(
    (sum(pm.likes_count) + 2*sum(pm.comments_count) + 3*sum(pm.shares_count)) /
    greatest(dateDiff('hour', p.created_at, now()), 1),
    4
  ) AS velocity_score

FROM post_metrics_1h AS pm

INNER JOIN posts AS p FINAL
  ON p.id = pm.post_id
  AND p.status = 'published'
  AND p.soft_delete IS NULL
  AND p.__deleted = 0

WHERE pm.metric_hour >= toStartOfHour(now()) - INTERVAL 24 HOUR
  AND p.created_at >= now() - INTERVAL 24 HOUR

GROUP BY
  pm.post_id,
  pm.author_id,
  p.caption,
  p.created_at

HAVING impressions >= {min_impressions:UInt32}

ORDER BY velocity_score DESC

LIMIT {limit:UInt16};


-- ============================================
-- Performance Optimization Tips
-- ============================================
--
-- 1. Use PREWHERE instead of WHERE:
--    - PREWHERE filters data before reading all columns
--    - Significantly faster for selective filters
--    - Best for low-cardinality columns (status, __deleted)
--
-- 2. Avoid FINAL in hot paths:
--    - FINAL forces deduplication at query time (expensive)
--    - Use only when data consistency is critical
--    - Alternative: Schedule OPTIMIZE TABLE to pre-merge data
--
-- 3. Parameterized queries:
--    - Use {param:Type} syntax for type-safe parameters
--    - Prevents SQL injection
--    - Enables query plan caching
--
-- 4. Index-friendly ORDER BY:
--    - ORDER BY (post_id, metric_hour) matches table ORDER BY
--    - Avoids sorting overhead
--    - DESC in ORDER BY is slower (reverse scan)
--
-- 5. Batch queries:
--    - Fetch metrics for multiple posts in one query
--    - Use IN clause with UUIDs array
--    - Reduces round trips and latency
--
-- 6. Materialized columns:
--    - Pre-compute score components (e.g., freshness_score)
--    - Store in table to avoid runtime calculation
--    - Update via materialized view
--
-- 7. Aggregation optimization:
--    - sum() is fast on SummingMergeTree
--    - uniqMerge() for unique counts (AggregateFunction)
--    - Avoid count(DISTINCT ...) (use uniq() instead)

-- ============================================
-- Monitoring & Debugging
-- ============================================
--
-- Check query execution plan:
-- EXPLAIN SELECT ... FROM posts WHERE ...;
--
-- Check query performance:
-- SELECT
--   query_duration_ms,
--   query,
--   read_rows,
--   formatReadableSize(read_bytes) as read_size
-- FROM system.query_log
-- WHERE event_date = today()
--   AND query LIKE '%posts%'
-- ORDER BY query_duration_ms DESC
-- LIMIT 10;
--
-- Check index usage:
-- SELECT
--   table,
--   formatReadableSize(primary_key_bytes_in_memory) as pk_size,
--   primary_key_bytes_in_memory / total_bytes * 100 as pk_ratio
-- FROM system.tables
-- WHERE database = 'nova_analytics';
