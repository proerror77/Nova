-- ============================================
-- ClickHouse setup verification script
-- Run with: clickhouse-client --host clickhouse --queries-file verify_setup.sql
-- ============================================

USE nova_feed;

SELECT '=== 1. Database and Table Status ===' AS section;

SELECT
    name AS table_name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = 'nova_feed'
ORDER BY
    CASE engine
        WHEN 'MergeTree' THEN 1
        WHEN 'ReplacingMergeTree' THEN 2
        WHEN 'SummingMergeTree' THEN 3
        WHEN 'Kafka' THEN 4
        WHEN 'MaterializedView' THEN 5
    END,
    name;

SELECT '\n=== 2. Table Schema Validation ===' AS section;

-- Events table validation
SELECT 'events table' AS check_name,
    countIf(name = 'event_id') AS has_event_id,
    countIf(name = 'user_id') AS has_user_id,
    countIf(name = 'post_id') AS has_post_id
FROM system.columns
WHERE database = 'nova_feed' AND table = 'events';

-- CDC tables validation (_version field)
SELECT 'CDC tables with _version' AS check_name,
    countIf(table = 'posts_cdc' AND name = '_version') AS posts_cdc,
    countIf(table = 'follows_cdc' AND name = '_version') AS follows_cdc,
    countIf(table = 'likes_cdc' AND name = '_version') AS likes_cdc,
    countIf(table = 'comments_cdc' AND name = '_version') AS comments_cdc
FROM system.columns
WHERE database = 'nova_feed';

SELECT '\n=== 3. Kafka Consumer Status ===' AS section;

SELECT
    table AS kafka_table,
    num_consumers,
    assignments,
    exceptions
FROM system.kafka_consumers
WHERE database = 'nova_feed';

-- If no consumers shown, Kafka might not be connected yet
SELECT
    CASE
        WHEN count() > 0 THEN '✅ Kafka consumers active'
        ELSE '⚠️  No Kafka consumers (check Kafka connectivity)'
    END AS kafka_status
FROM system.kafka_consumers
WHERE database = 'nova_feed';

SELECT '\n=== 4. Materialized Views ===' AS section;

SELECT
    name AS mv_name,
    as_select AS query_preview
FROM system.tables
WHERE database = 'nova_feed' AND engine = 'MaterializedView'
ORDER BY name;

SELECT '\n=== 5. Index Validation ===' AS section;

SELECT
    table,
    name AS index_name,
    type AS index_type,
    expr AS index_expression
FROM system.data_skipping_indices
WHERE database = 'nova_feed'
ORDER BY table, name;

SELECT '\n=== 6. TTL Configuration ===' AS section;

SELECT
    table,
    engine_full
FROM system.tables
WHERE database = 'nova_feed' AND engine_full LIKE '%TTL%'
ORDER BY table;

SELECT '\n=== 7. Recent Activity (if any data exists) ===' AS section;

SELECT 'events' AS table, count() AS row_count, max(event_time) AS latest_event
FROM events
UNION ALL
SELECT 'posts_cdc', count(), max(created_at) FROM posts_cdc
UNION ALL
SELECT 'follows_cdc', count(), max(created_at) FROM follows_cdc
UNION ALL
SELECT 'likes_cdc', count(), max(created_at) FROM likes_cdc
UNION ALL
SELECT 'comments_cdc', count(), max(created_at) FROM comments_cdc
UNION ALL
SELECT 'post_metrics_1h', count(), max(window_start) FROM post_metrics_1h
UNION ALL
SELECT 'user_author_90d', count(), max(last_ts) FROM user_author_90d;

SELECT '\n=== 8. Partition Health ===' AS section;

SELECT
    table,
    partition,
    formatReadableSize(sum(bytes_on_disk)) AS total_size,
    sum(rows) AS total_rows,
    count() AS part_count,
    max(modification_time) AS last_modified
FROM system.parts
WHERE database = 'nova_feed' AND active = 1
GROUP BY table, partition
ORDER BY table, partition;

SELECT '\n=== 9. Performance Settings ===' AS section;

SELECT
    name,
    value
FROM system.settings
WHERE name IN (
    'max_threads',
    'max_memory_usage',
    'max_insert_block_size',
    'kafka_max_block_size'
)
ORDER BY name;

SELECT '\n=== 10. Validation Summary ===' AS section;

SELECT
    CASE
        WHEN (SELECT count() FROM system.tables WHERE database = 'nova_feed' AND engine = 'MergeTree') >= 1 THEN '✅'
        ELSE '❌'
    END || ' Events table created' AS check_1,
    CASE
        WHEN (SELECT count() FROM system.tables WHERE database = 'nova_feed' AND engine = 'ReplacingMergeTree') >= 4 THEN '✅'
        ELSE '❌'
    END || ' All CDC tables created (4)' AS check_2,
    CASE
        WHEN (SELECT count() FROM system.tables WHERE database = 'nova_feed' AND engine = 'SummingMergeTree') >= 2 THEN '✅'
        ELSE '❌'
    END || ' Aggregation tables created (2)' AS check_3,
    CASE
        WHEN (SELECT count() FROM system.tables WHERE database = 'nova_feed' AND engine = 'Kafka') >= 5 THEN '✅'
        ELSE '❌'
    END || ' Kafka source tables created (5)' AS check_4,
    CASE
        WHEN (SELECT count() FROM system.tables WHERE database = 'nova_feed' AND engine = 'MaterializedView') >= 7 THEN '✅'
        ELSE '❌'
    END || ' Materialized views created (7)' AS check_5;

SELECT '✅ Verification complete! Check results above for any ❌ failures.' AS final_status;
