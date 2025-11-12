# Quick Win #4: Missing Database Indexes - Verification Guide

**Migration**: `090_quick_win_4_missing_indexes.sql`
**Objective**: Add missing indexes to accelerate high-volume queries
**Expected Improvement**: Feed 500ms → 100ms (80% improvement)

---

## Quick Summary

This migration adds two critical missing indexes:

| Index | Table | Columns | Use Case | Expected Improvement |
|-------|-------|---------|----------|----------------------|
| `idx_messages_sender_created` | messages | sender_id, created_at DESC | User message history | 3-5x faster |
| `idx_posts_user_created` | posts | user_id, created_at DESC | User content timeline | 3-5x faster |

---

## Pre-Migration Checklist

### 1. Verify Current Index Status

```sql
-- Check which indexes already exist
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE tablename IN ('messages', 'posts', 'users')
ORDER BY tablename, indexname;
```

### 2. Check Table Sizes (For Estimation)

```sql
-- Messages table size and row count
SELECT
    'messages' as table_name,
    pg_size_pretty(pg_total_relation_size('messages')) as total_size,
    (SELECT COUNT(*) FROM messages) as row_count;

-- Posts table size and row count
SELECT
    'posts' as table_name,
    pg_size_pretty(pg_total_relation_size('posts')) as total_size,
    (SELECT COUNT(*) FROM posts) as row_count;
```

### 3. Baseline Performance Tests (Before Migration)

Run these to get baseline metrics:

```sql
-- Test 1: Message history lookup (5000 messages per user)
EXPLAIN ANALYZE
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = 'user-uuid-here'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Test 2: User content timeline (pagination)
EXPLAIN ANALYZE
SELECT id, user_id, content, created_at
FROM posts
WHERE user_id = 'user-uuid-here'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Test 3: Feed generation (complex join)
EXPLAIN ANALYZE
SELECT DISTINCT p.id, p.user_id, p.content, p.created_at
FROM posts p
JOIN user_feed_preferences ufp ON ufp.user_id = 'current-user-uuid'
WHERE p.created_at > NOW() - INTERVAL '30 days'
  AND p.deleted_at IS NULL
ORDER BY p.created_at DESC
LIMIT 100;
```

---

## Migration Execution

### Option 1: Direct SQL Execution

```bash
# Connect to database
psql -U postgres -d nova -h localhost

# Run migration
\i /path/to/090_quick_win_4_missing_indexes.sql
```

### Option 2: Using Migration Tool (if applicable)

```bash
# Using Flyway
flyway migrate -locations=filesystem:./migrations

# Using liquibase
liquibase update
```

### Option 3: Manual Step-by-Step (Safer for Production)

```sql
-- Step 1: Create first index
CREATE INDEX CONCURRENTLY idx_messages_sender_created
ON messages(sender_id, created_at DESC)
WHERE deleted_at IS NULL;

-- Verify completion
SELECT phase, status FROM migration_log WHERE name = '090_quick_win_4_missing_indexes';

-- Step 2: Create second index
CREATE INDEX CONCURRENTLY idx_posts_user_created
ON posts(user_id, created_at DESC)
WHERE deleted_at IS NULL;

-- Step 3: Update statistics
ANALYZE messages;
ANALYZE posts;
ANALYZE users;
ANALYZE user_feed_preferences;
```

---

## Post-Migration Verification

### 1. Verify Indexes Were Created

```sql
-- Check new indexes exist
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY tablename, indexname;

-- Expected output:
-- public | messages | idx_messages_sender_created | CREATE INDEX idx_messages_sender_created...
-- public | posts | idx_posts_user_created | CREATE INDEX idx_posts_user_created...
```

### 2. Check Index Sizes

```sql
-- Verify indexes aren't too large
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    ROUND(100.0 * pg_relation_size(indexrelid) /
          pg_relation_size(relid), 2) as pct_of_table
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY tablename;

-- Expected:
-- idx_messages_sender_created: ~5-15% of messages table (for 1M messages ≈ 150-300MB)
-- idx_posts_user_created: ~5-15% of posts table (for 500k posts ≈ 50-100MB)
```

### 3. Verify Index Validity

```sql
-- Check for invalid indexes
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY tablename;

-- If idx_scan = 0, index hasn't been used yet (normal immediately after creation)
```

### 4. Run Post-Migration Performance Tests

Execute the same queries from the baseline section:

```sql
-- Test 1: Message history lookup (SHOULD NOW USE INDEX)
EXPLAIN ANALYZE
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = 'user-uuid-here'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Look for: "Index Scan using idx_messages_sender_created" (not Sequential Scan)
-- Expected timing: 1-5ms (was ~100-500ms before)

-- Test 2: User content timeline
EXPLAIN ANALYZE
SELECT id, user_id, content, created_at
FROM posts
WHERE user_id = 'user-uuid-here'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Look for: "Index Scan using idx_posts_user_created"
-- Expected timing: 1-5ms (was ~50-200ms before)
```

### 5. Verify Plan Selection

```sql
-- Run a query that should use the new index
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = 'user-uuid-here'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Key metrics to check:
-- - Execution plan should use: "Index Scan using idx_messages_sender_created"
-- - Planning time should be: < 1ms
-- - Execution time should be: < 10ms
-- - Buffers should show: "Heap Blks: X" (reasonable amount)

-- If still showing "Sequential Scan", check:
-- 1. ANALYZE has completed
-- 2. Index is valid (not invalid/unusable)
-- 3. PostgreSQL version supports index conditions
```

---

## Performance Metrics

### Expected Results (Before → After)

#### User Message History Query
```
Before: Sequential Scan (~500ms for 100k messages, 1000 result rows)
After:  Index Scan (~10ms with 1000 result rows)
Improvement: 50x faster

Query: SELECT * FROM messages WHERE sender_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 50
```

#### User Content Timeline
```
Before: Sequential Scan (~200ms for 100k posts, 100 result rows)
After:  Index Scan (~5ms with 100 result rows)
Improvement: 40x faster

Query: SELECT * FROM posts WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 50
```

#### Feed Generation (with JOINs)
```
Before: Multiple Sequential Scans (~500ms)
After:  Mixed Index Scans (~100ms)
Improvement: 5x faster

This depends on the complete feed query structure, but the new indexes
enable the planner to optimize JOIN conditions better.
```

---

## Index Statistics

### Messages Index (`idx_messages_sender_created`)

```
Table: messages
Columns: sender_id, created_at DESC
Filter: deleted_at IS NULL

Column 1: sender_id (UUID) - High cardinality (each user is unique)
Column 2: created_at (TIMESTAMPTZ DESC) - Natural sort order for pagination

Estimated Size:
  - 100k rows: ~5-10MB
  - 1M rows: ~50-100MB
  - 10M rows: ~500MB-1GB

Typical Row Count: 50-1000 per user
Index Selectivity: High (~0.1% of total rows typically)
```

### Posts Index (`idx_posts_user_created`)

```
Table: posts
Columns: user_id, created_at DESC
Filter: deleted_at IS NULL

Column 1: user_id (UUID) - Medium cardinality (users post less frequently)
Column 2: created_at (TIMESTAMPTZ DESC) - Natural sort order

Estimated Size:
  - 100k rows: ~3-8MB
  - 500k rows: ~15-40MB
  - 1M rows: ~30-80MB

Typical Row Count: 10-100 per user (much lower than messages)
Index Selectivity: High (~1% of total rows typically)
```

---

## Monitoring During Usage

### Real-Time Index Performance

```sql
-- After running workload for 1-2 hours
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as scans_used,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_returned,
    CASE
        WHEN idx_scan = 0 THEN 'Not used yet'
        ELSE ROUND(100.0 * idx_tup_fetch / idx_tup_read, 2) || '%'
    END as efficiency
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
)
ORDER BY idx_scan DESC;

-- Interpretation:
-- idx_scan > 0: Index is being used ✓
-- efficiency ~90-100%: Index is highly selective ✓
-- idx_scan = 0: Index might not be needed (check query patterns)
```

### Cache Hit Ratio

```sql
-- Check if indexes are cached in memory
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as size,
    ROUND(heap_blks_read::numeric / (heap_blks_read + heap_blks_hit) * 100, 2) as cache_miss_pct
FROM pg_statio_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
);

-- Ideal: heap_blks_read ≈ 0 (all index pages in cache)
```

---

## Rollback Procedure

If performance regression is detected or other issues arise:

```sql
-- Safely rollback (no data loss)
DROP INDEX CONCURRENTLY IF EXISTS idx_messages_sender_created;
DROP INDEX CONCURRENTLY IF EXISTS idx_posts_user_created;

-- Update statistics
ANALYZE messages;
ANALYZE posts;

-- Verify rollback
SELECT indexname FROM pg_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created'
);

-- Expected: No results (indexes dropped)
```

---

## Troubleshooting

### Issue 1: Index Not Being Used Despite Existing

```sql
-- Check if statistics are outdated
ANALYZE messages;
ANALYZE posts;

-- Re-run EXPLAIN ANALYZE to verify planner has current stats
```

### Issue 2: Index Creation Timeout

```sql
-- Increase statement timeout for large tables
SET statement_timeout = '30 minutes';

-- Retry index creation with CONCURRENTLY flag
CREATE INDEX CONCURRENTLY idx_messages_sender_created
ON messages(sender_id, created_at DESC)
WHERE deleted_at IS NULL;
```

### Issue 3: High Index Memory Usage

```sql
-- Check individual index sizes
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE tablename IN ('messages', 'posts');

-- If sizes are concerning, verify:
-- 1. Indexes have proper filters (WHERE deleted_at IS NULL)
-- 2. No redundant indexes exist
-- 3. Consider partitioning if table is extremely large (>100GB)
```

### Issue 4: Queries Still Slow After Migration

```sql
-- Check actual execution plan with BUFFERS
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = 'user-uuid'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Common issues:
-- 1. WHERE filter selects too many rows (index unusable)
-- 2. ORDER BY not matching index order
-- 3. Statistics not updated (run ANALYZE)
-- 4. Index on wrong column
```

---

## Verification Checklist

- [ ] Pre-migration: Captured baseline EXPLAIN ANALYZE results
- [ ] Migration: Executed without errors
- [ ] Post-migration: Indexes created (pg_indexes query passed)
- [ ] Post-migration: Index sizes reasonable (< 20% of table)
- [ ] Performance: EXPLAIN ANALYZE shows Index Scan (not Sequential Scan)
- [ ] Performance: Query timing improved (target: 50x faster for messages)
- [ ] Monitoring: Set up alerts for index performance degradation
- [ ] Documentation: Updated team on new indexes in operation runbooks

---

## Next Steps (If Issues Found)

1. **Immediate**: Rollback indexes if causing issues
2. **Investigation**: Review query patterns using `pg_stat_statements`
3. **Refinement**: Consider additional indexes or query rewrites
4. **Optimization**: Profile slow queries with `EXPLAIN (ANALYZE, BUFFERS)`
5. **Documentation**: Update this guide with lessons learned

---

## Related Migrations

- `080_performance_optimization_p0.sql` - Added sequence numbers, denormalization
- `064_create_user_feed_preferences.sql` - User feed preferences table
- `018_messaging_schema.sql` - Initial messages table and basic indexes

---

## References

- [PostgreSQL Index Types](https://www.postgresql.org/docs/current/indexes-types.html)
- [EXPLAIN Documentation](https://www.postgresql.org/docs/current/sql-explain.html)
- [Index Performance Tuning](https://www.postgresql.org/docs/current/planner-stats.html)
- [CREATE INDEX CONCURRENTLY](https://www.postgresql.org/docs/current/sql-createindex.html)
