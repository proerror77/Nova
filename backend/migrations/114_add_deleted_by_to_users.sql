-- ============================================
-- Migration: 071_add_deleted_by_to_users
-- Description: Add deleted_by to users for audit trail and align with Outbox triggers
-- ============================================

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deleted_by UUID NULL;

-- Keep audit consistency: deleted_at/deleted_by should be both NULL or both NOT NULL
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_deleted_at_logic'
    ) THEN
        ALTER TABLE users
        ADD CONSTRAINT users_deleted_at_logic
        CHECK (
            (deleted_at IS NULL AND deleted_by IS NULL) OR
            (deleted_at IS NOT NULL AND deleted_by IS NOT NULL)
        );
    END IF;
END $$;

-- Reference deleter (could be another user or system actor); set NULL if deleter is removed
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_deleted_by'
    ) THEN
        ALTER TABLE users
        ADD CONSTRAINT fk_users_deleted_by
        FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL;
    END IF;
END $$;

COMMENT ON COLUMN users.deleted_by IS 'User ID who performed the soft delete. Used by Outbox trigger and audit trail.';

