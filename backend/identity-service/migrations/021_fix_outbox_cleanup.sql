-- Migration: 021_fix_outbox_cleanup
-- Description: Remove legacy payload sync trigger and update outbox cleanup for published_at

-- Drop legacy payload sync trigger/function from migration 002 (references removed columns)
DROP TRIGGER IF EXISTS outbox_events_payload_sync ON outbox_events;
DROP FUNCTION IF EXISTS outbox_events_sync_payload();

-- Ensure legacy sync trigger/function is removed as well
DROP TRIGGER IF EXISTS outbox_column_sync_trigger ON outbox_events;
DROP FUNCTION IF EXISTS sync_outbox_columns();

-- Update cleanup function to use published_at
CREATE OR REPLACE FUNCTION cleanup_processed_outbox_events(retention_days INTEGER)
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM outbox_events
    WHERE published_at IS NOT NULL
      AND published_at < NOW() - make_interval(days => retention_days);

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;
