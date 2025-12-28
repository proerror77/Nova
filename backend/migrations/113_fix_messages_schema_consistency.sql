-- Migration 031: Fix messages table schema consistency
-- Problem: Code uses content_encrypted/content_nonce but DB has encrypted_content/nonce
-- Also missing sequence_number, encryption_version, idempotency_key
--
-- This migration:
-- 1. Adds missing columns to messages table
-- 2. Creates trigger for automatic search index synchronization
-- 3. Handles edit/delete operations for search consistency

-- Step 1: Add missing columns to messages table (if they don't exist)
ALTER TABLE IF EXISTS messages
ADD COLUMN IF NOT EXISTS content_encrypted BYTEA,
ADD COLUMN IF NOT EXISTS content_nonce BYTEA,
ADD COLUMN IF NOT EXISTS encryption_version INT DEFAULT 1,
ADD COLUMN IF NOT EXISTS idempotency_key UUID UNIQUE,
ADD COLUMN IF NOT EXISTS sequence_number BIGSERIAL;

-- Step 2: Migrate data from old columns to new columns (if needed)
DO $$
BEGIN
    -- Only migrate if old columns exist but new don't have data
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='encrypted_content') THEN
        UPDATE messages
        SET content_encrypted = DECODE(encrypted_content, 'escape')::BYTEA,
            content_nonce = DECODE(nonce, 'escape')::BYTEA
        WHERE content_encrypted IS NULL AND encrypted_content IS NOT NULL;
    END IF;
END $$;

-- Step 3: Create trigger to automatically sync message_search_index on edit
CREATE OR REPLACE FUNCTION sync_message_search_index_on_edit()
RETURNS TRIGGER AS $$
BEGIN
    -- When a message is edited, update its search index if it exists
    IF TG_OP = 'UPDATE' THEN
        UPDATE message_search_index
        SET created_at = COALESCE(NEW.edited_at, NEW.created_at)
        WHERE message_id = NEW.id;
    -- When a message is deleted (soft delete), remove it from search index
    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM message_search_index WHERE message_id = OLD.id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Drop old trigger if exists to avoid conflicts
DROP TRIGGER IF EXISTS message_search_sync_trigger ON messages;

-- Create trigger for UPDATE and soft DELETE (via deleted_at check)
CREATE TRIGGER message_search_sync_trigger
AFTER UPDATE OR DELETE ON messages
FOR EACH ROW
EXECUTE FUNCTION sync_message_search_index_on_edit();

-- Step 4: Also sync on soft delete by checking deleted_at
-- This requires a separate trigger that fires when deleted_at is set
CREATE OR REPLACE FUNCTION soft_delete_from_search_index()
RETURNS TRIGGER AS $$
BEGIN
    -- If deleted_at was just set (old value was NULL, new value is not NULL)
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        DELETE FROM message_search_index WHERE message_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS soft_delete_search_index_trigger ON messages;

CREATE TRIGGER soft_delete_search_index_trigger
AFTER UPDATE ON messages
FOR EACH ROW
EXECUTE FUNCTION soft_delete_from_search_index();

-- Step 5: Add index on idempotency_key for deduplication performance
CREATE INDEX IF NOT EXISTS idx_messages_idempotency_key ON messages(idempotency_key)
WHERE idempotency_key IS NOT NULL;

-- Step 6: Add index on edited_at for finding recently edited messages
CREATE INDEX IF NOT EXISTS idx_messages_edited_at ON messages(edited_at DESC)
WHERE edited_at IS NOT NULL;

-- Step 7: Verify that we can query by idempotency_key
-- No action needed - just a documentation comment
-- SELECT * FROM messages WHERE idempotency_key = '<uuid>';

-- Step 8: Migration verification query (can be run separately)
-- SELECT COUNT(*) as total,
--        COUNT(content_encrypted) as with_new_format,
--        COUNT(encrypted_content) as with_old_format
-- FROM messages;
