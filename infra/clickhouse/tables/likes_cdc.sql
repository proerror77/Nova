-- ============================================
-- Likes CDC table
-- Engine: ReplacingMergeTree
-- Source: Debezium topic 'nova.public.likes'
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.likes_cdc (
    -- Composite key
    user_id        UUID,
    post_id        UUID,

    -- Business fields
    created_at     DateTime('UTC'),
    deleted        UInt8 DEFAULT 0,

    -- CDC metadata
    _version       UInt64,
    _ts_ms         UInt64
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (user_id, post_id, _version)
TTL toDateTime(created_at) + INTERVAL 365 DAY DELETE
SETTINGS
    index_granularity = 8192;

-- Query pattern:
--   Check if user liked post: WHERE user_id = ? AND post_id = ? AND deleted = 0
--   Count likes per post: GROUP BY post_id
