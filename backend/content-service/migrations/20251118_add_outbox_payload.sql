-- Align content-service outbox schema with shared transactional-outbox expectations.
-- Adds a `payload` JSONB column that mirrors the legacy `data` column so new
-- publishers/consumers can rely on the unified schema.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'outbox_events'
          AND column_name = 'payload'
    ) THEN
        ALTER TABLE outbox_events
            ADD COLUMN payload JSONB;

        -- Backfill existing rows so payload matches the previous `data` column.
        UPDATE outbox_events
        SET payload = data
        WHERE payload IS NULL;

        ALTER TABLE outbox_events
            ALTER COLUMN payload SET NOT NULL;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION outbox_events_payload_sync()
RETURNS TRIGGER AS $$
BEGIN
    -- Keep legacy `data` column and new `payload` column consistent until the
    -- expand/contract process finishes and `data` can be dropped.
    IF NEW.payload IS NULL THEN
        NEW.payload := NEW.data;
    ELSIF NEW.data IS NULL THEN
        NEW.data := NEW.payload;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS outbox_events_payload_sync ON outbox_events;

CREATE TRIGGER outbox_events_payload_sync
BEFORE INSERT OR UPDATE ON outbox_events
FOR EACH ROW
EXECUTE FUNCTION outbox_events_payload_sync();
