-- ============================================
-- User-Author affinity scores (rolling 90 days)
-- Engine: SummingMergeTree
-- Updated by: mv_user_author_90d materialized view
-- Purpose: Personalized content discovery based on historical interactions
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.user_author_90d (
    -- Dimensions
    user_id        UUID,
    author_id      UUID,

    -- Engagement metrics (SUMmed on merge)
    likes          UInt64 DEFAULT 0,
    comments       UInt64 DEFAULT 0,
    views          UInt64 DEFAULT 0,
    dwell_ms       UInt64 DEFAULT 0,

    -- Metadata
    last_ts        DateTime('UTC'),  -- Latest interaction timestamp

    -- Composite affinity score (computed in query)
    -- Formula: (likes * 10 + comments * 5 + views * 1 + dwell_ms / 1000) / days_active

    INDEX idx_user_id user_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_author_id author_id TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree
ORDER BY (user_id, author_id)
TTL toDateTime(last_ts) + INTERVAL 120 DAY DELETE
SETTINGS
    index_granularity = 8192,
    ttl_only_drop_parts = 1;

-- Query pattern: Get top authors for a user
-- SELECT
--     author_id,
--     sum(likes) AS total_likes,
--     sum(comments) AS total_comments,
--     sum(views) AS total_views,
--     (sum(likes) * 10 + sum(comments) * 5 + sum(views)) AS affinity_score
-- FROM user_author_90d
-- WHERE user_id = ?
-- GROUP BY author_id
-- ORDER BY affinity_score DESC
-- LIMIT 20;

-- Anti-pattern warning: Do NOT use WHERE last_ts >= now() - 90 days in MV
-- TTL handles expiration automatically, filtering in MV wastes compute
