-- ============================================
-- Hourly post engagement metrics (pre-aggregated)
-- Engine: SummingMergeTree (automatic SUM on merge)
-- Updated by: mv_post_metrics_1h materialized view
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.post_metrics_1h (
    -- Dimensions
    post_id        UUID,
    window_start   DateTime('UTC'),  -- Aligned to hour boundary (e.g., 2025-01-15 14:00:00)

    -- Metrics (SUMmed on merge)
    views          UInt64 DEFAULT 0,
    likes          UInt64 DEFAULT 0,
    comments       UInt64 DEFAULT 0,
    shares         UInt64 DEFAULT 0,
    dwell_ms_sum   UInt64 DEFAULT 0,
    exposures      UInt64 DEFAULT 0,  -- Impression count

    -- Index for bloom filter
    INDEX idx_post_id post_id TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(window_start)
ORDER BY (post_id, window_start)
TTL toDateTime(window_start) + INTERVAL 90 DAY DELETE
SETTINGS
    index_granularity = 8192,
    ttl_only_drop_parts = 1;

-- Query pattern: Get recent metrics for trending detection
-- SELECT post_id, sum(views) AS total_views, sum(likes) AS total_likes
-- FROM post_metrics_1h
-- WHERE window_start >= now() - INTERVAL 24 HOUR
-- GROUP BY post_id
-- ORDER BY total_views DESC
-- LIMIT 100;

-- Engagement rate calculation:
-- SELECT post_id, sum(likes) / sum(exposures) AS ctr
-- FROM post_metrics_1h
-- WHERE window_start >= now() - INTERVAL 6 HOUR AND exposures > 0
-- GROUP BY post_id;
