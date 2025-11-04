-- ============================================
-- Migration: 068_add_message_encryption_versioning
-- Description: Add encryption versioning support to messages table
--
-- Problem: Messages table has encrypted_content and nonce but NO encryption metadata:
--          - No encryption_algorithm field (which version of AES-GCM?)
--          - No encryption_key_version field (which key was used?)
--
--          This causes:
--          1. Impossible key rotation (can't identify which messages need re-encryption)
--          2. Algorithm upgrade blocked (no way to track old vs new versions)
--          3. Compliance issues (can't audit encryption parameters)
--
-- Solution: Add encryption_algorithm and encryption_key_version fields.
--           Default to current algorithm/key version.
--           Create index for efficient key rotation queries.
--
-- Author: Nova Team (Linus-style architecture review)
-- Date: 2025-11-02
-- ============================================

-- Step 1: Add encryption algorithm column
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS encryption_algorithm VARCHAR(50) NOT NULL DEFAULT 'AES-GCM-256';

-- Step 2: Add encryption key version column (used for key rotation)
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS encryption_key_version INT NOT NULL DEFAULT 1;

-- Step 3: Add constraint to validate algorithm
ALTER TABLE messages
    ADD CONSTRAINT valid_encryption_algorithm
        CHECK (encryption_algorithm IN (
            'AES-GCM-256',      -- Current/default algorithm
            'AES-GCM-128',      -- Legacy
            'CHACHA20-POLY1305' -- Alternative
        ));

-- Step 4: Add constraint to validate key version
ALTER TABLE messages
    ADD CONSTRAINT valid_encryption_key_version
        CHECK (encryption_key_version > 0 AND encryption_key_version <= 100);

-- Step 5: Create index for key rotation queries
-- Queries like: SELECT * FROM messages WHERE encryption_key_version = 1
-- Used when rotating from key version 1 to version 2
CREATE INDEX idx_messages_encryption_key_version ON messages(encryption_key_version)
    WHERE deleted_at IS NULL;

-- Step 6: Create index for algorithm tracking
CREATE INDEX idx_messages_encryption_algorithm ON messages(encryption_algorithm)
    WHERE deleted_at IS NULL;

-- Step 7: Create composite index for key rotation queries
-- Efficiently find messages needing re-encryption
CREATE INDEX idx_messages_key_rotation ON messages(encryption_key_version, created_at DESC)
    WHERE deleted_at IS NULL;

-- Step 8: Create helper function to track encryption versions
CREATE OR REPLACE FUNCTION get_messages_by_encryption_version(p_version INT)
RETURNS TABLE (
    message_id UUID,
    conversation_id UUID,
    sender_id UUID,
    algorithm VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.conversation_id,
        m.sender_id,
        m.encryption_algorithm,
        m.created_at
    FROM messages m
    WHERE m.encryption_key_version = p_version
        AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Step 9: Create function to get key rotation status
CREATE OR REPLACE FUNCTION get_encryption_key_rotation_status()
RETURNS TABLE (
    key_version INT,
    algorithm VARCHAR(50),
    message_count BIGINT,
    oldest_message TIMESTAMP WITH TIME ZONE,
    newest_message TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.encryption_key_version,
        m.encryption_algorithm,
        COUNT(*),
        MIN(m.created_at),
        MAX(m.created_at)
    FROM messages m
    WHERE m.deleted_at IS NULL
    GROUP BY m.encryption_key_version, m.encryption_algorithm
    ORDER BY m.encryption_key_version DESC;
END;
$$ LANGUAGE plpgsql;

-- Step 10: Create procedure for key rotation
-- Example: CALL rotate_message_encryption_key(1, 2, 'AES-GCM-256')
-- This marks when a key rotation started so we can track progress
CREATE OR REPLACE PROCEDURE start_encryption_key_rotation(
    p_old_version INT,
    p_new_version INT,
    p_algorithm VARCHAR(50)
)
LANGUAGE SQL
AS $$
    -- Create a rotation log entry
    -- In real implementation, this would be in a separate encryption_rotations table
    -- For now, document the operation
    SELECT 'Key rotation started from version ' ||
           p_old_version || ' to version ' || p_new_version ||
           ' using algorithm ' || p_algorithm;
$$;

-- Step 11: Create helper view for monitoring encryption status
CREATE OR REPLACE VIEW message_encryption_status AS
SELECT
    COUNT(*) as total_messages,
    COUNT(CASE WHEN encryption_key_version = 1 THEN 1 END) as messages_key_v1,
    COUNT(CASE WHEN encryption_key_version = 2 THEN 1 END) as messages_key_v2,
    COUNT(CASE WHEN encryption_algorithm = 'AES-GCM-256' THEN 1 END) as messages_aes_gcm_256,
    COUNT(CASE WHEN encryption_algorithm = 'CHACHA20-POLY1305' THEN 1 END) as messages_chacha,
    MIN(created_at) as oldest_message,
    MAX(created_at) as newest_message
FROM messages
WHERE deleted_at IS NULL;

-- Step 12: Add comments for documentation
COMMENT ON COLUMN messages.encryption_algorithm IS
    'Algorithm used for encryption: AES-GCM-256 (default), AES-GCM-128 (legacy), or CHACHA20-POLY1305 (alternative)';

COMMENT ON COLUMN messages.encryption_key_version IS
    'Key version used for encryption. Used for key rotation: increment version when rotating to new key.';

COMMENT ON INDEX idx_messages_encryption_key_version IS
    'Index for key rotation queries: find all messages encrypted with specific key version';

-- Step 13: Log this migration
INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
VALUES (
    '068',
    'messages',
    'Added encryption_algorithm and encryption_key_version columns for key rotation support'
);

-- Step 14: Create audit table for encryption operations (optional, for compliance)
CREATE TABLE IF NOT EXISTS encryption_audit_log (
    id BIGSERIAL PRIMARY KEY,
    operation VARCHAR(50) NOT NULL,
    message_id UUID NOT NULL,
    old_key_version INT,
    new_key_version INT,
    algorithm VARCHAR(50),
    executed_at TIMESTAMP DEFAULT NOW(),
    executed_by VARCHAR(255)
);

CREATE INDEX idx_encryption_audit_message ON encryption_audit_log(message_id);
CREATE INDEX idx_encryption_audit_timestamp ON encryption_audit_log(executed_at DESC);
