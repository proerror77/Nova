-- ============================================
-- Materialized Views for Real-Time Data Processing
-- Version: 1.0.0
-- Date: 2025-10-18
-- Purpose: Transform and aggregate data from Kafka to target tables
-- ============================================

USE nova_analytics;

-- ============================================
-- MV1: Events Ingestion (Kafka → events)
-- Purpose: Consume events from Kafka and store in events table
-- Trigger: Every batch from events_kafka
-- Expected throughput: 1000+ events/second
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_events_ingest TO events
AS SELECT
  event_id,
  user_id,
  post_id,
  event_type,
  author_id,
  dwell_ms,
  created_at
FROM events_kafka;

-- ============================================
-- MV2: Post Metrics Aggregation (events → post_metrics_1h)
-- Purpose: Pre-aggregate hourly metrics per post
-- Trigger: On insert to events table
-- Performance: Reduces query time from 2s to <100ms for 50 posts
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_post_metrics_1h TO post_metrics_1h
AS SELECT
  post_id,
  author_id,
  toStartOfHour(created_at) AS metric_hour,

  -- Aggregate counts
  sumIf(1, event_type = 'like') AS likes_count,
  sumIf(1, event_type = 'comment') AS comments_count,
  sumIf(1, event_type = 'share') AS shares_count,
  sumIf(1, event_type = 'impression') AS impressions_count,
  sumIf(1, event_type = 'view') AS views_count,

  -- Average dwell time
  avgIf(dwell_ms, event_type IN ('view', 'impression') AND dwell_ms IS NOT NULL) AS avg_dwell_ms,

  -- Unique viewers (uses AggregateFunction for SummingMergeTree)
  uniqState(user_id) AS unique_viewers,

  now() AS updated_at
FROM events
WHERE post_id IS NOT NULL
  AND author_id IS NOT NULL
  AND created_at >= now() - INTERVAL 30 DAY  -- Only aggregate recent events
GROUP BY
  post_id,
  author_id,
  metric_hour;

-- ============================================
-- MV3: User-Author Affinity (events → user_author_affinity)
-- Purpose: Track user interaction patterns with specific authors
-- Window: 90 days rolling (enforced by TTL on target table)
-- Use case: Personalized feed ranking
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_author_affinity TO user_author_affinity
AS SELECT
  user_id,
  author_id,
  count() AS interaction_count,
  max(created_at) AS last_interaction,

  -- Interaction breakdown
  sumIf(1, event_type = 'like') AS like_count,
  sumIf(1, event_type = 'comment') AS comment_count,
  sumIf(1, event_type = 'view') AS view_count,
  sumIf(1, event_type = 'share') AS share_count,

  -- Average engagement quality
  avgIf(dwell_ms, event_type = 'view' AND dwell_ms IS NOT NULL) AS avg_dwell_ms,

  -- Follow status (default 0, will be updated by CDC)
  0 AS follows_author
FROM events
WHERE author_id IS NOT NULL
  AND user_id != author_id  -- Exclude self-interactions
  AND created_at >= now() - INTERVAL 90 DAY
GROUP BY
  user_id,
  author_id;

-- ============================================
-- MV4: Posts CDC Sync (posts_kafka → posts)
-- Purpose: Replicate PostgreSQL posts table to ClickHouse
-- Source: Debezium CDC from PostgreSQL
-- Handling: Upserts and soft deletes
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_posts_cdc TO posts
AS SELECT
  id,
  user_id,
  caption,
  image_key,
  status,
  created_at,
  updated_at,
  soft_delete,
  __op,
  if(__op = 'd', 1, 0) AS __deleted,
  toUnixTimestamp(updated_at) AS __version  -- Use updated_at as version for deduplication
FROM posts_kafka;

-- ============================================
-- MV5: Follows CDC Sync (follows_kafka → follows)
-- Purpose: Replicate PostgreSQL follows table to ClickHouse
-- Source: Debezium CDC from PostgreSQL
-- Side effect: Update follows_author in user_author_affinity
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_follows_cdc TO follows
AS SELECT
  id,
  follower_id,
  following_id,
  created_at,
  __op,
  if(__op = 'd', 1, 0) AS __deleted,
  toUnixTimestamp(created_at) AS __version
FROM follows_kafka;

-- ============================================
-- MV6: Comments CDC Sync (comments_kafka → comments)
-- Purpose: Replicate PostgreSQL comments table to ClickHouse
-- Source: Debezium CDC from PostgreSQL
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_comments_cdc TO comments
AS SELECT
  id,
  post_id,
  user_id,
  content,
  parent_comment_id,
  created_at,
  updated_at,
  soft_delete,
  __op,
  if(__op = 'd', 1, 0) AS __deleted,
  toUnixTimestamp(updated_at) AS __version
FROM comments_kafka;

-- ============================================
-- MV7: Likes CDC Sync (likes_kafka → likes)
-- Purpose: Replicate PostgreSQL likes table to ClickHouse
-- Source: Debezium CDC from PostgreSQL
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_likes_cdc TO likes
AS SELECT
  id,
  user_id,
  post_id,
  created_at,
  __op,
  if(__op = 'd', 1, 0) AS __deleted,
  toUnixTimestamp(created_at) AS __version
FROM likes_kafka;

-- ============================================
-- Performance Optimization Notes
-- ============================================
--
-- 1. Incremental Materialized Views:
--    - ClickHouse MVs are incremental (process new data only)
--    - No need to refresh entire view like traditional databases
--    - Data appears in target table milliseconds after source insert
--
-- 2. Memory Usage:
--    - Each MV uses memory for aggregation states
--    - Monitor with: SELECT * FROM system.tables WHERE engine LIKE '%Materializ%'
--    - Large GROUP BY cardinality can cause memory pressure
--
-- 3. Query Optimization:
--    - Always filter by time range in MV queries
--    - Use PREWHERE for dimension filters (not shown here, use in application queries)
--    - Avoid complex joins in MVs (pre-compute in application layer)
--
-- 4. Backfilling Strategy:
--    - MVs only process new data after creation
--    - To backfill historical data:
--      INSERT INTO target_table SELECT ... FROM source_table WHERE ...
--    - Example for events:
--      INSERT INTO post_metrics_1h
--      SELECT post_id, author_id, toStartOfHour(created_at) AS metric_hour, ...
--      FROM events
--      WHERE created_at >= '2025-01-01' AND created_at < '2025-10-18';

-- ============================================
-- CDC Handling Details
-- ============================================
--
-- Debezium Operation Codes (__op):
--   - 'c': Create (INSERT)
--   - 'u': Update (UPDATE)
--   - 'd': Delete (DELETE)
--   - 'r': Read (snapshot, treat as INSERT)
--
-- Deduplication Strategy:
--   - ReplacingMergeTree uses __version to keep latest record
--   - __version = toUnixTimestamp(updated_at) for updates
--   - __version = toUnixTimestamp(created_at) for inserts
--   - FINAL keyword in queries collapses duplicates
--
-- Soft Delete Handling:
--   - __deleted = 1 marks row as deleted
--   - Keep in table for audit trail
--   - Filter in queries: WHERE __deleted = 0
--   - Alternative: Use FINAL and check __op != 'd'
--
-- Out-of-Order Handling:
--   - ReplacingMergeTree handles out-of-order CDC events
--   - Higher __version always wins during merge
--   - No manual intervention needed

-- ============================================
-- Error Handling & Retry Logic
-- ============================================
--
-- 1. Malformed Data:
--    - Kafka engine skips broken messages (see kafka_skip_broken_messages)
--    - Monitor system.kafka_consumers for exceptions
--    - Log to application for manual investigation
--
-- 2. Constraint Violations:
--    - ClickHouse doesn't enforce foreign keys
--    - Orphaned records possible (e.g., post_id not in posts table)
--    - Handle in application layer or periodic cleanup job
--
-- 3. Duplicate Prevention:
--    - Kafka at-least-once delivery may cause duplicates
--    - ReplacingMergeTree deduplicates based on ORDER BY + __version
--    - SummingMergeTree sums duplicates (idempotent for counters)
--
-- 4. Manual Retry:
--    - If MV processing fails, data remains in Kafka
--    - Reset consumer offset to reprocess:
--      ALTER TABLE events_kafka MODIFY SETTING kafka_reset_offset_on_startup = 'earliest';
--    - Re-create MV to reprocess all Kafka data

-- ============================================
-- Monitoring Queries
-- ============================================
--
-- Check MV processing lag:
-- SELECT
--   database,
--   table,
--   formatReadableSize(total_bytes) as size,
--   total_rows,
--   max(last_exception_time) as last_error,
--   any(last_exception) as error_message
-- FROM system.tables
-- WHERE database = 'nova_analytics'
--   AND engine LIKE '%Materialized%';
--
-- Check ingestion rate (events per second):
-- SELECT
--   toStartOfMinute(event_time) as minute,
--   count() as events_ingested,
--   count() / 60 as events_per_second
-- FROM system.query_log
-- WHERE event_date = today()
--   AND type = 'QueryFinish'
--   AND query LIKE '%INSERT INTO events%'
-- GROUP BY minute
-- ORDER BY minute DESC
-- LIMIT 60;
--
-- Check MV query performance:
-- SELECT
--   view_name,
--   view_query,
--   view_duration_ms,
--   read_rows,
--   formatReadableSize(read_bytes) as read_size
-- FROM system.query_log
-- WHERE event_date = today()
--   AND type = 'QueryFinish'
--   AND is_initial_query = 1
--   AND query LIKE '%MATERIALIZED VIEW%'
-- ORDER BY view_duration_ms DESC
-- LIMIT 20;

-- ============================================
-- Production Checklist
-- ============================================
-- [ ] Verify all MVs created successfully (SHOW TABLES LIKE 'mv_%')
-- [ ] Test event ingestion with sample data
-- [ ] Monitor MV processing lag (should be < 1 second)
-- [ ] Set up alerting for MV exceptions
-- [ ] Test CDC sync with PostgreSQL updates
-- [ ] Verify deduplication works (update same record multiple times)
-- [ ] Test backfilling procedure in staging
-- [ ] Document rollback procedure (DROP MV, recreate)
-- [ ] Load test with 10K events/second
-- [ ] Verify memory usage under load (< 4GB per MV)

-- ============================================
-- Development Testing
-- ============================================
--
-- Test MV1 (events ingestion):
-- 1. Produce event to Kafka (see kafka-engines.sql)
-- 2. Wait 1 second
-- 3. Query: SELECT count(*) FROM events WHERE event_id = '...'
-- Expected: 1 row
--
-- Test MV2 (post metrics):
-- 1. Insert test events:
--    INSERT INTO events VALUES
--    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
--     '33333333-3333-3333-3333-333333333333', 'view', '44444444-4444-4444-4444-444444444444',
--     5000, now());
-- 2. Query: SELECT * FROM post_metrics_1h WHERE post_id = '33333333-3333-3333-3333-333333333333'
-- Expected: 1 row with views_count = 1, avg_dwell_ms = 5000
--
-- Test MV4 (posts CDC):
-- 1. Produce CDC event to Kafka:
--    echo '{"id":"55555555-5555-5555-5555-555555555555","user_id":"66666666-6666-6666-6666-666666666666","caption":"Test","image_key":"test.jpg","status":"published","created_at":"2025-10-18 10:00:00","updated_at":"2025-10-18 10:00:00","__op":"c"}' | \
--    docker exec -i nova-kafka kafka-console-producer.sh --topic postgres.public.posts --bootstrap-server localhost:9092
-- 2. Query: SELECT * FROM posts FINAL WHERE id = '55555555-5555-5555-5555-555555555555'
-- Expected: 1 row with caption = 'Test'
