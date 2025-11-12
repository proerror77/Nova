-- ClickHouse Feature Storage Schema
-- This schema should be executed on ClickHouse (not PostgreSQL)
-- Migration: 002_clickhouse_schema
-- Description: Create tables for near-line feature storage

-- Features table (MergeTree engine for analytics workloads)
CREATE TABLE IF NOT EXISTS features (
    entity_type String,
    entity_id String,
    feature_name String,
    feature_value String,  -- JSON-serialized value
    value_type UInt8,  -- 1=Double, 2=Int, 3=String, 4=Bool, 5=DoubleList, 6=Timestamp
    updated_at DateTime DEFAULT now(),
    INDEX idx_entity_id (entity_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_feature_name (feature_name) TYPE bloom_filter GRANULARITY 1
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(updated_at)
ORDER BY (entity_type, entity_id, feature_name, updated_at)
TTL updated_at + INTERVAL 90 DAY;  -- Keep features for 90 days

-- Feature embeddings table (optimized for vector storage)
CREATE TABLE IF NOT EXISTS feature_embeddings (
    entity_type String,
    entity_id String,
    feature_name String,
    embedding Array(Float32),  -- Embedding vector
    dimension UInt16,  -- Vector dimension
    updated_at DateTime DEFAULT now(),
    INDEX idx_entity_id (entity_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(updated_at)
ORDER BY (entity_type, entity_id, feature_name, updated_at)
TTL updated_at + INTERVAL 90 DAY;

-- Feature access log (for monitoring and debugging)
CREATE TABLE IF NOT EXISTS feature_access_log (
    entity_type String,
    entity_id String,
    feature_name String,
    access_type Enum8('read' = 1, 'write' = 2),
    source Enum8('redis' = 1, 'clickhouse' = 2, 'direct' = 3),
    timestamp DateTime DEFAULT now(),
    INDEX idx_timestamp (timestamp) TYPE minmax GRANULARITY 1
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (entity_type, timestamp)
TTL timestamp + INTERVAL 7 DAY;  -- Keep logs for 7 days

-- Materialized view for feature access statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS feature_access_stats
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (entity_type, feature_name, access_type, hour)
AS SELECT
    entity_type,
    feature_name,
    access_type,
    toStartOfHour(timestamp) AS hour,
    count() AS access_count
FROM feature_access_log
GROUP BY entity_type, feature_name, access_type, hour;

-- Sample queries:
-- 1. Get latest feature value:
--    SELECT feature_value FROM features
--    WHERE entity_type = 'user' AND entity_id = '123' AND feature_name = 'engagement_score'
--    ORDER BY updated_at DESC LIMIT 1

-- 2. Get all features for an entity:
--    SELECT feature_name, feature_value FROM features
--    WHERE entity_type = 'user' AND entity_id = '123'
--    ORDER BY updated_at DESC

-- 3. Get feature access statistics:
--    SELECT feature_name, access_type, sum(access_count) as total_accesses
--    FROM feature_access_stats
--    WHERE entity_type = 'user' AND hour >= now() - INTERVAL 1 DAY
--    GROUP BY feature_name, access_type
--    ORDER BY total_accesses DESC
