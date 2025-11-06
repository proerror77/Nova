-- ============================================================================
-- Events Service Database Schema
-- ============================================================================
-- This migration creates core tables for event sourcing and outbox pattern
--
-- Tables:
--   - outbox_events: Transactional outbox for reliable event publishing
--   - event_schemas: JSON schema registry for event validation
--   - kafka_topics: Topic configuration for event routing
--   - domain_events: Persisted event history (optional, for event sourcing)
-- ============================================================================

-- ============================================================================
-- 1. Outbox Events Table (Transactional Outbox Pattern)
-- ============================================================================
-- Purpose: Guarantees exactly-once event publishing to Kafka
-- Pattern:
--   1. Service writes to DB + outbox in same transaction
--   2. OutboxPublisher reads pending events and publishes to Kafka
--   3. Mark as published after Kafka confirms
-- ============================================================================

CREATE TABLE IF NOT EXISTS outbox_events (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Event identification
    event_type VARCHAR(255) NOT NULL,           -- e.g., "user.created", "post.published"
    aggregate_id VARCHAR(255) NOT NULL,         -- Entity ID that triggered event
    aggregate_type VARCHAR(100) NOT NULL,       -- Entity type (user, post, message)

    -- Event payload (JSON)
    data JSONB NOT NULL,                        -- Event data as JSON
    metadata JSONB,                             -- Optional metadata (correlation_id, etc.)

    -- Publishing control
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending|published|failed
    priority INTEGER NOT NULL DEFAULT 5,        -- 1-10, lower = higher priority
    retry_count INTEGER NOT NULL DEFAULT 0,     -- Number of publish attempts
    max_retries INTEGER NOT NULL DEFAULT 3,     -- Max retry attempts

    -- Error tracking
    last_error TEXT,                            -- Last error message if failed

    -- Kafka routing
    kafka_topic VARCHAR(255),                   -- Target Kafka topic (if specified)
    kafka_partition INTEGER,                    -- Target partition (if specified)
    kafka_key VARCHAR(255),                     -- Kafka message key (for ordering)

    -- Correlation/causation tracking
    correlation_id UUID,                        -- For tracing related events
    causation_id UUID,                          -- Event that caused this one

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,                   -- When successfully published
    next_retry_at TIMESTAMPTZ,                  -- When to retry if failed

    -- Constraints
    CONSTRAINT valid_status CHECK (status IN ('pending', 'published', 'failed')),
    CONSTRAINT valid_priority CHECK (priority BETWEEN 1 AND 10)
);

-- Indexes for outbox processing
CREATE INDEX idx_outbox_events_status_created
    ON outbox_events(status, created_at)
    WHERE status = 'pending';                    -- Fast lookup for pending events

CREATE INDEX idx_outbox_events_priority_created
    ON outbox_events(priority DESC, created_at ASC)
    WHERE status = 'pending';                    -- Priority-based processing

CREATE INDEX idx_outbox_events_retry
    ON outbox_events(next_retry_at)
    WHERE status = 'failed' AND retry_count < max_retries; -- Retry failed events

CREATE INDEX idx_outbox_events_aggregate
    ON outbox_events(aggregate_type, aggregate_id, created_at DESC); -- Query by entity

CREATE INDEX idx_outbox_events_type
    ON outbox_events(event_type, created_at DESC); -- Query by event type

CREATE INDEX idx_outbox_events_correlation
    ON outbox_events(correlation_id)
    WHERE correlation_id IS NOT NULL;            -- Trace related events


-- ============================================================================
-- 2. Event Schemas Table (JSON Schema Registry)
-- ============================================================================
-- Purpose: Validate event payloads against JSON schemas
-- Pattern:
--   1. Register schema on service startup
--   2. Validate events before publishing
--   3. Support schema evolution with versioning
-- ============================================================================

CREATE TABLE IF NOT EXISTS event_schemas (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Schema identification
    event_type VARCHAR(255) NOT NULL,           -- Event type this schema validates
    version INTEGER NOT NULL DEFAULT 1,         -- Schema version (for evolution)

    -- Schema definition (JSON Schema format)
    schema_json JSONB NOT NULL,                 -- JSON Schema (draft-07 or later)

    -- Metadata
    description TEXT,                           -- Human-readable description
    example_payload JSONB,                      -- Example valid payload

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT TRUE,    -- Whether this is active version

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(event_type, version)                 -- Only one schema per type+version
);

-- Indexes for schema lookup
CREATE INDEX idx_event_schemas_type_active
    ON event_schemas(event_type)
    WHERE is_active = TRUE;                      -- Fast lookup for active schemas


-- ============================================================================
-- 3. Kafka Topics Table (Topic Configuration)
-- ============================================================================
-- Purpose: Map event types to Kafka topics
-- Pattern:
--   1. Configure routing rules per event type
--   2. Support multi-topic publishing
--   3. Enable/disable topics dynamically
-- ============================================================================

CREATE TABLE IF NOT EXISTS kafka_topics (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Topic configuration
    topic_name VARCHAR(255) NOT NULL UNIQUE,    -- Kafka topic name
    event_types TEXT[] NOT NULL DEFAULT '{}',   -- Event types routed to this topic

    -- Kafka settings
    partitions INTEGER NOT NULL DEFAULT 3,       -- Number of partitions
    replication_factor INTEGER NOT NULL DEFAULT 3, -- Replication factor

    -- Retention
    retention_ms BIGINT,                        -- Message retention (milliseconds)

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT TRUE,    -- Whether topic is active

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for event type lookup
CREATE INDEX idx_kafka_topics_event_types
    ON kafka_topics USING GIN(event_types)
    WHERE is_active = TRUE;


-- ============================================================================
-- 4. Domain Events Table (Optional - Event Store)
-- ============================================================================
-- Purpose: Persist all events for event sourcing and audit trail
-- Pattern:
--   1. Store immutable event history
--   2. Rebuild aggregate state from events
--   3. Query event history for analytics/debugging
-- ============================================================================

CREATE TABLE IF NOT EXISTS domain_events (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Event identification
    event_type VARCHAR(255) NOT NULL,
    aggregate_id VARCHAR(255) NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,

    -- Event version (for schema evolution)
    event_version INTEGER NOT NULL DEFAULT 1,

    -- Event payload
    data JSONB NOT NULL,
    metadata JSONB,

    -- Ordering (for event sourcing reconstruction)
    sequence_number BIGSERIAL,                  -- Global ordering
    aggregate_version INTEGER NOT NULL,         -- Version within aggregate

    -- Correlation/causation
    correlation_id UUID,
    causation_id UUID,

    -- Actor tracking
    created_by VARCHAR(255),                    -- User/service that created event

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(aggregate_type, aggregate_id, aggregate_version) -- Ensure version consistency
);

-- Indexes for event sourcing queries
CREATE INDEX idx_domain_events_aggregate
    ON domain_events(aggregate_type, aggregate_id, aggregate_version ASC);

CREATE INDEX idx_domain_events_type
    ON domain_events(event_type, created_at DESC);

CREATE INDEX idx_domain_events_sequence
    ON domain_events(sequence_number ASC);

CREATE INDEX idx_domain_events_created
    ON domain_events(created_at DESC);


-- ============================================================================
-- 5. Event Subscriptions Table (Subscription Management)
-- ============================================================================
-- Purpose: Track which services subscribe to which events
-- Pattern:
--   1. Services register subscriptions
--   2. Events service routes events accordingly
--   3. Support multiple subscription types (push, pull, Kafka)
-- ============================================================================

CREATE TABLE IF NOT EXISTS event_subscriptions (
    -- Primary key
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Subscriber identification
    subscriber_service VARCHAR(255) NOT NULL,   -- Service name (e.g., "notification-service")

    -- Subscription configuration
    event_types TEXT[] NOT NULL,                -- Event types to subscribe to
    endpoint VARCHAR(500),                      -- gRPC endpoint or Kafka consumer group
    subscription_type VARCHAR(50) NOT NULL,     -- push_grpc|pull_grpc|kafka_consumer

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT valid_subscription_type
        CHECK (subscription_type IN ('push_grpc', 'pull_grpc', 'kafka_consumer'))
);

-- Indexes for subscription lookup
CREATE INDEX idx_event_subscriptions_service
    ON event_subscriptions(subscriber_service)
    WHERE is_active = TRUE;

CREATE INDEX idx_event_subscriptions_event_types
    ON event_subscriptions USING GIN(event_types)
    WHERE is_active = TRUE;


-- ============================================================================
-- Seed Data: Default Kafka Topics
-- ============================================================================

INSERT INTO kafka_topics (topic_name, event_types, partitions, replication_factor)
VALUES
    ('nova-events-user', ARRAY['user.created', 'user.updated', 'user.deleted'], 3, 3),
    ('nova-events-content', ARRAY['post.created', 'post.updated', 'post.deleted', 'comment.created'], 3, 3),
    ('nova-events-messaging', ARRAY['message.sent', 'message.read', 'conversation.created'], 3, 3),
    ('nova-events-social', ARRAY['follow.created', 'follow.deleted', 'like.created', 'like.deleted'], 3, 3)
ON CONFLICT (topic_name) DO NOTHING;


-- ============================================================================
-- Functions: Update timestamp triggers
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers to tables with updated_at
CREATE TRIGGER update_event_schemas_updated_at
    BEFORE UPDATE ON event_schemas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_kafka_topics_updated_at
    BEFORE UPDATE ON kafka_topics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_event_subscriptions_updated_at
    BEFORE UPDATE ON event_subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- Performance: Analyze tables for query planner
-- ============================================================================

ANALYZE outbox_events;
ANALYZE event_schemas;
ANALYZE kafka_topics;
ANALYZE domain_events;
ANALYZE event_subscriptions;
