-- Migration: 0031_add_conversation_metadata_and_soft_delete
-- Description: Add missing conversation metadata columns and soft-delete support.

BEGIN;

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS avatar_url TEXT,
    ADD COLUMN IF NOT EXISTS admin_key_version INT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_conversations_active_updated_at
    ON conversations(updated_at DESC)
    WHERE deleted_at IS NULL;

COMMIT;
