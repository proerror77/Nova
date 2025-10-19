-- ============================================
-- Posts CDC table (Change Data Capture from PostgreSQL)
-- Engine: ReplacingMergeTree (upsert semantics via _version)
-- Source: Debezium Kafka topic 'nova.public.posts'
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.posts_cdc (
    -- Primary key
    post_id        UUID,

    -- Business fields
    user_id        UUID,
    created_at     DateTime('UTC'),
    deleted        UInt8 DEFAULT 0,

    -- CDC metadata
    _version       UInt64,  -- Debezium transaction ID (ensures latest version wins)
    _ts_ms         UInt64   -- Debezium event timestamp (milliseconds since epoch)
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, _version)
TTL toDateTime(created_at) + INTERVAL 365 DAY DELETE
SETTINGS
    index_granularity = 8192;

-- Query pattern: SELECT ... WHERE post_id IN (...) AND deleted = 0
-- Avoid FINAL in production (use explicit _version filtering in queries)
-- Example query:
--   SELECT post_id, user_id, created_at
--   FROM posts_cdc
--   WHERE (post_id, _version) IN (
--       SELECT post_id, max(_version) AS _version
--       FROM posts_cdc
--       WHERE post_id IN (...)
--       GROUP BY post_id
--   ) AND deleted = 0;
