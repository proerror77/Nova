-- ============================================
-- ClickHouse schema for Nova personalized feed
-- Run with: clickhouse-client --host clickhouse --user default --password clickhouse --queries-file init.sql
-- ============================================

CREATE DATABASE IF NOT EXISTS nova_feed;
USE nova_feed;

-- Behavior events (app instrumentation)
CREATE TABLE IF NOT EXISTS events (
    event_time    DateTime64(3, 'UTC'),
    event_date    Date DEFAULT toDate(event_time),
    user_id       UUID,
    post_id       UUID,
    author_id     UUID,
    action        LowCardinality(String),
    dwell_ms      UInt32,
    device        LowCardinality(String),
    app_ver       LowCardinality(String)
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_time)
TTL toDateTime(event_time) + INTERVAL 30 DAY DELETE;

-- CDC mirrors from Postgres (via Debezium Kafka topics)
CREATE TABLE IF NOT EXISTS posts_cdc (
    post_id     UUID,
    user_id     UUID,
    created_at  DateTime('UTC'),
    deleted     UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at);

CREATE TABLE IF NOT EXISTS follows_cdc (
    follower_id  UUID,
    following_id UUID,
    created_at   DateTime('UTC'),
    deleted      UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree
ORDER BY (follower_id, following_id);

CREATE TABLE IF NOT EXISTS likes_cdc (
    user_id   UUID,
    post_id   UUID,
    created_at DateTime('UTC'),
    deleted    UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree
ORDER BY (user_id, post_id);

CREATE TABLE IF NOT EXISTS comments_cdc (
    comment_id UUID,
    post_id    UUID,
    user_id    UUID,
    created_at DateTime('UTC'),
    deleted    UInt8 DEFAULT 0
) ENGINE = ReplacingMergeTree
ORDER BY (post_id, created_at);

-- Hourly post metrics (aggregations)
CREATE TABLE IF NOT EXISTS post_metrics_1h (
    post_id      UUID,
    window_start DateTime('UTC'),
    views        UInt64,
    likes        UInt64,
    comments     UInt64,
    shares       UInt64,
    dwell_ms_sum UInt64,
    exposures    UInt64
) ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(window_start)
ORDER BY (post_id, window_start)
TTL window_start + INTERVAL 90 DAY DELETE;

-- User → Author affinity (rolling 90 days)
CREATE TABLE IF NOT EXISTS user_author_90d (
    user_id   UUID,
    author_id UUID,
    likes     UInt64,
    comments  UInt64,
    views     UInt64,
    dwell_ms  UInt64,
    last_ts   DateTime('UTC')
) ENGINE = SummingMergeTree
ORDER BY (user_id, author_id)
TTL last_ts + INTERVAL 120 DAY DELETE;

-- ============================================
-- Kafka engines (source topics)
-- Update the topic names if they differ in your environment.
-- ============================================

CREATE TABLE IF NOT EXISTS src_kafka_events (
    event_time   DateTime64(3, 'UTC'),
    user_id      UUID,
    post_id      UUID,
    author_id    UUID,
    action       String,
    dwell_ms     UInt32,
    device       String,
    app_ver      String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'events',
    kafka_group_name = 'ch_events',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

CREATE TABLE IF NOT EXISTS src_kafka_posts (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.posts',
    kafka_group_name = 'ch_posts',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

CREATE TABLE IF NOT EXISTS src_kafka_follows (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.follows',
    kafka_group_name = 'ch_follows',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

CREATE TABLE IF NOT EXISTS src_kafka_likes (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.likes',
    kafka_group_name = 'ch_likes',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

CREATE TABLE IF NOT EXISTS src_kafka_comments (
    payload String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'nova.public.comments',
    kafka_group_name = 'ch_comments',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

-- ============================================
-- Materialized views
-- ============================================

-- Ingest events topic into fact table
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_events TO events AS
SELECT
    event_time,
    toUUID(user_id) AS user_id,
    toUUID(post_id) AS post_id,
    toUUID(author_id) AS author_id,
    action,
    dwell_ms,
    device,
    app_ver
FROM src_kafka_events;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_posts TO posts_cdc AS
SELECT
    toUUID(coalesce(JSON_VALUE(payload, '$.after.id'), JSON_VALUE(payload, '$.before.id'))) AS post_id,
    toUUID(coalesce(JSON_VALUE(payload, '$.after.user_id'), JSON_VALUE(payload, '$.before.user_id'))) AS user_id,
    parseDateTimeBestEffort(coalesce(JSON_VALUE(payload, '$.after.created_at'), JSON_VALUE(payload, '$.before.created_at'))) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted
FROM src_kafka_posts
WHERE coalesce(JSON_VALUE(payload, '$.after.id'), JSON_VALUE(payload, '$.before.id')) IS NOT NULL;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_follows TO follows_cdc AS
SELECT
    toUUID(coalesce(JSON_VALUE(payload, '$.after.follower_id'), JSON_VALUE(payload, '$.before.follower_id'))) AS follower_id,
    toUUID(coalesce(JSON_VALUE(payload, '$.after.following_id'), JSON_VALUE(payload, '$.before.following_id'))) AS following_id,
    parseDateTimeBestEffort(coalesce(JSON_VALUE(payload, '$.after.created_at'), JSON_VALUE(payload, '$.before.created_at'))) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted
FROM src_kafka_follows
WHERE coalesce(JSON_VALUE(payload, '$.after.follower_id'), JSON_VALUE(payload, '$.before.follower_id')) IS NOT NULL;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_likes TO likes_cdc AS
SELECT
    toUUID(coalesce(JSON_VALUE(payload, '$.after.user_id'), JSON_VALUE(payload, '$.before.user_id'))) AS user_id,
    toUUID(coalesce(JSON_VALUE(payload, '$.after.post_id'), JSON_VALUE(payload, '$.before.post_id'))) AS post_id,
    parseDateTimeBestEffort(coalesce(JSON_VALUE(payload, '$.after.created_at'), JSON_VALUE(payload, '$.before.created_at'))) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted
FROM src_kafka_likes
WHERE coalesce(JSON_VALUE(payload, '$.after.user_id'), JSON_VALUE(payload, '$.before.user_id')) IS NOT NULL;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_comments TO comments_cdc AS
SELECT
    toUUID(coalesce(JSON_VALUE(payload, '$.after.id'), JSON_VALUE(payload, '$.before.id'))) AS comment_id,
    toUUID(coalesce(JSON_VALUE(payload, '$.after.post_id'), JSON_VALUE(payload, '$.before.post_id'))) AS post_id,
    toUUID(coalesce(JSON_VALUE(payload, '$.after.user_id'), JSON_VALUE(payload, '$.before.user_id'))) AS user_id,
    parseDateTimeBestEffort(coalesce(JSON_VALUE(payload, '$.after.created_at'), JSON_VALUE(payload, '$.before.created_at'))) AS created_at,
    IF(JSONExtractString(payload, 'op') = 'd', 1, 0) AS deleted
FROM src_kafka_comments
WHERE coalesce(JSON_VALUE(payload, '$.after.id'), JSON_VALUE(payload, '$.before.id')) IS NOT NULL;

-- Hourly metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_post_metrics_1h TO post_metrics_1h AS
SELECT
    post_id,
    toStartOfHour(event_time) AS window_start,
    countIf(action = 'view')      AS views,
    countIf(action = 'like')      AS likes,
    countIf(action = 'comment')   AS comments,
    countIf(action = 'share')     AS shares,
    sumIf(dwell_ms, action = 'view') AS dwell_ms_sum,
    countIf(action = 'impression')   AS exposures
FROM events
GROUP BY post_id, window_start;

-- User → Author affinity (90-day rolling window)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_author_90d TO user_author_90d AS
SELECT
    user_id,
    author_id,
    countIf(action = 'like')    AS likes,
    countIf(action = 'comment') AS comments,
    countIf(action = 'view')    AS views,
    sumIf(dwell_ms, action = 'view') AS dwell_ms,
    max(event_time) AS last_ts
FROM events
WHERE event_time >= now() - INTERVAL 90 DAY
GROUP BY user_id, author_id;
