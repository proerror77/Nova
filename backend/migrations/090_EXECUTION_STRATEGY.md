# Quick Win #4: Missing Database Indexes - Execution Strategy

**Status**: Ready for Production Deployment
**Risk Level**: LOW (additive only, no data changes)
**Rollback Risk**: MINIMAL (index-only changes)
**Timeline**: 5-15 minutes total

---

## Executive Summary

This migration adds two critical missing indexes to the Nova backend database:

1. **`idx_messages_sender_created`** - Accelerates user message history queries
2. **`idx_posts_user_created`** - Accelerates user content timeline queries

**Expected Impact:**
- Feed generation: 500ms → 100ms (80% improvement)
- User message history: 100-500ms → 10-20ms (10-25x faster)
- User content queries: 50-200ms → 5-10ms (10-20x faster)

---

## Pre-Deployment Checklist

### 1. Environment Validation (5 minutes)

```bash
# Verify PostgreSQL connection
psql -U postgres -d nova -c "SELECT version();"

# Check current database size
psql -U postgres -d nova -c "
SELECT
    pg_size_pretty(pg_database_size('nova')) as db_size,
    (SELECT count(*) FROM messages) as msg_count,
    (SELECT count(*) FROM posts) as post_count;
"

# Expected output:
# db_size | msg_count | post_count
# --------|-----------|----------
# ~50GB   | ~5M       | ~2M
```

### 2. Backup Strategy (Before Deployment)

```bash
# Full backup (recommended for production)
pg_dump -U postgres nova > backup_nova_$(date +%Y%m%d_%H%M%S).sql

# OR: Create WAL backup for point-in-time recovery
pg_basebackup -D ./nova_backup -Ft -z -P
```

### 3. Permissions Check

```bash
# Verify user has permission to create indexes
psql -U postgres -d nova -c "
SELECT current_user, has_database_privilege(current_database(), 'CONNECT');"
```

### 4. Downtime Assessment

- **Read queries**: Continue operating normally
- **Write queries**: Continue operating normally
- **Index building**: No locks with CONCURRENTLY flag
- **Expected downtime**: 0 minutes ✓

---

## Deployment Strategy

### Option 1: Fully Automated (Recommended for Most Deployments)

```bash
# All indexes created in parallel
psql -U postgres -d nova -f 090_quick_win_4_missing_indexes.sql

# Expected runtime: ~10-15 minutes total
# Both indexes created concurrently: ~5-10 minutes each
```

### Option 2: Sequential Deployment (Recommended for Critical Prod Systems)

Use this if you want to monitor each step:

```bash
# Step 1: Create messages index (5-10 minutes)
psql -U postgres -d nova -c "
CREATE INDEX CONCURRENTLY idx_messages_sender_created
ON messages(sender_id, created_at DESC)
WHERE deleted_at IS NULL;"

# Monitor progress
psql -U postgres -d nova -c "
SELECT phase, status FROM migration_log
WHERE name = '090_quick_win_4_missing_indexes';"

# Verify index created
psql -U postgres -d nova -c "
SELECT indexname FROM pg_indexes
WHERE indexname = 'idx_messages_sender_created';"

# Step 2: Create posts index (3-5 minutes)
psql -U postgres -d nova -c "
CREATE INDEX CONCURRENTLY idx_posts_user_created
ON posts(user_id, created_at DESC)
WHERE deleted_at IS NULL;"

# Step 3: Update statistics
psql -U postgres -d nova -c "
ANALYZE messages;
ANALYZE posts;
ANALYZE users;
ANALYZE user_feed_preferences;"

# Verify completion
psql -U postgres -d nova -c "
SELECT indexname, idx_scan
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created');"
```

### Option 3: Progressive Rollout (For Multi-Region Setups)

```bash
# Region 1: Apply immediately
psql -U postgres -d nova-region-1 -f 090_quick_win_4_missing_indexes.sql

# Monitor for 1 hour
sleep 3600

# Check metrics
psql -U postgres -d nova-region-1 -c "
SELECT indexname, idx_scan FROM pg_stat_user_indexes
WHERE indexname LIKE 'idx_%_sender%' OR indexname LIKE 'idx_%_user_created%';"

# Region 2: Apply if Region 1 stable
psql -U postgres -d nova-region-2 -f 090_quick_win_4_missing_indexes.sql

# Region 3: Apply after Region 2 validated
psql -U postgres -d nova-region-3 -f 090_quick_win_4_missing_indexes.sql
```

---

## Detailed Timeline (Full Deployment)

### Minute 0-2: Pre-checks

```bash
# Verify disk space (need ~2% of table size for indexes)
psql -U postgres -d nova -c "
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    (SELECT pg_size_pretty(pg_tablespace_size('pg_default'))) as available
FROM pg_tables
WHERE tablename IN ('messages', 'posts');"

# Expected: Available disk space > 5GB
```

### Minute 2-12: Index Creation

```
[Duration: 5-10 minutes for both indexes]

Process:
├─ idx_messages_sender_created: 3-7 minutes (if 5M messages)
└─ idx_posts_user_created: 2-3 minutes (if 2M posts)

Both run concurrently - total time is max of both, not sum
```

### Minute 12-15: Statistics & Verification

```bash
# Update table statistics (critical for query planner)
psql -U postgres -d nova -c "
ANALYZE messages;
ANALYZE posts;
ANALYZE users;
ANALYZE user_feed_preferences;"

# Final verification
psql -U postgres -d nova -c "
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created');"
```

---

## Deployment Validation

### Immediate Post-Deployment (Minute 15-20)

```bash
# 1. Verify indexes exist
psql -U postgres -d nova -c "
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created')
ORDER BY tablename, indexname;"

# Expected: 2 rows returned ✓

# 2. Test index is usable
psql -U postgres -d nova -c "
EXPLAIN (FORMAT JSON)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;" | grep -i "index scan" && echo "✓ Index is being used"

# 3. Check for NULL columns (would invalidate index)
psql -U postgres -d nova -c "
SELECT COUNT(*) as null_sender_ids FROM messages WHERE sender_id IS NULL;
SELECT COUNT(*) as null_user_ids FROM posts WHERE user_id IS NULL;"

# Expected: Both return 0 ✓
```

### Mid-Deployment Validation (30 minutes after)

```bash
# 1. Check query performance improvement
psql -U postgres -d nova -c "
EXPLAIN ANALYZE
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = '00000000-0000-0000-0000-000000000001'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;" > post_migration_explain.txt

# 2. Compare timing
# Expected: Planning time < 1ms, Execution time < 10ms

# 3. Monitor cache hit ratio
psql -U postgres -d nova -c "
SELECT
    schemaname,
    indexname,
    heap_blks_hit,
    heap_blks_read,
    ROUND(100 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2) as cache_hit_pct
FROM pg_statio_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created');"
```

### Long-Term Monitoring (1-24 hours after)

```bash
# 1. Check index usage statistics
psql -U postgres -d nova -c "
SELECT
    indexname,
    idx_scan as scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_returned,
    CASE WHEN idx_scan > 0
        THEN ROUND(100.0 * idx_tup_fetch / idx_tup_read, 2)
        ELSE 0
    END as efficiency_pct
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created')
ORDER BY idx_scan DESC;"

# Expected output:
# idx_messages_sender_created | 1000+ | 50000 | 48000 | 96.00
# idx_posts_user_created      | 500+  | 25000 | 24000 | 96.00

# Interpretation:
# ✓ idx_scan > 0: Index is being used
# ✓ efficiency > 90%: Index is highly selective
# ✗ idx_scan = 0 after 1 hour: Investigate query patterns

# 2. Monitor slow query log
psql -U postgres -d nova -c "
SELECT query, calls, mean_exec_time, max_exec_time
FROM pg_stat_statements
WHERE query LIKE '%messages%' OR query LIKE '%posts%'
ORDER BY mean_exec_time DESC
LIMIT 10;"

# Expected: Average query time significantly reduced
```

---

## Potential Issues & Mitigation

### Issue 1: Index Creation Hangs

**Symptom**: CREATE INDEX command doesn't complete after 30 minutes

**Mitigation**:
```sql
-- Check if index creation is blocked
SELECT pid, usename, query FROM pg_stat_activity
WHERE query LIKE '%CREATE INDEX%';

-- If blocked, find blocking process
SELECT blocking_pids FROM pg_blocking_pids() ORDER BY array_length(blocking_pids, 1) DESC;

-- Cancel blocking query (if long-running non-essential query)
SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE query = '<long-running-query>';

-- Retry index creation
CREATE INDEX CONCURRENTLY idx_messages_sender_created
ON messages(sender_id, created_at DESC)
WHERE deleted_at IS NULL;
```

### Issue 2: Disk Space Exhaustion

**Symptom**: Index creation fails with "No space left on device"

**Solution**:
```bash
# Check available space
df -h

# Cleanup old backups/logs if needed
rm -f backup_nova_*.sql  # Old backups
pg_dump -U postgres nova > backup_latest.sql  # Fresh backup first

# Ensure >5GB available
# OR: Add disk to PostgreSQL tablespace
# Then retry: CREATE INDEX CONCURRENTLY ...
```

### Issue 3: Index Not Used After Creation

**Symptom**: EXPLAIN still shows Sequential Scan even though index exists

**Solution**:
```sql
-- Force statistics update (query planner might have stale stats)
ANALYZE messages;
ANALYZE posts;

-- Check if planner cost settings favor index scans
SHOW random_page_cost;  -- Should be 1.0-2.0 for modern hardware
SHOW seq_page_cost;     -- Should be 1.0

-- If needed, tune cost parameters
SET random_page_cost = 1.1;  -- Encourage index scans

-- Disable sequential scans to force index usage (testing only!)
SET enable_seqscan = off;

-- Rerun EXPLAIN to verify index is chosen
EXPLAIN SELECT ...;

-- Re-enable sequential scans
SET enable_seqscan = on;
```

### Issue 4: Slow Queries After Migration

**Symptom**: Specific queries suddenly slower after indexes added

**Cause**: Query planner chose different execution plan that's suboptimal

**Solution**:
```sql
-- Detailed execution analysis
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT id, sender_id, content, created_at
FROM messages
WHERE sender_id = '...'
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 50;

-- Check what changed:
-- 1. Different index used?
-- 2. More rows scanned?
-- 3. More I/O operations?

-- If index hurt performance:
DROP INDEX CONCURRENTLY idx_messages_sender_created;
ANALYZE messages;

-- Investigate alternative:
-- 1. Is WHERE clause filtering enough rows?
-- 2. Should index include more columns?
-- 3. Is table statistics accurate?
```

---

## Rollback Procedure

If severe performance issues (rollback should be rare!):

### Fast Rollback (< 1 minute)

```bash
# Drop both indexes concurrently (no locks)
psql -U postgres -d nova -c "
DROP INDEX CONCURRENTLY IF EXISTS idx_messages_sender_created;
DROP INDEX CONCURRENTLY IF EXISTS idx_posts_user_created;"

# Update statistics
psql -U postgres -d nova -c "
ANALYZE messages;
ANALYZE posts;"

# Verify rollback successful
psql -U postgres -d nova -c "
SELECT indexname FROM pg_indexes
WHERE indexname IN (
    'idx_messages_sender_created',
    'idx_posts_user_created');"

# Expected: No results (indexes dropped)
```

### Data Safety

- ✓ No data loss possible (indexes are metadata only)
- ✓ Can rollback at any time without downtime
- ✓ Rollback takes < 1 minute

---

## Success Criteria

The migration is successful if:

- [ ] ✓ Both indexes created without errors
- [ ] ✓ Indexes visible in pg_indexes
- [ ] ✓ Indexes < 20% of respective table size
- [ ] ✓ EXPLAIN shows Index Scan for relevant queries
- [ ] ✓ Query execution time improved (target: 10-50x faster)
- [ ] ✓ No disk space issues
- [ ] ✓ No query timeouts
- [ ] ✓ No performance regression on other queries

---

## Communication Plan

### Before Deployment

```text
To: Engineering Team
Subject: Quick Win #4 Deployment - Database Index Optimization

Timeline: [DATE/TIME]
Expected Duration: 15 minutes
Downtime: 0 minutes
Rollback: < 1 minute if needed

What's Changing:
- Adding 2 missing database indexes for high-volume queries
- Feed queries expected to improve from 500ms → 100ms (80%)
- User message history queries 10-25x faster

No code changes, no migrations, no restarts required.
```

### After Deployment

```text
Quick Win #4 deployment completed successfully!

Performance improvements observed:
- Feed generation: 80% faster
- User message history: 10-25x faster
- Content queries: 10-20x faster

No issues detected. Indexes are actively being used.
```

---

## Monitoring & Alerting

### Prometheus Metrics to Add

```yaml
# Monitor index usage
pg_stat_user_indexes_idx_scan{indexname="idx_messages_sender_created"}
pg_stat_user_indexes_idx_scan{indexname="idx_posts_user_created"}

# Alert if index not used after 1 hour
alert: UnusedDatabaseIndex
condition: pg_stat_user_indexes_idx_scan == 0
duration: 1h
```

### Datadog/New Relic Query

```
# Index usage over time
SELECT indexname, idx_scan FROM pg_stat_user_indexes
WHERE indexname IN ('idx_messages_sender_created', 'idx_posts_user_created')

# Alert if idx_scan remains 0 after 1 hour of normal load
```

---

## Post-Deployment Documentation

Update the following:

- [ ] Architecture documentation (schema changes)
- [ ] Database operations runbook (new indexes)
- [ ] Performance baseline metrics (for future optimization)
- [ ] Alert thresholds (if monitoring added)
- [ ] Team wiki/knowledge base

---

## Approval & Sign-Off

- [ ] DBA Review: _______________
- [ ] Performance Team: _______________
- [ ] DevOps/Ops Team: _______________
- [ ] Engineering Lead: _______________

---

## Related Links

- [Migration File](./090_quick_win_4_missing_indexes.sql)
- [Verification Guide](./090_VERIFICATION_GUIDE.md)
- [PostgreSQL Index Documentation](https://www.postgresql.org/docs/current/sql-createindex.html)
- [Query Planner Documentation](https://www.postgresql.org/docs/current/planner.html)
