-- ============================================
-- Migration: 066a_add_deleted_by_to_users_pre_outbox
-- Description: Ensure users.deleted_by exists before Outbox (067) triggers reference it
-- Note: Only adds column; constraints are handled in later migrations.
-- ============================================

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deleted_by UUID NULL;

-- Optional: add FK in later migration to avoid dependency timing issues

