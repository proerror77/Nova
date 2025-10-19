# ClickHouse Infrastructure for Nova Feed

Complete ClickHouse schema and query infrastructure for Phase 3 personalized feed ranking.

## 📁 Directory Structure

```
infra/clickhouse/
├── tables/              # Table DDL definitions
│   ├── events.sql                  # Main events table (MergeTree)
│   ├── posts_cdc.sql               # Posts CDC (ReplacingMergeTree)
│   ├── follows_cdc.sql             # Follows CDC (ReplacingMergeTree)
│   ├── comments_cdc.sql            # Comments CDC (ReplacingMergeTree)
│   ├── likes_cdc.sql               # Likes CDC (ReplacingMergeTree)
│   ├── post_metrics_1h.sql         # Hourly metrics (SummingMergeTree)
│   └── user_author_90d.sql         # User-author affinity (SummingMergeTree)
├── views/               # Materialized view definitions
│   ├── mv_events_to_table.sql      # Kafka events → events table
│   ├── mv_post_metrics_1h.sql      # events → post_metrics_1h
│   └── mv_user_author_90d.sql      # events → user_author_90d
├── engines/             # Kafka engine configurations
│   └── kafka_cdc.sql               # CDC topic consumers + MVs
├── queries/             # Query templates
│   └── feed_ranking_v1.sql         # Personalized feed ranking query
├── init_all.sql         # Complete initialization script
├── verify_setup.sql     # Setup verification script
└── README.md            # This file
```

## 🚀 Quick Start

### 1. Initialize All Tables and Views

```bash
# From project root
clickhouse-client \
  --host clickhouse \
  --port 9000 \
  --user default \
  --password clickhouse \
  --multiquery < infra/clickhouse/init_all.sql
```

### 2. Verify Setup

```bash
clickhouse-client \
  --host clickhouse \
  --multiquery < infra/clickhouse/verify_setup.sql
```

Expected output:
```
✅ Events table created
✅ All CDC tables created (4)
✅ Aggregation tables created (2)
✅ Kafka source tables created (5)
✅ Materialized views created (7)
```

### 3. Test Feed Ranking Query

```bash
# Replace {user_id} with actual UUID
clickhouse-client \
  --host clickhouse \
  --param_user_id='550e8400-e29b-41d4-a716-446655440000' \
  < infra/clickhouse/queries/feed_ranking_v1.sql
```

## 📊 Table Overview

### Events Table (Fact Table)
- **Engine**: MergeTree
- **Retention**: 30 days (TTL)
- **Write volume**: 10K-100K events/sec
- **Indexes**: bloom_filter on user_id, post_id, action
- **Partition**: By month (YYYYMM)
- **Order**: (user_id, event_time, event_id)

### CDC Tables (Change Data Capture)
All use **ReplacingMergeTree** with `_version` field:
- `posts_cdc`: Post creation/deletion from PostgreSQL
- `follows_cdc`: Follow relationships
- `comments_cdc`: Comment activity
- `likes_cdc`: Like interactions

**Critical**: Query CDC tables with explicit `_version` filtering (avoid `FINAL` in production).

### Aggregation Tables
- `post_metrics_1h`: Hourly post engagement metrics (SummingMergeTree)
  - Metrics: views, likes, comments, shares, dwell_ms, exposures
  - Window: 90 days retention
- `user_author_90d`: User-author affinity scores (SummingMergeTree)
  - Metrics: likes, comments, views, dwell_ms per (user_id, author_id)
  - Window: 120 days retention (90d + 30d grace period)

## 🔄 Data Flow

```
PostgreSQL
    ↓ (Debezium)
  Kafka Topics (nova.public.*)
    ↓ (Kafka Engine)
ClickHouse CDC Tables
    ↓ (Materialized Views)
Application Queries


Mobile/Web App
    ↓ (Event tracking)
  Kafka Topic (events)
    ↓ (Kafka Engine + MV)
ClickHouse events table
    ↓ (Materialized Views)
Aggregation Tables (post_metrics_1h, user_author_90d)
    ↓
Feed Ranking Query
```

## ⚡ Performance Characteristics

### Write Path
- **Events ingestion**: P95 ≤ 2s (Kafka → ClickHouse)
- **CDC replication**: P95 ≤ 3s (PostgreSQL → ClickHouse)
- **Aggregation latency**: ~100ms per batch

### Query Path
- **Feed ranking query**: P95 ≤ 800ms (target)
  - Followees posts: ~150ms
  - Trending posts: ~100ms
  - Affinity posts: ~200ms
  - Scoring + ranking: ~150ms

### Storage
- **Events table**: ~1TB/month (30-day retention = 1TB total)
- **CDC tables**: ~50GB (yearly retention)
- **Aggregations**: ~100GB (90-day metrics + affinity data)
- **Total**: ~1.2TB with compression

## 🛠️ Operational Commands

### Check Kafka Consumer Status
```sql
SELECT table, num_consumers, assignments
FROM system.kafka_consumers
WHERE database = 'nova_feed';
```

### Monitor Recent Events
```sql
SELECT
    count() AS event_count,
    max(event_time) AS latest_event,
    min(event_time) AS oldest_event
FROM nova_feed.events
WHERE event_time >= now() - INTERVAL 1 HOUR;
```

### Check Partition Size
```sql
SELECT
    table,
    partition,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(rows) AS rows
FROM system.parts
WHERE database = 'nova_feed' AND active = 1
GROUP BY table, partition
ORDER BY sum(bytes_on_disk) DESC;
```

### View Materialized View Refresh Rate
```sql
SELECT
    view_name,
    last_refresh_time,
    refresh_count
FROM system.query_log
WHERE type = 'QueryFinish'
    AND query LIKE '%mv_%'
    AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 20;
```

### Test Trending Posts Query
```sql
SELECT
    post_id,
    sum(views) AS total_views,
    sum(likes) AS total_likes,
    (sum(likes) / nullIf(sum(exposures), 0)) AS ctr
FROM nova_feed.post_metrics_1h
WHERE window_start >= now() - INTERVAL 6 HOUR
GROUP BY post_id
HAVING sum(exposures) > 100
ORDER BY (total_views * 2 + total_likes * 10) DESC
LIMIT 20;
```

## 🔧 Troubleshooting

### Issue: Kafka consumers not consuming
```sql
-- Check consumer lag
SELECT * FROM system.kafka_consumers WHERE database = 'nova_feed';

-- Check for errors in logs
SELECT * FROM system.text_log
WHERE logger_name LIKE '%Kafka%'
    AND level IN ('Error', 'Warning')
ORDER BY event_time DESC
LIMIT 50;
```

**Fix**: Restart ClickHouse or recreate Kafka table.

### Issue: Query is slow (> 800ms)
```sql
-- Enable query profiling
SET send_logs_level = 'trace';

-- Run query and check execution plan
EXPLAIN PLAN SELECT ... FROM nova_feed.events WHERE ...;
```

**Optimization**:
1. Verify indexes are created: `SELECT * FROM system.data_skipping_indices WHERE database = 'nova_feed';`
2. Check partition pruning: Ensure queries filter on `event_date` or `window_start`
3. Reduce candidate set: Limit each UNION branch to ≤100 rows

### Issue: CDC tables have stale data
```sql
-- Check latest _version in CDC table
SELECT post_id, max(_version), max(_ts_ms)
FROM nova_feed.posts_cdc
GROUP BY post_id
ORDER BY max(_ts_ms) DESC
LIMIT 10;
```

**Fix**: Verify Debezium connector is running and Kafka topics are receiving messages.

## 📈 Scaling Considerations

### Horizontal Scaling
- **Sharding**: Shard by `user_id` hash (consistent hashing)
- **Replication**: 3 replicas for high availability
- **Kafka partitions**: Increase to 8-16 for higher throughput

### Vertical Scaling
- **Memory**: 64GB+ RAM for large aggregations
- **CPU**: 16+ cores for parallel query execution
- **Disk**: NVMe SSD for low-latency reads

### Query Optimization
- **Caching**: Cache trending posts for 5 minutes (Redis)
- **Pre-computation**: Materialize user followee lists (PostgreSQL → Redis)
- **Batch queries**: Fetch feed for multiple users in one query

## 📝 Schema Evolution

### Adding New Event Types
1. Add to `action` enum in events table (no schema change needed)
2. Update aggregation logic in `mv_post_metrics_1h.sql`
3. Deploy new MV with `CREATE MATERIALIZED VIEW IF NOT EXISTS`

### Adding New CDC Tables
1. Create table in `tables/` directory
2. Add Kafka engine in `engines/kafka_cdc.sql`
3. Create MV for transformation
4. Run `SOURCE` command in ClickHouse

### Modifying Ranking Algorithm
1. Edit `queries/feed_ranking_v1.sql`
2. Test on staging environment
3. Deploy as new version (`feed_ranking_v2.sql`)
4. A/B test in production

## 🔗 Integration with Backend

### FastAPI Example
```python
from clickhouse_driver import Client

client = Client(host='clickhouse', port=9000, user='default', password='clickhouse')

def get_personalized_feed(user_id: str) -> list[dict]:
    query = open('infra/clickhouse/queries/feed_ranking_v1.sql').read()
    query = query.replace('{user_id}', user_id)

    results = client.execute(query)
    return [
        {
            'post_id': str(row[0]),
            'created_at': row[1],
            'source_type': row[2],
            'score': row[5]
        }
        for row in results
    ]
```

## 📚 References

- [ClickHouse MergeTree Engine](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- [ReplacingMergeTree for CDC](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Kafka Engine Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka)
- [Materialized Views Best Practices](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)

---

**Last Updated**: 2025-01-15
**Version**: 1.0
**Author**: Backend Architect
