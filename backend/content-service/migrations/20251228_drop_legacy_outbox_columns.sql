-- Migration: 20251228_drop_legacy_outbox_columns
-- Description: Drop legacy outbox columns after expand/contract migration complete
--
-- Prerequisites:
--   1. All services using transactional_outbox library (uses `payload` column)
--   2. No direct SQL queries using legacy columns
--   3. Sync trigger has been running to keep columns in sync
--
-- What this migration does:
--   1. Drops the sync trigger that kept data<->payload in sync
--   2. Drops the sync function
--   3. Drops legacy columns: data (and any deprecated aliases)
--
-- Rollback:
--   If rollback is needed, recreate columns and sync trigger manually.

-- Step 1: Drop the sync trigger
DROP TRIGGER IF EXISTS outbox_events_payload_sync ON outbox_events;

-- Step 2: Drop the sync function
DROP FUNCTION IF EXISTS outbox_events_payload_sync();

-- Step 3: Drop legacy columns
ALTER TABLE outbox_events DROP COLUMN IF EXISTS data;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS event_data;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS processed_at;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS max_retries;
ALTER TABLE outbox_events DROP COLUMN IF EXISTS error_message;

-- Step 4: Add documentation
COMMENT ON COLUMN outbox_events.payload IS 'Event payload (JSONB) - library standard column name';

-- Verification query (run manually after migration):
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'outbox_events' ORDER BY ordinal_position;
--
-- Expected columns: id, aggregate_type, aggregate_id, event_type, payload,
--                   created_at, published_at, retry_count, last_error, metadata
