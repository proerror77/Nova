-- ============================================
-- Follows CDC table (PostgreSQL replication)
-- Engine: ReplacingMergeTree
-- Source: Debezium topic 'nova.public.follows'
-- ============================================

CREATE TABLE IF NOT EXISTS nova_feed.follows_cdc (
    -- Composite key
    follower_id    UUID,
    following_id   UUID,

    -- Business fields
    created_at     DateTime('UTC'),
    deleted        UInt8 DEFAULT 0,

    -- CDC metadata
    _version       UInt64,  -- Debezium LSN or transaction ID
    _ts_ms         UInt64
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (follower_id, following_id, _version)
TTL toDateTime(created_at) + INTERVAL 365 DAY DELETE
SETTINGS
    index_granularity = 8192;

-- Query pattern:
--   SELECT following_id FROM follows_cdc
--   WHERE follower_id = ? AND deleted = 0
--   GROUP BY following_id HAVING max(_version) AS _version
-- This gives us the latest state of each follow relationship
