# Social Service Database Migrations

## Overview

This directory contains PostgreSQL schema migrations for the Social Service.

## Migration Files

### 001_initial_schema.sql (DEPRECATED)
- **Status**: Replaced by 002_create_social_tables.sql
- **Purpose**: Initial basic schema (no counters, no triggers)
- **Action**: Do not use in production

### 002_create_social_tables.sql (CURRENT)
- **Status**: Production-ready
- **Purpose**: Complete social interaction schema with:
  - 6 tables (likes, shares, comments, comment_likes, post_counters, processed_events)
  - 8 triggers for automatic counter maintenance
  - 18 indexes for query performance
  - CHECK constraints for data integrity
  - Foreign keys with CASCADE deletes

## Schema Design Philosophy

### 1. Counter Denormalization
- **Problem**: Counting likes/comments/shares on every query is expensive (SELECT COUNT(*))
- **Solution**: Maintain denormalized counters in `post_counters` table
- **Mechanism**: PostgreSQL triggers automatically update counters on INSERT/DELETE/UPDATE
- **Benefit**: O(1) counter reads, no application-level counter management

### 2. Soft Deletes for Comments
- **Why**: Preserve comment tree structure when parent comments are deleted
- **Implementation**: `is_deleted` boolean flag (default FALSE)
- **Query Pattern**: Always filter `WHERE is_deleted = FALSE` (index-backed)
- **Trigger Behavior**: Soft deletes decrement counters automatically

### 3. Idempotent Event Processing
- **Table**: `processed_events`
- **Purpose**: Exactly-once delivery guarantee for Kafka/event consumers
- **Usage**: Before processing event, check if `event_id` exists
- **Retention**: Auto-cleanup after 7 days (via `cleanup_old_processed_events()` function)

## Running Migrations

### Development
```bash
# Using sqlx-cli
cd backend/social-service
sqlx migrate run

# Or using psql directly
psql $DATABASE_URL -f migrations/002_create_social_tables.sql
```

### Production (Zero-Downtime)
```bash
# Step 1: Run migration on replica first
psql $REPLICA_DATABASE_URL -f migrations/002_create_social_tables.sql

# Step 2: Verify triggers work correctly
psql $REPLICA_DATABASE_URL -c "
    INSERT INTO likes (post_id, user_id) VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');
    SELECT * FROM post_counters WHERE post_id = '00000000-0000-0000-0000-000000000001';
"

# Step 3: Run on primary database
psql $DATABASE_URL -f migrations/002_create_social_tables.sql
```

## Verification Queries

### Check Trigger Setup
```sql
SELECT tgname, tgtype, tgenabled
FROM pg_trigger
WHERE tgrelid IN ('likes'::regclass, 'shares'::regclass, 'comments'::regclass, 'comment_likes'::regclass);
```

### Verify Indexes
```sql
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE tablename IN ('likes', 'shares', 'comments', 'post_counters', 'comment_likes', 'processed_events')
ORDER BY tablename, indexname;
```

### Test Counter Increment
```sql
-- Insert a like
INSERT INTO likes (post_id, user_id)
VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');

-- Check post_counters (should show like_count = 1)
SELECT * FROM post_counters WHERE post_id = '00000000-0000-0000-0000-000000000001';

-- Delete the like
DELETE FROM likes WHERE post_id = '00000000-0000-0000-0000-000000000001';

-- Check post_counters again (should show like_count = 0)
SELECT * FROM post_counters WHERE post_id = '00000000-0000-0000-0000-000000000001';
```

## Performance Considerations

### Indexes
- All foreign keys indexed for JOIN performance
- Temporal indexes (`created_at DESC`) for timeline queries
- Partial indexes (`WHERE is_deleted = FALSE`) to reduce index size
- Composite unique indexes prevent duplicate likes/shares per user

### Triggers
- All triggers are `AFTER` triggers (non-blocking for INSERT/DELETE)
- Counter updates use `ON CONFLICT DO UPDATE` (upsert) for efficiency
- `GREATEST(count - 1, 0)` prevents negative counters (edge case safety)

### Query Patterns
```sql
-- ✅ GOOD: Use post_counters for counts
SELECT like_count, comment_count, share_count
FROM post_counters
WHERE post_id = $1;

-- ❌ BAD: Count on every query
SELECT
    (SELECT COUNT(*) FROM likes WHERE post_id = $1) AS like_count,
    (SELECT COUNT(*) FROM comments WHERE post_id = $1) AS comment_count,
    (SELECT COUNT(*) FROM shares WHERE post_id = $1) AS share_count;
```

## Data Retention

### Processed Events Cleanup
Run this via cron job or scheduled task:
```sql
-- Clean events older than 7 days
SELECT cleanup_old_processed_events(7);

-- Clean events older than 30 days
SELECT cleanup_old_processed_events(30);
```

### Comment Soft Deletes
Comments are never hard-deleted to preserve tree structure. To permanently remove:
```sql
-- Hard delete soft-deleted comments older than 30 days
DELETE FROM comments
WHERE is_deleted = TRUE
  AND updated_at < NOW() - INTERVAL '30 days';
```

## Troubleshooting

### Counter Mismatch
If counters get out of sync (e.g., due to direct SQL manipulation):
```sql
-- Recalculate post counters
INSERT INTO post_counters (post_id, like_count, comment_count, share_count, updated_at)
SELECT
    p.post_id,
    COALESCE(l.like_count, 0),
    COALESCE(c.comment_count, 0),
    COALESCE(s.share_count, 0),
    NOW()
FROM (SELECT DISTINCT post_id FROM likes UNION SELECT DISTINCT post_id FROM comments UNION SELECT DISTINCT post_id FROM shares) p
LEFT JOIN (SELECT post_id, COUNT(*) AS like_count FROM likes GROUP BY post_id) l ON p.post_id = l.post_id
LEFT JOIN (SELECT post_id, COUNT(*) AS comment_count FROM comments WHERE is_deleted = FALSE GROUP BY post_id) c ON p.post_id = c.post_id
LEFT JOIN (SELECT post_id, COUNT(*) AS share_count FROM shares GROUP BY post_id) s ON p.post_id = s.post_id
ON CONFLICT (post_id) DO UPDATE
SET
    like_count = EXCLUDED.like_count,
    comment_count = EXCLUDED.comment_count,
    share_count = EXCLUDED.share_count,
    updated_at = NOW();
```

### Trigger Not Firing
Check trigger status:
```sql
-- Check if trigger is enabled
SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgname LIKE 'trigger_%';

-- Re-enable disabled trigger
ALTER TABLE likes ENABLE TRIGGER trigger_increment_like_count;
```

## References
- [PostgreSQL Triggers Documentation](https://www.postgresql.org/docs/current/sql-createtrigger.html)
- [Idempotent Consumer Pattern](https://www.enterpriseintegrationpatterns.com/patterns/messaging/IdempotentReceiver.html)
- [Database Denormalization Best Practices](https://en.wikipedia.org/wiki/Denormalization)
