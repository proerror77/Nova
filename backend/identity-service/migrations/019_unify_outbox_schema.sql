-- Migration: 019_unify_outbox_schema
-- Description: Align outbox_events schema with transactional-outbox library standard
-- Changes:
--   - Add payload column (library standard name for event_data)
--   - Add published_at column (library standard name for processed_at)
--   - Add metadata column for correlation/tracing
--   - Add last_error column for debugging
--   - Create sync trigger to keep old/new columns in sync during transition
--   - Update indexes to use new column names
--
-- Note: aggregate_id remains VARCHAR for backward compatibility (code handles UUID parsing)
-- Note: max_retries column kept for backward compatibility (now configured in processor)

-- Step 1: Add new columns with library-standard names
ALTER TABLE outbox_events
    ADD COLUMN IF NOT EXISTS payload JSONB,
    ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS metadata JSONB,
    ADD COLUMN IF NOT EXISTS last_error TEXT;

-- Step 2: Migrate data from old columns to new columns
UPDATE outbox_events
SET
    payload = event_data,
    published_at = processed_at
WHERE payload IS NULL AND event_data IS NOT NULL;

-- Step 3: Create sync trigger for transition period
-- This keeps both old and new columns in sync during rollout
CREATE OR REPLACE FUNCTION sync_outbox_columns()
RETURNS TRIGGER AS $$
BEGIN
    -- Sync old -> new
    IF NEW.payload IS NULL AND NEW.event_data IS NOT NULL THEN
        NEW.payload := NEW.event_data;
    END IF;
    IF NEW.published_at IS NULL AND NEW.processed_at IS NOT NULL THEN
        NEW.published_at := NEW.processed_at;
    END IF;
    -- Sync new -> old (for backwards compatibility)
    IF NEW.event_data IS NULL AND NEW.payload IS NOT NULL THEN
        NEW.event_data := NEW.payload;
    END IF;
    IF NEW.processed_at IS NULL AND NEW.published_at IS NOT NULL THEN
        NEW.processed_at := NEW.published_at;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS outbox_column_sync_trigger ON outbox_events;
CREATE TRIGGER outbox_column_sync_trigger
    BEFORE INSERT OR UPDATE ON outbox_events
    FOR EACH ROW
    EXECUTE FUNCTION sync_outbox_columns();

-- Step 4: Update indexes to use new column names
DROP INDEX IF EXISTS idx_outbox_unprocessed;
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON outbox_events (created_at, retry_count)
    WHERE published_at IS NULL;

-- Step 5: Add library-standard constraints
ALTER TABLE outbox_events
    DROP CONSTRAINT IF EXISTS chk_retry_count,
    DROP CONSTRAINT IF EXISTS chk_published_at;

ALTER TABLE outbox_events
    ADD CONSTRAINT chk_retry_count CHECK (retry_count >= 0),
    ADD CONSTRAINT chk_published_at CHECK (published_at IS NULL OR published_at >= created_at);

-- Step 6: Add documentation
COMMENT ON COLUMN outbox_events.payload IS 'Event data as JSON (library standard name)';
COMMENT ON COLUMN outbox_events.published_at IS 'Timestamp when event was successfully published to Kafka';
COMMENT ON COLUMN outbox_events.metadata IS 'Correlation ID, trace ID, user ID, etc.';
COMMENT ON COLUMN outbox_events.event_data IS 'DEPRECATED: Use payload instead. Kept for backwards compatibility.';
COMMENT ON COLUMN outbox_events.processed_at IS 'DEPRECATED: Use published_at instead. Kept for backwards compatibility.';

-- Note: After all services are updated to use new column names,
-- run migration 020 to drop deprecated columns and sync trigger:
--
-- DROP TRIGGER IF EXISTS outbox_column_sync_trigger ON outbox_events;
-- DROP FUNCTION IF EXISTS sync_outbox_columns();
-- ALTER TABLE outbox_events DROP COLUMN IF EXISTS event_data;
-- ALTER TABLE outbox_events DROP COLUMN IF EXISTS processed_at;
-- ALTER TABLE outbox_events DROP COLUMN IF EXISTS max_retries;
-- ALTER TABLE outbox_events DROP COLUMN IF EXISTS error_message;
