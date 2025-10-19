# ClickHouse Quick Reference

## 🚀 One-Command Setup

```bash
# Initialize all tables, views, and Kafka engines
clickhouse-client --host clickhouse --port 9000 \
  --user default --password clickhouse \
  --multiquery < infra/clickhouse/init_all.sql
```

## ✅ Verification Commands

### Check All Tables
```sql
SELECT name, engine, total_rows, formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = 'nova_feed'
ORDER BY engine, name;
```

### Check Kafka Consumers
```sql
SELECT table, num_consumers, assignments
FROM system.kafka_consumers
WHERE database = 'nova_feed';
```

### Check Materialized Views
```sql
SELECT name, as_select
FROM system.tables
WHERE database = 'nova_feed' AND engine = 'MaterializedView';
```

### Check Recent Activity
```sql
USE nova_feed;

SELECT 'events' AS table, count() AS rows, max(event_time) AS latest FROM events
UNION ALL
SELECT 'posts_cdc', count(), max(created_at) FROM posts_cdc
UNION ALL
SELECT 'post_metrics_1h', count(), max(window_start) FROM post_metrics_1h;
```

## 🔍 Monitoring Queries

### Kafka Consumer Lag
```sql
SELECT
    table,
    num_consumers,
    assignments,
    exceptions
FROM system.kafka_consumers
WHERE database = 'nova_feed';
```

### Partition Health
```sql
SELECT
    table,
    partition,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(rows) AS rows,
    count() AS parts
FROM system.parts
WHERE database = 'nova_feed' AND active = 1
GROUP BY table, partition
ORDER BY table, partition;
```

### Query Performance
```sql
SELECT
    query_duration_ms,
    read_rows,
    read_bytes,
    query
FROM system.query_log
WHERE type = 'QueryFinish'
    AND database = 'nova_feed'
    AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10;
```

## 🧪 Test Queries

### Insert Test Event
```sql
INSERT INTO nova_feed.events
(event_id, event_time, user_id, post_id, author_id, action, dwell_ms, device, app_ver)
VALUES
(generateUUIDv4(), now(), toUUID('550e8400-e29b-41d4-a716-446655440000'),
 toUUID('660e8400-e29b-41d4-a716-446655440000'),
 toUUID('770e8400-e29b-41d4-a716-446655440000'),
 'view', 5000, 'ios', '1.0.0');
```

### Query Trending Posts
```sql
SELECT
    post_id,
    sum(views) AS total_views,
    sum(likes) AS total_likes,
    (sum(likes) / nullIf(sum(exposures), 0)) AS ctr
FROM nova_feed.post_metrics_1h
WHERE window_start >= now() - INTERVAL 6 HOUR
GROUP BY post_id
HAVING sum(exposures) > 10
ORDER BY (total_views * 2 + total_likes * 10) DESC
LIMIT 20;
```

### Query User Affinity
```sql
SELECT
    author_id,
    sum(likes) AS total_likes,
    sum(views) AS total_views,
    (sum(likes) * 10 + sum(views)) AS affinity_score
FROM nova_feed.user_author_90d
WHERE user_id = toUUID('550e8400-e29b-41d4-a716-446655440000')
GROUP BY author_id
ORDER BY affinity_score DESC
LIMIT 10;
```

### Test Feed Ranking (replace user_id)
```bash
clickhouse-client --host clickhouse \
  --query "$(sed 's/{user_id}/550e8400-e29b-41d4-a716-446655440000/' \
    infra/clickhouse/queries/feed_ranking_v1.sql)"
```

## 🛠️ Maintenance Commands

### Show Table Schema
```sql
SHOW CREATE TABLE nova_feed.events;
```

### Optimize Table (force merge)
```sql
OPTIMIZE TABLE nova_feed.post_metrics_1h FINAL;
```

### Drop and Recreate (reset)
```sql
DROP DATABASE IF EXISTS nova_feed;
-- Then run init_all.sql again
```

### Check TTL Expiration
```sql
SELECT
    table,
    engine_full
FROM system.tables
WHERE database = 'nova_feed' AND engine_full LIKE '%TTL%';
```

## 📊 Performance Tuning

### Check Index Usage
```sql
SELECT
    table,
    name AS index_name,
    type AS index_type,
    expr
FROM system.data_skipping_indices
WHERE database = 'nova_feed';
```

### Query Execution Plan
```sql
EXPLAIN PLAN
SELECT post_id, count() FROM nova_feed.events
WHERE user_id = toUUID('550e8400-e29b-41d4-a716-446655440000')
GROUP BY post_id;
```

### Memory Usage
```sql
SELECT
    formatReadableSize(sum(bytes)) AS memory_usage
FROM system.parts
WHERE database = 'nova_feed' AND active = 1;
```

## 🚨 Troubleshooting

### No Data in Tables?
```sql
-- Check Kafka connectivity
SELECT * FROM system.kafka_consumers WHERE database = 'nova_feed';

-- Check for errors
SELECT * FROM system.text_log
WHERE logger_name LIKE '%Kafka%' AND level = 'Error'
ORDER BY event_time DESC LIMIT 20;
```

### Slow Queries?
```sql
-- Enable profiling
SET send_logs_level = 'trace';

-- Check slow queries
SELECT query_duration_ms, query FROM system.query_log
WHERE type = 'QueryFinish' AND database = 'nova_feed'
ORDER BY query_duration_ms DESC LIMIT 10;
```

### Kafka Consumer Stopped?
```sql
-- Recreate Kafka table
DROP TABLE nova_feed.src_kafka_events;
-- Then run init_all.sql again
```

---

**Quick Links**:
- Full documentation: `infra/clickhouse/README.md`
- All verification checks: `infra/clickhouse/verify_setup.sql`
- Complete summary: `CLICKHOUSE_INFRASTRUCTURE_COMPLETE.md`
