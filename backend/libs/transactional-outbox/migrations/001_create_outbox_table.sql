-- Transactional Outbox Table
-- Stores events that need to be published to Kafka after transaction commits
-- This ensures at-least-once delivery and prevents event loss

CREATE TABLE IF NOT EXISTS outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Aggregate identification
    aggregate_type VARCHAR(255) NOT NULL,  -- e.g., "user", "content", "feed"
    aggregate_id UUID NOT NULL,            -- ID of the entity this event relates to

    -- Event metadata
    event_type VARCHAR(255) NOT NULL,      -- e.g., "user.created", "content.published"
    payload JSONB NOT NULL,                -- Event data as JSON
    metadata JSONB,                        -- correlation_id, user_id, trace_id, etc.

    -- Lifecycle tracking
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,              -- NULL until successfully published to Kafka

    -- Retry handling
    retry_count INT NOT NULL DEFAULT 0,
    last_error TEXT,                       -- Store last error message for debugging

    -- Constraints
    CONSTRAINT chk_retry_count CHECK (retry_count >= 0),
    CONSTRAINT chk_published_at CHECK (published_at IS NULL OR published_at >= created_at)
);

-- Index for fetching unpublished events (used by background processor)
-- Partial index to only index unpublished events for efficiency
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON outbox_events (created_at, retry_count)
    WHERE published_at IS NULL;

-- Index for querying events by aggregate (useful for debugging/auditing)
CREATE INDEX IF NOT EXISTS idx_outbox_aggregate
    ON outbox_events (aggregate_type, aggregate_id, created_at);

-- Index for querying by event type (useful for metrics/monitoring)
CREATE INDEX IF NOT EXISTS idx_outbox_event_type
    ON outbox_events (event_type, created_at);

-- Add comments for documentation
COMMENT ON TABLE outbox_events IS 'Transactional outbox pattern: stores events to be published to Kafka';
COMMENT ON COLUMN outbox_events.aggregate_type IS 'Type of aggregate (e.g., user, content, feed)';
COMMENT ON COLUMN outbox_events.aggregate_id IS 'ID of the entity this event relates to';
COMMENT ON COLUMN outbox_events.event_type IS 'Fully qualified event name (e.g., user.created)';
COMMENT ON COLUMN outbox_events.payload IS 'Event data as JSON';
COMMENT ON COLUMN outbox_events.metadata IS 'Correlation ID, trace ID, user ID, etc.';
COMMENT ON COLUMN outbox_events.published_at IS 'Timestamp when event was successfully published to Kafka';
COMMENT ON COLUMN outbox_events.retry_count IS 'Number of failed publish attempts';
COMMENT ON COLUMN outbox_events.last_error IS 'Last error message from failed publish attempt';
