-- ============================================
-- Migration: 067_fix_messages_cascade
-- Description: Fix missing CASCADE on messages.sender_id foreign key
--
-- Problem: messages.sender_id references users(id) but has NO DELETE ACTION.
--          When a user is deleted (or soft-deleted), orphaned messages remain
--          causing:
--          1. FK constraint violations if user hard-delete is attempted
--          2. GDPR compliance issues (data tied to deleted user)
--          3. Data inconsistency (can't determine message author)
--
-- Current state: messages.sender_id doesn't explicitly define ON DELETE behavior
--
-- Solution: Add explicit ON DELETE CASCADE with comment explaining the choice.
--
-- Author: Nova Team (Linus-style architecture review)
-- Date: 2025-11-02
-- ============================================

-- Step 1: Check if constraint already exists
-- PostgreSQL requires dropping and recreating to modify foreign key behavior

-- Drop the old constraint (it has no name, so we need to find it)
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;

-- Step 2: Add the corrected foreign key with CASCADE
ALTER TABLE messages
    ADD CONSTRAINT fk_messages_sender_id_cascade
        FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE;

-- Step 3: Document the constraint
COMMENT ON CONSTRAINT fk_messages_sender_id_cascade ON messages IS
    'Foreign key to users with CASCADE delete. When a user is deleted, all their messages are cascaded deleted. This ensures referential integrity and GDPR compliance.';

-- Step 4: Verify the constraint is working by checking table structure
-- This is informational and will be visible in DESCRIBE/\d commands

-- Step 5: Create helper function to get messages by sender
CREATE OR REPLACE FUNCTION get_user_messages(p_user_id UUID)
RETURNS TABLE (
    message_id UUID,
    conversation_id UUID,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.conversation_id,
        m.encrypted_content,
        m.created_at
    FROM messages m
    WHERE m.sender_id = p_user_id
        AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Step 6: Create trigger to handle soft-delete of messages when user is soft-deleted
-- (In addition to hard-cascade, we also soft-delete for audit trail)
CREATE OR REPLACE FUNCTION cascade_delete_user_messages()
RETURNS TRIGGER AS $$
BEGIN
    -- If user is soft-deleted (NEW.deleted_at is set)
    -- Also soft-delete their messages for audit trail
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE messages
        SET deleted_at = NEW.deleted_at
        WHERE sender_id = NEW.id
            AND deleted_at IS NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_cascade_delete_user_messages'
    ) THEN
        CREATE TRIGGER trg_cascade_delete_user_messages
            AFTER UPDATE OF deleted_at ON users
            FOR EACH ROW
            EXECUTE FUNCTION cascade_delete_user_messages();
    END IF;
END $$;

-- Step 7: Verify data integrity - find any orphaned messages (should be none after constraint)
CREATE OR REPLACE VIEW orphaned_messages AS
SELECT
    m.id,
    m.conversation_id,
    m.sender_id,
    m.created_at
FROM messages m
WHERE NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = m.sender_id
);

-- Step 8: Create audit log entry for this migration
-- Documents schema changes for compliance and debugging
CREATE TABLE IF NOT EXISTS schema_migrations_log (
    id BIGSERIAL PRIMARY KEY,
    migration_number VARCHAR(50),
    table_name VARCHAR(255),
    change_description TEXT,
    executed_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
VALUES (
    '067',
    'messages',
    'Added ON DELETE CASCADE to messages.sender_id foreign key for referential integrity'
);

-- Step 9: Performance optimization - index on sender_id for cascade operations
CREATE INDEX IF NOT EXISTS idx_messages_sender_for_cascade ON messages(sender_id, deleted_at);
