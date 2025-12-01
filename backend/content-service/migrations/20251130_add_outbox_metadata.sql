-- Add metadata column to outbox_events table
-- Required by transactional-outbox library which expects this column
-- for storing correlation_id, trace_id, user_id, etc.
--
-- Migration: 20251130_add_outbox_metadata
-- Service: content-service
-- Issue: "column 'metadata' does not exist" error from outbox processor

DO $$
BEGIN
    -- Add metadata column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'outbox_events'
          AND column_name = 'metadata'
    ) THEN
        ALTER TABLE outbox_events
            ADD COLUMN metadata JSONB;

        RAISE NOTICE 'Added metadata column to outbox_events table';
    ELSE
        RAISE NOTICE 'metadata column already exists in outbox_events table';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Add comment for documentation
COMMENT ON COLUMN outbox_events.metadata IS 'Optional metadata: correlation_id, trace_id, user_id, service name, etc.';
