-- Migration: 002_unify_notifications_soft_delete
-- Description: Replace is_deleted with deleted_at, add updated_at, and align indexes/triggers.

BEGIN;

-- Add updated_at column for notifications (used by application code)
ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- If legacy is_deleted exists, backfill deleted_at then drop the column
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'notifications'
          AND column_name = 'is_deleted'
    ) THEN
        UPDATE notifications
        SET deleted_at = COALESCE(deleted_at, NOW())
        WHERE is_deleted = TRUE AND deleted_at IS NULL;

        ALTER TABLE notifications DROP COLUMN is_deleted;
    END IF;
END $$;

-- Rebuild index that previously referenced is_deleted
DROP INDEX IF EXISTS idx_notifications_is_read_created_at;
CREATE INDEX IF NOT EXISTS idx_notifications_is_read_created_at
    ON notifications(is_read, created_at DESC)
    WHERE deleted_at IS NULL;

-- Ensure updated_at stays in sync on changes
DROP TRIGGER IF EXISTS update_notifications_updated_at ON notifications;
CREATE TRIGGER update_notifications_updated_at
    BEFORE UPDATE ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMIT;
