-- ============================================================================
-- Quick Win #4: Performance Analysis & EXPLAIN ANALYZE Scripts
-- ============================================================================
--
-- This script provides comprehensive performance testing for the new indexes.
-- Run these queries BEFORE and AFTER migration to measure improvements.
--
-- Usage:
-- 1. Create backup of these results BEFORE running migration
-- 2. Run each test case and save output
-- 3. Run migration
-- 4. Run same test cases again
-- 5. Compare results to measure improvement
--
-- ============================================================================

-- ============================================================================
-- SECTION 1: PRE-MIGRATION BASELINE TESTS
-- ============================================================================
-- Run this entire section BEFORE applying the migration
-- This captures the current performance without the new indexes

-- ============================================================================
-- TEST 1.1: Message History Query (High Volume)
-- ============================================================================
-- Purpose: Test finding all messages from a specific user
-- Query Pattern: Commonly used in user profile message timeline
-- Expected: Sequential Scan (without index) or Index Scan (with index)
--
-- Create a test message if no real data:
-- INSERT INTO messages (id, sender_id, conversation_id, content, created_at, deleted_at)
-- VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', gen_random_uuid(), 'test', NOW(), NULL);

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Key metrics to track:
-- - Execution Time: [RECORD THIS]
-- - Planning Time: [RECORD THIS]
-- - Rows: Should return ~50 or fewer
-- - Scan Type: Should change from SeqScan to IndexScan after migration

-- ============================================================================
-- TEST 1.2: User Content Timeline Query
-- ============================================================================
-- Purpose: Test finding all posts from a specific user
-- Query Pattern: Commonly used in user profile content timeline
-- Expected: Sequential Scan (without) → Index Scan (with index)

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT id, user_id, content, created_at
FROM posts
WHERE user_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Key metrics to track:
-- - Execution Time: [RECORD THIS]
-- - Planning Time: [RECORD THIS]
-- - Rows returned: Typically 10-100 per user

-- ============================================================================
-- TEST 1.3: Feed Generation with Multiple Conditions
-- ============================================================================
-- Purpose: Test complex feed query with JOINs
-- Query Pattern: Main feed generation query
-- Expected: Multiple sequential scans that can be optimized

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT DISTINCT
    p.id,
    p.user_id,
    p.content,
    p.created_at,
    COUNT(*) OVER (PARTITION BY p.user_id) as user_post_count
FROM posts p
WHERE p.created_at > NOW() - INTERVAL '30 days'
  AND p.deleted_at IS NULL
  AND p.user_id IN (
      SELECT DISTINCT user_id FROM user_feed_preferences
      WHERE user_id = '00000000-0000-0000-0000-000000000001'
  )
ORDER BY p.created_at DESC
LIMIT 100;

-- Key metrics to track:
-- - Total Execution Time: [RECORD THIS] (typically 100-500ms without index)
-- - Number of Seq Scans: Should decrease after index creation
-- - Index usage: Should increase after migration

-- ============================================================================
-- TEST 1.4: Pagination with Cursor
-- ============================================================================
-- Purpose: Test cursor-based pagination (most common pattern)
-- Query Pattern: Pagination using created_at DESC ordering
-- Expected: Sequential Scan → Index Scan with cursor position

-- Get a cursor (created_at timestamp from previous query)
SET cursor_timestamp = '2025-01-15 10:30:00';

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
  AND created_at < current_setting('cursor_timestamp')::TIMESTAMPTZ
ORDER BY created_at DESC
LIMIT 50;

-- Key metrics to track:
-- - Execution Time: Should be very fast with index
-- - Buffer hits: Should be high (mostly in-memory)

-- ============================================================================
-- SECTION 2: INDEX USAGE MONITORING
-- ============================================================================
-- Run after indexes are created to verify they're being used

-- ============================================================================
-- TEST 2.1: Verify Indexes Exist
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY tablename, indexname;

-- Expected output after migration:
-- schemaname | tablename | indexname                    | indexdef (truncated)                                | index_size
-- -----------|-----------|-----------------------------|-----------------------------------------------------|----------
-- public     | messages  | idx_messages_sender_created | CREATE INDEX idx_messages_sender_created ON m...   | 150 MB
-- public     | posts     | idx_posts_user_created      | CREATE INDEX idx_posts_user_created ON posts(...   | 50 MB

-- ============================================================================
-- TEST 2.2: Monitor Index Usage Statistics
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_returned,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE
        WHEN idx_scan = 0 THEN 'NOT USED'
        WHEN idx_scan > 100 THEN 'HEAVILY USED'
        WHEN idx_scan > 10 THEN 'REGULARLY USED'
        ELSE 'LIGHTLY USED'
    END as usage_level,
    CASE
        WHEN idx_tup_read > 0
            THEN ROUND(100.0 * idx_tup_fetch / idx_tup_read, 2)
        ELSE 0
    END as selectivity_pct
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY idx_scan DESC;

-- Interpretation:
-- idx_scan > 0: Index is being used ✓
-- selectivity_pct > 90%: Index is highly selective ✓
-- index_size < 20% of table: Index is reasonably sized ✓

-- ============================================================================
-- TEST 2.3: Check Cache Hit Ratio
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    heap_blks_hit as cache_hits,
    heap_blks_read as cache_misses,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE
        WHEN heap_blks_read = 0 THEN '100.00%'
        ELSE ROUND(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)::text || '%'
    END as cache_hit_ratio
FROM pg_statio_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY tablename;

-- Ideal: cache_hit_ratio > 95% (indexes mostly in memory)
-- If < 80%: Consider increasing shared_buffers or reducing index size

-- ============================================================================
-- SECTION 3: POST-MIGRATION PERFORMANCE TESTS
-- ============================================================================
-- Run these same tests AFTER migration to measure improvement

-- ============================================================================
-- TEST 3.1: Message History - Post-Migration (Compare with TEST 1.1)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Expected improvement:
-- - Execution Time: < 10ms (was 100-500ms)
-- - Scan Type: Index Scan (was Seq Scan)
-- - Improvement: 10-50x faster

-- ============================================================================
-- TEST 3.2: User Content - Post-Migration (Compare with TEST 1.2)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT id, user_id, content, created_at
FROM posts
WHERE user_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Expected improvement:
-- - Execution Time: < 5ms (was 50-200ms)
-- - Scan Type: Index Scan (was Seq Scan)
-- - Improvement: 10-40x faster

-- ============================================================================
-- TEST 3.3: Feed Generation - Post-Migration (Compare with TEST 1.3)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT DISTINCT
    p.id,
    p.user_id,
    p.content,
    p.created_at,
    COUNT(*) OVER (PARTITION BY p.user_id) as user_post_count
FROM posts p
WHERE p.created_at > NOW() - INTERVAL '30 days'
  AND p.deleted_at IS NULL
  AND p.user_id IN (
      SELECT DISTINCT user_id FROM user_feed_preferences
      WHERE user_id = '00000000-0000-0000-0000-000000000001'
  )
ORDER BY p.created_at DESC
LIMIT 100;

-- Expected improvement:
-- - Total Execution Time: < 100ms (was 100-500ms)
-- - Multiple Seq Scans reduced: More Index Scans
-- - Improvement: 5-10x faster (depends on feed complexity)

-- ============================================================================
-- SECTION 4: COMPARATIVE ANALYSIS
-- ============================================================================

-- ============================================================================
-- TEST 4.1: Index Size vs Table Size
-- ============================================================================

SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as table_size,
    COUNT(*) as total_indexes,
    SUM(pg_relation_size(indexrelid))::text as total_index_size,
    pg_size_pretty(SUM(pg_relation_size(indexrelid))) as total_index_size_pretty,
    ROUND(100.0 * SUM(pg_relation_size(indexrelid)) / pg_total_relation_size(schemaname||'.'||tablename), 2) as index_overhead_pct
FROM pg_stat_user_indexes
WHERE tablename IN ('messages', 'posts')
GROUP BY schemaname, tablename
ORDER BY tablename;

-- Expected:
-- messages table: ~4-6GB, indexes: ~600-900MB (15-20% overhead)
-- posts table: ~2-3GB, indexes: ~300-450MB (15-20% overhead)

-- ============================================================================
-- TEST 4.2: Query Cost Comparison
-- ============================================================================

-- Before optimization (without index):
-- Seq Scan on messages (cost=0.00..150000.00)
--
-- After optimization (with index):
-- Index Scan using idx_messages_sender_created (cost=0.42..1500.00)

-- Cost reduction: ~100x (theoretical)
-- Actual execution time reduction: 10-50x (depends on selectivity)

-- ============================================================================
-- TEST 4.3: Row Filtering Effectiveness
-- ============================================================================

SELECT
    't1' as test_name,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) as active_count,
    COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) as deleted_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE deleted_at IS NULL) / COUNT(*), 2) as active_percentage
FROM messages;

SELECT
    't2' as test_name,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) as active_count,
    COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) as deleted_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE deleted_at IS NULL) / COUNT(*), 2) as active_percentage
FROM posts;

-- Expected:
-- High active percentage (>95%) means WHERE filter is effective
-- Indexes are more selective when filtering active records

-- ============================================================================
-- SECTION 5: SLOW QUERY ANALYSIS
-- ============================================================================

-- Enable slow query logging (if available)
-- SET log_min_duration_statement = 1000;  -- Log queries > 1000ms

-- ============================================================================
-- TEST 5.1: Top Slow Queries (if pg_stat_statements extension enabled)
-- ============================================================================

SELECT
    query,
    calls as query_count,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(max_exec_time::numeric, 2) as max_time_ms,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time * calls / 1000, 2) as total_time_seconds
FROM pg_stat_statements
WHERE (query LIKE '%messages%' OR query LIKE '%posts%')
  AND query NOT LIKE '%pg_stat%'
ORDER BY mean_exec_time DESC
LIMIT 20;

-- This shows actual query patterns in production
-- After migration, these should show significantly lower execution times

-- ============================================================================
-- TEST 5.2: Lock Contention During Index Creation
-- ============================================================================

-- Run during index creation in a separate connection:
SELECT
    pid,
    usename,
    state,
    query,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event_type IS NOT NULL
  AND query LIKE '%CREATE INDEX%';

-- Expected during CONCURRENT index creation:
-- - State: active or idle
-- - Wait events: minimal (should be none for CONCURRENT)
-- - Query: CREATE INDEX ... CONCURRENTLY

-- ============================================================================
-- SECTION 6: RECOMMENDATIONS & NEXT STEPS
-- ============================================================================

-- If new indexes are working well (idx_scan > 0, selectivity > 90%):
--
-- 1. Consider adding these compound indexes:
--    CREATE INDEX idx_messages_conversation_sender_created
--    ON messages(conversation_id, sender_id, created_at DESC)
--    WHERE deleted_at IS NULL;
--
-- 2. Monitor pg_stat_statements for other slow queries
--
-- 3. Consider partitioning if tables grow > 10GB
--
-- 4. Implement automatic VACUUM and ANALYZE jobs
--
-- 5. Set up alerts for index bloat and unused indexes

-- ============================================================================
-- PERFORMANCE IMPROVEMENT MATRIX
-- ============================================================================
--
-- Query Type              | Before    | After   | Improvement
-- ------------------------|-----------|---------|-------------
-- Single user messages    | 100-500ms | 5-20ms  | 10-50x
-- Single user posts       | 50-200ms  | 3-15ms  | 10-40x
-- Feed generation (100)   | 500ms     | 100ms   | 5x (80% improvement)
-- Auth email lookup       | 10-50ms   | 5-20ms  | 2-5x (existing index)
-- Cursor pagination (50)  | 50-200ms  | 5-15ms  | 10-20x
-- Complex JOINs          | 200-800ms | 50-150ms| 3-8x
--
-- ============================================================================
