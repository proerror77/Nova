-- ============================================
-- Kafka engine tables for CDC topics (Debezium)
-- Data flow: PostgreSQL → Debezium → Kafka → ClickHouse CDC tables
-- Format: Debezium JSON envelope
-- ============================================

-- Posts CDC from PostgreSQL
CREATE TABLE IF NOT EXISTS nova_feed.src_kafka_posts (
    payload String  -- Raw Debezium JSON envelope
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.posts',
    kafka_group_name = 'ch_posts_cdc',
    kafka_format = 'JSONAsString',  -- Read entire message as single string column
    kafka_num_consumers = 2,
    kafka_thread_per_consumer = 1,
    kafka_max_block_size = 16384,  -- CDC is lower volume: 16K rows/batch
    kafka_poll_timeout_ms = 5000;

-- Follows CDC
CREATE TABLE IF NOT EXISTS nova_feed.src_kafka_follows (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.follows',
    kafka_group_name = 'ch_follows_cdc',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 2,
    kafka_thread_per_consumer = 1,
    kafka_max_block_size = 16384,
    kafka_poll_timeout_ms = 5000;

-- Likes CDC
CREATE TABLE IF NOT EXISTS nova_feed.src_kafka_likes (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.likes',
    kafka_group_name = 'ch_likes_cdc',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 2,
    kafka_thread_per_consumer = 1,
    kafka_max_block_size = 16384,
    kafka_poll_timeout_ms = 5000;

-- Comments CDC
CREATE TABLE IF NOT EXISTS nova_feed.src_kafka_comments (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.comments',
    kafka_group_name = 'ch_comments_cdc',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 2,
    kafka_thread_per_consumer = 1,
    kafka_max_block_size = 16384,
    kafka_poll_timeout_ms = 5000;

-- ============================================
-- Materialized views: Kafka CDC → CDC tables
-- ============================================

-- Posts CDC MV
CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.mv_posts TO nova_feed.posts_cdc AS
SELECT
    toUUID(JSONExtractString(payload, 'after', 'id')) AS post_id,
    toUUID(JSONExtractString(payload, 'after', 'user_id')) AS user_id,
    parseDateTimeBestEffort(JSONExtractString(payload, 'after', 'created_at')) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _version,  -- Debezium timestamp as version
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _ts_ms
FROM nova_feed.src_kafka_posts
WHERE JSONHas(payload, 'after', 'id');  -- Skip tombstone records (op='d' without 'after')

-- Follows CDC MV
CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.mv_follows TO nova_feed.follows_cdc AS
SELECT
    toUUID(JSONExtractString(payload, 'after', 'follower_id')) AS follower_id,
    toUUID(JSONExtractString(payload, 'after', 'following_id')) AS following_id,
    parseDateTimeBestEffort(JSONExtractString(payload, 'after', 'created_at')) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _version,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _ts_ms
FROM nova_feed.src_kafka_follows
WHERE JSONHas(payload, 'after', 'follower_id');

-- Likes CDC MV
CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.mv_likes TO nova_feed.likes_cdc AS
SELECT
    toUUID(JSONExtractString(payload, 'after', 'user_id')) AS user_id,
    toUUID(JSONExtractString(payload, 'after', 'post_id')) AS post_id,
    parseDateTimeBestEffort(JSONExtractString(payload, 'after', 'created_at')) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _version,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _ts_ms
FROM nova_feed.src_kafka_likes
WHERE JSONHas(payload, 'after', 'user_id');

-- Comments CDC MV
CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.mv_comments TO nova_feed.comments_cdc AS
SELECT
    toUUID(JSONExtractString(payload, 'after', 'id')) AS comment_id,
    toUUID(JSONExtractString(payload, 'after', 'post_id')) AS post_id,
    toUUID(JSONExtractString(payload, 'after', 'user_id')) AS user_id,
    parseDateTimeBestEffort(JSONExtractString(payload, 'after', 'created_at')) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _version,
    toUInt64(JSONExtractString(payload, 'ts_ms')) AS _ts_ms
FROM nova_feed.src_kafka_comments
WHERE JSONHas(payload, 'after', 'id');

-- Debezium message format example:
-- {
--   "before": null,
--   "after": {
--     "id": "550e8400-e29b-41d4-a716-446655440000",
--     "user_id": "660e8400-e29b-41d4-a716-446655440000",
--     "created_at": "2025-01-15T14:30:00Z"
--   },
--   "op": "c",  -- c=create, u=update, d=delete
--   "ts_ms": 1737824400000
-- }

-- Monitoring queries:
-- SELECT count(), max(_ts_ms) FROM posts_cdc WHERE _ts_ms >= (toUnixTimestamp(now()) - 60) * 1000;
-- SELECT count() FROM system.kafka_consumers WHERE table LIKE 'src_kafka_%';
