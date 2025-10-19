-- ============================================
-- ClickHouse initialization script (idempotent)
-- Run with: clickhouse-client --host clickhouse --port 9000 --user default --password clickhouse --queries-file init_all.sql
-- Execution order: Database → Tables → Kafka Engines → Materialized Views
-- ============================================

-- Step 1: Create database
CREATE DATABASE IF NOT EXISTS nova_feed;
USE nova_feed;

-- ============================================
-- Step 2: Create all tables (order: no dependencies first)
-- ============================================

-- 2a. Events table (fact table)
SOURCE tables/events.sql;

-- 2b. CDC tables (ReplacingMergeTree)
SOURCE tables/posts_cdc.sql;
SOURCE tables/follows_cdc.sql;
SOURCE tables/comments_cdc.sql;
SOURCE tables/likes_cdc.sql;

-- 2c. Aggregation tables (SummingMergeTree)
SOURCE tables/post_metrics_1h.sql;
SOURCE tables/user_author_90d.sql;

-- ============================================
-- Step 3: Create Kafka source tables
-- ============================================

SOURCE engines/kafka_cdc.sql;

-- ============================================
-- Step 4: Create materialized views
-- (Must be after target tables exist)
-- ============================================

SOURCE views/mv_events_to_table.sql;
SOURCE views/mv_post_metrics_1h.sql;
SOURCE views/mv_user_author_90d.sql;

-- ============================================
-- Verification queries
-- ============================================

SELECT 'Database created:' AS status, name FROM system.databases WHERE name = 'nova_feed';

SELECT 'Tables created:' AS status, count() AS table_count
FROM system.tables
WHERE database = 'nova_feed' AND engine NOT IN ('Kafka', 'MaterializedView');

SELECT 'Kafka engines created:' AS status, count() AS kafka_count
FROM system.tables
WHERE database = 'nova_feed' AND engine = 'Kafka';

SELECT 'Materialized views created:' AS status, count() AS mv_count
FROM system.tables
WHERE database = 'nova_feed' AND engine = 'MaterializedView';

-- Show table list
SELECT
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS total_size
FROM system.tables
WHERE database = 'nova_feed'
ORDER BY engine, name;

-- Show partitions for main tables
SELECT
    table,
    partition,
    formatReadableSize(bytes_on_disk) AS size,
    rows,
    modification_time
FROM system.parts
WHERE database = 'nova_feed' AND active = 1
ORDER BY table, partition;

-- Check Kafka consumer status
SELECT
    table,
    num_consumers,
    assignments
FROM system.kafka_consumers
WHERE database = 'nova_feed';

SELECT '✅ Initialization complete!' AS status;
