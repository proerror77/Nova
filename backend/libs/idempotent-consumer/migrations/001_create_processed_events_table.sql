-- Processed events table for idempotency tracking
-- This table ensures exactly-once processing of Kafka events across service restarts
CREATE TABLE IF NOT EXISTS processed_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(255) NOT NULL UNIQUE,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique index for fast O(1) event_id lookups (idempotency check)
CREATE UNIQUE INDEX IF NOT EXISTS idx_processed_events_event_id
    ON processed_events (event_id);

-- Index for efficient cleanup queries (DELETE WHERE processed_at < X)
CREATE INDEX IF NOT EXISTS idx_processed_events_processed_at
    ON processed_events (processed_at);

-- Table comment
COMMENT ON TABLE processed_events IS 'Tracks processed Kafka events for idempotency guarantees (exactly-once semantics)';
COMMENT ON COLUMN processed_events.event_id IS 'Unique identifier from Kafka message header or payload (must be globally unique)';
COMMENT ON COLUMN processed_events.processed_at IS 'Timestamp when event was successfully processed';
COMMENT ON COLUMN processed_events.metadata IS 'Optional metadata about processing (consumer group, partition, offset, correlation_id, etc.)';
