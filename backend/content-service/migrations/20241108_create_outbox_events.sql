-- Create outbox_events table for transactional outbox pattern
-- This table stores events to be published asynchronously to message brokers (Kafka)
-- Required by later migrations that add payload column support

CREATE TABLE IF NOT EXISTS outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(255) NOT NULL,     -- e.g., 'post', 'comment', 'like'
    aggregate_id UUID NOT NULL,               -- ID of the entity the event relates to
    event_type VARCHAR(255) NOT NULL,         -- e.g., 'created', 'updated', 'deleted'
    data JSONB NOT NULL,                      -- Event payload (legacy column)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,                 -- NULL until event is published
    retry_count INTEGER NOT NULL DEFAULT 0,   -- Number of publish attempts
    last_error TEXT                           -- Last error message if publish failed
);

-- Index for polling unpublished events
CREATE INDEX IF NOT EXISTS idx_outbox_events_unpublished
    ON outbox_events(created_at)
    WHERE published_at IS NULL;

-- Index for aggregate lookups
CREATE INDEX IF NOT EXISTS idx_outbox_events_aggregate
    ON outbox_events(aggregate_type, aggregate_id);

-- Comment
COMMENT ON TABLE outbox_events IS 'Transactional outbox for reliable event publishing';
