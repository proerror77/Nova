-- Migration: 020_drop_legacy_outbox_columns
-- Description: Drop legacy outbox columns after expand/contract migration complete
--
-- Prerequisites:
--   1. Migration 019_unify_outbox_schema.sql has been applied
--   2. identity-service outbox.rs updated to use payload/published_at (done)
--   3. Sync trigger has been running to keep columns in sync
--
-- What this migration does:
--   1. Drops the sync trigger that kept old<->new columns in sync
--   2. Drops the sync function
--   3. Drops legacy columns: event_data, processed_at, max_retries, error_message
--
-- Rollback:
--   If rollback is needed, the columns can be recreated from 019 comments.

-- Step 1: Drop the sync trigger
DROP TRIGGER IF EXISTS outbox_column_sync_trigger ON outbox_events;

-- Step 2: Drop the sync function
DROP FUNCTION IF EXISTS sync_outbox_columns();

-- Step 3: Drop legacy columns
-- These were kept for backward compatibility during transition
ALTER TABLE outbox_events DROP COLUMN IF EXISTS event_data;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS processed_at;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS max_retries;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS error_message;

-- Step 4: Drop old index if exists
DROP INDEX IF EXISTS idx_outbox_unprocessed;

-- Step 5: Update column comments
COMMENT ON COLUMN outbox_events.payload IS 'Event payload (JSONB) - library standard column name';
COMMENT ON COLUMN outbox_events.published_at IS 'Timestamp when event was published to Kafka';

-- Verification query (run manually after migration):
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'outbox_events' ORDER BY ordinal_position;
--
-- Expected columns: id, aggregate_type, aggregate_id, event_type, payload,
--                   retry_count, created_at, published_at, metadata, last_error
