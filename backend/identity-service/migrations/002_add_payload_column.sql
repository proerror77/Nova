-- 20251118_add_payload_column.sql
-- Purpose: align outbox_events schema with shared expectations by
-- providing a `payload` column that mirrors `event_data`.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'outbox_events'
          AND table_schema = 'public'
          AND column_name = 'payload'
    ) THEN
        ALTER TABLE outbox_events
            ADD COLUMN payload JSONB;

        -- Backfill historical rows so payload mirrors event_data
        UPDATE outbox_events
        SET payload = event_data
        WHERE payload IS NULL;

        ALTER TABLE outbox_events
            ALTER COLUMN payload SET NOT NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION outbox_events_sync_payload()
RETURNS TRIGGER AS $$
BEGIN
    -- Ensure both payload <-> event_data stay consistent
    IF NEW.payload IS NULL THEN
        NEW.payload := NEW.event_data;
    ELSIF NEW.event_data IS NULL THEN
        NEW.event_data := NEW.payload;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS outbox_events_payload_sync ON outbox_events;

CREATE TRIGGER outbox_events_payload_sync
BEFORE INSERT OR UPDATE ON outbox_events
FOR EACH ROW
EXECUTE FUNCTION outbox_events_sync_payload();
