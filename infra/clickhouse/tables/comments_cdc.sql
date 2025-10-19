-- ============================================
-- Comments CDC table
-- Engine: ReplacingMergeTree
-- Source: Debezium topic 'nova.public.comments'
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.comments_cdc (
    -- Primary key
    comment_id     UUID,

    -- Foreign keys
    post_id        UUID,
    user_id        UUID,

    -- Business fields
    created_at     DateTime('UTC'),
    deleted        UInt8 DEFAULT 0,

    -- CDC metadata
    _version       UInt64,
    _ts_ms         UInt64
) ENGINE = ReplacingMergeTree(_version)
PARTITION BY toYYYYMM(created_at)
ORDER BY (post_id, created_at, comment_id, _version)
TTL toDateTime(created_at) + INTERVAL 365 DAY DELETE
SETTINGS
    index_granularity = 8192;

-- Query pattern: Count comments per post for engagement metrics
-- SELECT post_id, count() FROM comments_cdc
-- WHERE post_id IN (...) AND deleted = 0
-- GROUP BY post_id
