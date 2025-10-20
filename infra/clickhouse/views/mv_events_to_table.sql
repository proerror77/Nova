-- ============================================
-- Materialized view: Kafka events → events table
-- Data flow: Kafka topic 'events' → src_kafka_events → events table
-- Latency target: P95 ≤ 2s (part of 5s end-to-end SLA)
-- ============================================

-- Step 1: Create Kafka engine table (source)
CREATE TABLE IF NOT EXISTS nova_feed.src_kafka_events (
    event_time     DateTime64(3, 'UTC'),
    user_id        String,  -- UUID as string from JSON
    post_id        String,
    author_id      String,
    action         String,
    dwell_ms       UInt32,
    device         String,
    app_ver        String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'events',
    kafka_group_name = 'ch_events_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 4,  -- Parallel consumption (4 partitions assumed)
    kafka_thread_per_consumer = 1,
    kafka_max_block_size = 65536,  -- Batch size: 64K rows = ~2-5s at 10K events/sec
    kafka_poll_timeout_ms = 5000,
    kafka_skip_broken_messages = 100;  -- Skip malformed JSON (log to system.text_log)

-- Step 2: Create materialized view (transform + insert)
CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.mv_events TO nova_feed.events AS
SELECT
    generateUUIDv4() AS event_id,  -- Generate UUID for each event
    event_time,
    toDate(event_time) AS event_date,
    toUUID(user_id) AS user_id,
    toUUID(post_id) AS post_id,
    toUUID(author_id) AS author_id,
    action,
    dwell_ms,
    device,
    app_ver
FROM nova_feed.src_kafka_events;

-- Data flow explanation:
-- 1. Kafka producers write JSON to topic 'events'
-- 2. src_kafka_events table polls Kafka (4 consumers in parallel)
-- 3. mv_events transforms each batch (toUUID, add event_id, event_date)
-- 4. Batch INSERT into events table (MergeTree optimizes writes)
-- 5. Events available for querying within 2-5 seconds

-- Monitoring queries:
-- SELECT count() FROM system.kafka_consumers WHERE table = 'src_kafka_events';
-- SELECT * FROM system.text_log WHERE logger_name LIKE '%Kafka%' ORDER BY event_time DESC LIMIT 100;
-- SELECT count(), max(event_time) FROM events WHERE event_time >= now() - INTERVAL 1 MINUTE;
