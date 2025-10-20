-- ============================================
-- Main events table for user behavior tracking
-- Engine: MergeTree (high write throughput)
-- Retention: 30 days (TTL)
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.events (
    -- Primary key fields
    event_id       UUID DEFAULT generateUUIDv4(),
    event_time     DateTime64(3, 'UTC') DEFAULT now64(3),
    event_date     Date DEFAULT toDate(event_time),

    -- Business dimensions
    user_id        UUID,
    post_id        UUID,
    author_id      UUID,

    -- Event attributes
    action         LowCardinality(String),  -- 'impression', 'view', 'like', 'comment', 'share'
    dwell_ms       UInt32 DEFAULT 0,

    -- Device context
    device         LowCardinality(String),  -- 'ios', 'android', 'web'
    app_ver        LowCardinality(String),  -- e.g., '1.2.3'

    -- Materialized column for partitioning
    INDEX idx_user_id user_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_post_id post_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_action action TYPE set(0) GRANULARITY 1
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_time, event_id)
TTL toDateTime(event_time) + INTERVAL 30 DAY DELETE
SETTINGS
    index_granularity = 8192,
    ttl_only_drop_parts = 1;

-- Comment for operational context
-- Query pattern: SELECT ... WHERE user_id = ? AND event_time >= ? ORDER BY event_time DESC
-- Write pattern: 10k-100k events/sec from Kafka
-- Index granularity: 8192 rows = ~65KB per granule (optimized for SSD)
