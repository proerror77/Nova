-- ============================================
-- Kafka Engine Tables for Event Ingestion
-- Version: 1.0.0
-- Date: 2025-10-18
-- Purpose: Consume events from Kafka topics
-- ============================================

USE nova_analytics;

-- ============================================
-- Configuration Variables
-- ============================================
-- These can be overridden via environment variables:
-- - KAFKA_BROKER: Default kafka:9092 (docker-compose) or kafka.prod:9093 (production)
-- - KAFKA_GROUP_PREFIX: Default clickhouse-consumer (can add env suffix)
-- - KAFKA_COMMIT_INTERVAL: Default 1000 (commit every 1000 messages)

-- ============================================
-- 1. Kafka Engine: Events Topic
-- Topic: events
-- Format: JSONEachRow
-- Schema: Must match events table exactly
-- ============================================
CREATE TABLE IF NOT EXISTS events_kafka (
  event_id UUID,
  user_id UUID,
  post_id Nullable(UUID),
  event_type String,
  author_id Nullable(UUID),
  dwell_ms Nullable(UInt32),
  created_at DateTime
) ENGINE = Kafka()
SETTINGS
  kafka_broker_list = '${KAFKA_BROKER:kafka:9092}',
  kafka_topic_list = 'events',
  kafka_group_name = '${KAFKA_GROUP_PREFIX:clickhouse-consumer}-events',
  kafka_format = 'JSONEachRow',
  kafka_num_consumers = 2,                     -- Parallel consumers per table
  kafka_max_block_size = 1048576,              -- 1MB batches for efficiency
  kafka_skip_broken_messages = 100,            -- Skip up to 100 broken messages
  kafka_commit_every_batch = 1,                -- Commit after every batch
  kafka_thread_per_consumer = 1;

-- ============================================
-- 2. Kafka Engine: Posts CDC Topic
-- Topic: postgres.public.posts (Debezium format)
-- Format: JSONEachRow
-- Schema: Includes __op and __version fields
-- ============================================
CREATE TABLE IF NOT EXISTS posts_kafka (
  id UUID,
  user_id UUID,
  caption String,
  image_key String,
  status String,
  created_at DateTime,
  updated_at DateTime,
  soft_delete Nullable(DateTime),
  __op String,
  __deleted UInt8,
  __version UInt64
) ENGINE = Kafka()
SETTINGS
  kafka_broker_list = '${KAFKA_BROKER:kafka:9092}',
  kafka_topic_list = 'postgres.public.posts',
  kafka_group_name = '${KAFKA_GROUP_PREFIX:clickhouse-consumer}-posts-cdc',
  kafka_format = 'JSONEachRow',
  kafka_num_consumers = 1,                     -- Single consumer for CDC (order matters)
  kafka_max_block_size = 524288,               -- 512KB (smaller batches for CDC)
  kafka_skip_broken_messages = 10,             -- Fewer skips for CDC (critical data)
  kafka_commit_every_batch = 1,
  kafka_thread_per_consumer = 1;

-- ============================================
-- 3. Kafka Engine: Follows CDC Topic
-- Topic: postgres.public.follows
-- Format: JSONEachRow
-- ============================================
CREATE TABLE IF NOT EXISTS follows_kafka (
  id UUID,
  follower_id UUID,
  following_id UUID,
  created_at DateTime,
  __op String,
  __deleted UInt8,
  __version UInt64
) ENGINE = Kafka()
SETTINGS
  kafka_broker_list = '${KAFKA_BROKER:kafka:9092}',
  kafka_topic_list = 'postgres.public.follows',
  kafka_group_name = '${KAFKA_GROUP_PREFIX:clickhouse-consumer}-follows-cdc',
  kafka_format = 'JSONEachRow',
  kafka_num_consumers = 1,
  kafka_max_block_size = 524288,
  kafka_skip_broken_messages = 10,
  kafka_commit_every_batch = 1,
  kafka_thread_per_consumer = 1;

-- ============================================
-- 4. Kafka Engine: Comments CDC Topic
-- Topic: postgres.public.comments
-- Format: JSONEachRow
-- ============================================
CREATE TABLE IF NOT EXISTS comments_kafka (
  id UUID,
  post_id UUID,
  user_id UUID,
  content String,
  parent_comment_id Nullable(UUID),
  created_at DateTime,
  updated_at DateTime,
  soft_delete Nullable(DateTime),
  __op String,
  __deleted UInt8,
  __version UInt64
) ENGINE = Kafka()
SETTINGS
  kafka_broker_list = '${KAFKA_BROKER:kafka:9092}',
  kafka_topic_list = 'postgres.public.comments',
  kafka_group_name = '${KAFKA_GROUP_PREFIX:clickhouse-consumer}-comments-cdc',
  kafka_format = 'JSONEachRow',
  kafka_num_consumers = 1,
  kafka_max_block_size = 524288,
  kafka_skip_broken_messages = 10,
  kafka_commit_every_batch = 1,
  kafka_thread_per_consumer = 1;

-- ============================================
-- 5. Kafka Engine: Likes CDC Topic
-- Topic: postgres.public.likes
-- Format: JSONEachRow
-- ============================================
CREATE TABLE IF NOT EXISTS likes_kafka (
  id UUID,
  user_id UUID,
  post_id UUID,
  created_at DateTime,
  __op String,
  __deleted UInt8,
  __version UInt64
) ENGINE = Kafka()
SETTINGS
  kafka_broker_list = '${KAFKA_BROKER:kafka:9092}',
  kafka_topic_list = 'postgres.public.likes',
  kafka_group_name = '${KAFKA_GROUP_PREFIX:clickhouse-consumer}-likes-cdc',
  kafka_format = 'JSONEachRow',
  kafka_num_consumers = 1,
  kafka_max_block_size = 524288,
  kafka_skip_broken_messages = 10,
  kafka_commit_every_batch = 1,
  kafka_thread_per_consumer = 1;

-- ============================================
-- Kafka Settings Explanation
-- ============================================
--
-- kafka_broker_list:
--   - Development: kafka:9092 (docker-compose service name)
--   - Production: kafka.prod:9093 (use environment variable)
--   - Can specify multiple brokers: 'broker1:9092,broker2:9092'
--
-- kafka_topic_list:
--   - Single topic per Kafka engine table
--   - CDC topics follow Debezium naming: postgres.public.<table_name>
--
-- kafka_group_name:
--   - Unique consumer group per table
--   - Allows independent offset tracking
--   - Add environment suffix for multi-env deployments
--
-- kafka_format:
--   - JSONEachRow: One JSON object per line (newline-delimited)
--   - Alternative: Avro (requires schema registry)
--
-- kafka_num_consumers:
--   - Events: 2 consumers for high throughput
--   - CDC: 1 consumer to preserve order (critical for updates)
--   - Max: Match Kafka topic partition count
--
-- kafka_max_block_size:
--   - Events: 1MB (optimize for throughput)
--   - CDC: 512KB (balance latency vs throughput)
--   - Larger = better compression, higher latency
--
-- kafka_skip_broken_messages:
--   - Events: 100 (tolerate malformed analytics data)
--   - CDC: 10 (stricter validation for critical data)
--   - 0 = fail on first error (production CDC should use 0)
--
-- kafka_commit_every_batch:
--   - 1 = commit after every batch (at-least-once delivery)
--   - 0 = commit based on internal buffer (faster but risky)
--
-- kafka_thread_per_consumer:
--   - 1 = recommended for most cases
--   - 0 = use shared thread pool (advanced use case)

-- ============================================
-- Error Handling Strategy
-- ============================================
--
-- 1. Broken Message Handling:
--    - kafka_skip_broken_messages > 0 allows skipping malformed JSON
--    - Monitor system.kafka_consumers for parse errors
--    - Set up alerting when skip count exceeds threshold
--
-- 2. Offset Management:
--    - Offsets stored in Kafka (__consumer_offsets topic)
--    - View current offsets: SELECT * FROM system.kafka_consumers
--    - Manual offset reset (if needed):
--      - Stop ClickHouse
--      - kafka-consumer-groups --reset-offsets --group <group_name> --topic <topic> --to-earliest
--      - Restart ClickHouse
--
-- 3. Backpressure Handling:
--    - If ClickHouse can't keep up, consumer lag increases
--    - Monitor lag: kafka-consumer-groups --describe --group <group_name>
--    - Solutions:
--      a) Increase kafka_num_consumers (up to partition count)
--      b) Increase ClickHouse hardware resources
--      c) Optimize materialized view queries
--
-- 4. Schema Evolution:
--    - Add new fields to Kafka engine table (non-breaking)
--    - Nullable columns for optional fields
--    - Drop/recreate Kafka table to reset consumer group (breaks offset tracking)

-- ============================================
-- Monitoring Queries
-- ============================================
--
-- Check consumer status:
-- SELECT
--   database,
--   table,
--   consumer_number,
--   assignments.topic_name,
--   assignments.partition_id,
--   assignments.current_offset,
--   exceptions.time,
--   exceptions.text
-- FROM system.kafka_consumers
-- WHERE database = 'nova_analytics';
--
-- Check message consumption rate (last hour):
-- SELECT
--   table,
--   count() as messages_consumed,
--   count() / 3600 as messages_per_second
-- FROM system.query_log
-- WHERE event_date = today()
--   AND event_time > now() - INTERVAL 1 HOUR
--   AND query_kind = 'Insert'
--   AND tables LIKE '%kafka%'
-- GROUP BY table;
--
-- Check for parse errors (broken messages):
-- SELECT
--   consumer_number,
--   partition_id,
--   count() as error_count,
--   any(exception_text) as sample_error
-- FROM system.kafka_consumers
-- WHERE database = 'nova_analytics'
--   AND length(exception_text) > 0
-- GROUP BY consumer_number, partition_id;

-- ============================================
-- Production Checklist
-- ============================================
-- [ ] Set KAFKA_BROKER to production Kafka cluster
-- [ ] Use environment-specific consumer group names
-- [ ] Set kafka_skip_broken_messages = 0 for CDC topics
-- [ ] Enable Kafka ACLs for topic access control
-- [ ] Set up monitoring for consumer lag
-- [ ] Configure alerting for parse errors
-- [ ] Test offset reset procedure in staging
-- [ ] Document rollback procedure for schema changes
-- [ ] Enable Kafka message compression (producer-side)
-- [ ] Configure retention policy on Kafka topics (7 days recommended)

-- ============================================
-- Development Notes
-- ============================================
-- To test Kafka ingestion locally:
--
-- 1. Start Kafka in docker-compose:
--    docker-compose up -d kafka zookeeper
--
-- 2. Create test topics:
--    docker exec -it nova-kafka kafka-topics.sh --create \
--      --topic events --partitions 2 --replication-factor 1 \
--      --bootstrap-server localhost:9092
--
-- 3. Produce test event:
--    echo '{"event_id":"123e4567-e89b-12d3-a456-426614174000","user_id":"223e4567-e89b-12d3-a456-426614174000","event_type":"view","created_at":"2025-10-18 10:00:00"}' | \
--    docker exec -i nova-kafka kafka-console-producer.sh \
--      --topic events --bootstrap-server localhost:9092
--
-- 4. Verify consumption in ClickHouse:
--    SELECT * FROM events WHERE event_id = '123e4567-e89b-12d3-a456-426614174000';
