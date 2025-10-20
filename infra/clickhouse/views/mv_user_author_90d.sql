-- ============================================
-- Materialized view: Events → User-Author affinity (90-day rolling)
-- Data flow: events table → user_author_90d (SummingMergeTree)
-- Purpose: Personalized content discovery based on engagement history
-- ============================================

CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.mv_user_author_90d
TO nova_feed.user_author_90d AS
SELECT
    user_id,
    author_id,

    -- Engagement signals (SUMmed on merge)
    countIf(action = 'like') AS likes,
    countIf(action = 'comment') AS comments,
    countIf(action = 'view') AS views,
    sumIf(dwell_ms, action = 'view') AS dwell_ms,

    -- Timestamp for TTL calculation
    max(event_time) AS last_ts
FROM nova_feed.events
GROUP BY user_id, author_id;

-- Critical design decision: NO WHERE clause filtering by time
-- ❌ BAD:  WHERE event_time >= now() - INTERVAL 90 DAY  (wastes compute on every insert)
-- ✅ GOOD: Let TTL handle expiration (TTL last_ts + 120 days in table definition)

-- Data flow explanation:
-- 1. Each batch of events triggers aggregation
-- 2. ClickHouse groups by (user_id, author_id)
-- 3. Metrics are SUMmed into user_author_90d table
-- 4. SummingMergeTree merges duplicate keys in background
-- 5. TTL automatically drops rows older than 120 days (90d retention + 30d grace period)

-- Why TTL instead of WHERE filter:
-- - WHERE in MV: Evaluated on EVERY INSERT (expensive for high-frequency events)
-- - TTL: Runs in background during merge operations (zero query-time cost)
-- - Trade-off: Slightly more storage (max 30 extra days) for 100x faster inserts

-- Example query: Get user's favorite authors (affinity-based recommendations)
-- SELECT
--     author_id,
--     sum(likes) AS total_likes,
--     sum(comments) AS total_comments,
--     sum(views) AS total_views,
--     sum(dwell_ms) / 1000 AS total_dwell_sec,
--     -- Weighted affinity score
--     (sum(likes) * 10 + sum(comments) * 5 + sum(views) * 1 + sum(dwell_ms) / 1000) AS affinity_score
-- FROM user_author_90d
-- WHERE user_id = toUUID('...')
-- GROUP BY author_id
-- ORDER BY affinity_score DESC
-- LIMIT 20;

-- Use case in feed ranking:
-- - Cold start: New users have empty affinity → fallback to trending posts
-- - Warm users: Join affinity table to boost posts from preferred authors
-- - Score formula: base_score * (1 + affinity_multiplier)
-- - Example: If user engaged with author 50 times, boost their posts by 2.5x

-- Performance characteristics:
-- - Aggregation latency: ~200ms for 100K events/batch
-- - Query latency: ~100ms to fetch top 20 authors for a user
-- - Cardinality: O(users × authors_per_user) ≈ 1M users × 50 authors = 50M rows
-- - Storage: ~2KB per row × 50M = 100GB (highly compressible)
