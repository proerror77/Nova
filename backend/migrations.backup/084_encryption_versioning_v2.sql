-- ============================================
-- Migration: 068_encryption_versioning_v2
--
-- Changes from v1:
-- - Use ENUM for encryption_version (saves 96% space)
-- - Move algorithm details to config table
-- - Optimize for key rotation queries
--
-- Linus Principle: "Bad programmers worry about code. Good programmers worry about data structures."
-- Store version number (1 byte), not algorithm name (32 bytes).
--
-- Space Savings:
-- 1 billion messages × 32 bytes = 32 GB
-- 1 billion messages × 1 byte = 1 GB
-- Savings: 96%
--
-- Author: Nova Team + Database Architect Review
-- Date: 2025-11-02
-- ============================================

-- Step 1: Create ENUM type for encryption version
-- Using ENUM because there are only 2-3 versions in practice
-- ENUM takes 1 byte, VARCHAR(50) takes ~32 bytes
CREATE TYPE encryption_version_type AS ENUM (
    'v1_aes_256',
    'v2_aes_256',
    'v3_chacha'
);

-- Step 2: Add encryption versioning columns
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS encryption_version encryption_version_type DEFAULT 'v1_aes_256',
    ADD COLUMN IF NOT EXISTS encryption_key_generation INT DEFAULT 1;

-- Step 3: Create encryption_keys configuration table
-- This is the single source of truth for algorithm details
-- Application queries this, not individual message rows
CREATE TABLE IF NOT EXISTS encryption_keys (
    version_name encryption_version_type PRIMARY KEY,
    algorithm VARCHAR(50) NOT NULL,        -- 'AES-GCM-256', 'CHACHA20-POLY1305'
    key_bits INT NOT NULL,                 -- 256
    created_at TIMESTAMP DEFAULT NOW(),
    deprecated_at TIMESTAMP NULL,          -- When this version stopped being used for new encryptions
    rotated_to_version encryption_version_type,  -- Points to next version for migration
    active BOOLEAN DEFAULT TRUE              -- Use for new messages?
);

-- Step 4: Populate encryption_keys table
INSERT INTO encryption_keys (version_name, algorithm, key_bits, created_at, rotated_to_version, active)
VALUES
    ('v1_aes_256', 'AES-GCM-256', 256, NOW(), 'v2_aes_256', FALSE),
    ('v2_aes_256', 'AES-GCM-256', 256, NOW(), 'v3_chacha', FALSE),
    ('v3_chacha', 'CHACHA20-POLY1305', 256, NOW(), NULL, TRUE)
ON CONFLICT (version_name) DO NOTHING;

-- Step 5: Add indexes for key rotation queries
-- These are the queries used during key rotation process
CREATE INDEX IF NOT EXISTS idx_messages_encryption_version
    ON messages(encryption_version, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_messages_need_rotation
    ON messages(created_at DESC)
    WHERE encryption_version = 'v1_aes_256'
        AND deleted_at IS NULL;

-- Step 6: Create helper function for key rotation
-- Returns messages that need to be re-encrypted
CREATE OR REPLACE FUNCTION get_messages_needing_rotation(
    p_from_version encryption_version_type,
    p_to_version encryption_version_type,
    p_limit INT DEFAULT 1000
)
RETURNS TABLE (
    message_id UUID,
    conversation_id UUID,
    sender_id UUID,
    created_at TIMESTAMP WITH TIME ZONE,
    encrypted_content TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.conversation_id,
        m.sender_id,
        m.created_at,
        m.encrypted_content
    FROM messages m
    WHERE m.encryption_version = p_from_version
        AND m.deleted_at IS NULL
    ORDER BY m.created_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Step 7: Create view for monitoring encryption status
CREATE OR REPLACE VIEW message_encryption_status AS
SELECT
    ek.version_name,
    ek.algorithm,
    COUNT(m.id) as message_count,
    MIN(m.created_at) as oldest_message,
    MAX(m.created_at) as newest_message,
    ek.deprecated_at,
    ek.active
FROM messages m
RIGHT JOIN encryption_keys ek ON m.encryption_version = ek.version_name
WHERE m.deleted_at IS NULL
    OR m.deleted_at IS NULL  -- Include all keys even if no messages yet
GROUP BY ek.version_name, ek.algorithm, ek.deprecated_at, ek.active;

COMMENT ON VIEW message_encryption_status IS
    'Monitor which encryption versions are in use and how many messages each version has. Used to track key rotation progress.';

-- Step 8: Create function to report key rotation status
CREATE OR REPLACE FUNCTION get_key_rotation_status()
RETURNS TABLE (
    current_version encryption_version_type,
    current_algorithm VARCHAR(50),
    messages_in_current BIGINT,
    messages_needing_rotation BIGINT,
    rotation_progress_percent NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ek.version_name,
        ek.algorithm,
        COUNT(CASE WHEN m.encryption_version = ek.version_name THEN 1 END)::BIGINT as messages_in_current,
        COUNT(CASE WHEN m.encryption_version != ek.version_name AND m.deleted_at IS NULL THEN 1 END)::BIGINT as messages_needing_rotation,
        ROUND(
            100.0 * COUNT(CASE WHEN m.encryption_version = ek.version_name THEN 1 END)::NUMERIC
            / NULLIF(COUNT(m.id)::NUMERIC, 0)
        )::NUMERIC as rotation_progress_percent
    FROM messages m
    RIGHT JOIN encryption_keys ek ON ek.active = TRUE
    GROUP BY ek.version_name, ek.algorithm;
END;
$$ LANGUAGE plpgsql;

-- Step 9: Create audit log table for encryption operations
CREATE TABLE IF NOT EXISTS encryption_audit_log (
    id BIGSERIAL PRIMARY KEY,
    operation VARCHAR(50) NOT NULL,         -- 'key_rotation_start', 'key_rotation_complete'
    message_id UUID,
    old_version encryption_version_type,
    new_version encryption_version_type,
    executed_at TIMESTAMP DEFAULT NOW(),
    executed_by VARCHAR(255),               -- Service name (e.g., 'messaging-service')
    details JSONB                           -- Extra info (error messages, retry count, etc.)
);

-- Step 10: Index audit log for queries
CREATE INDEX IF NOT EXISTS idx_encryption_audit_by_message
    ON encryption_audit_log(message_id);

CREATE INDEX IF NOT EXISTS idx_encryption_audit_by_time
    ON encryption_audit_log(executed_at DESC);

CREATE INDEX IF NOT EXISTS idx_encryption_audit_by_version
    ON encryption_audit_log(old_version, new_version);

-- Step 11: Add constraints to ensure valid transitions
ALTER TABLE encryption_keys
    ADD CONSTRAINT valid_algorithm CHECK (
        algorithm IN (
            'AES-GCM-256',
            'AES-GCM-128',
            'CHACHA20-POLY1305'
        )
    );

ALTER TABLE encryption_keys
    ADD CONSTRAINT valid_key_bits CHECK (
        key_bits IN (128, 192, 256)
    );

-- Step 12: Add column comments for documentation
COMMENT ON COLUMN messages.encryption_version IS
    'Encryption version as ENUM. References encryption_keys(version_name). Determines which decryption key to use. Stored as 1-byte ENUM instead of 32-byte VARCHAR for space efficiency (96% savings).';

COMMENT ON COLUMN messages.encryption_key_generation IS
    'Key generation number within this version. Used to support multiple keys per version if needed. Default 1.';

COMMENT ON TABLE encryption_keys IS
    'Single source of truth for encryption algorithm details. Application queries this table, not individual messages. Supports key rotation and algorithm migration.';

COMMENT ON COLUMN encryption_keys.active IS
    'Is this version used for NEW encryptions? Only one version should have active=TRUE at a time.';

COMMENT ON COLUMN encryption_keys.rotated_to_version IS
    'Points to the next version in the rotation chain. Used to coordinate key rotation progress.';

COMMENT ON TABLE encryption_audit_log IS
    'Audit trail for all encryption operations. Required for compliance (SOC2, HIPAA, PCI-DSS). Tracks who rotated keys and when.';

-- Step 13: Helper function for starting key rotation
CREATE OR REPLACE FUNCTION start_key_rotation(
    p_from_version encryption_version_type,
    p_to_version encryption_version_type,
    p_executed_by VARCHAR(255) DEFAULT 'system'
)
RETURNS TABLE (
    message_count BIGINT,
    estimated_duration_minutes INT
) AS $$
DECLARE
    v_message_count BIGINT;
BEGIN
    -- Mark current version as deprecated
    UPDATE encryption_keys
    SET deprecated_at = NOW()
    WHERE version_name = p_from_version;

    -- Mark new version as active
    UPDATE encryption_keys
    SET active = TRUE
    WHERE version_name = p_to_version;

    -- Log the operation
    INSERT INTO encryption_audit_log (
        operation, old_version, new_version, executed_by, details
    ) VALUES (
        'rotation_started',
        p_from_version,
        p_to_version,
        p_executed_by,
        jsonb_build_object(
            'status', 'started',
            'started_at', NOW()
        )
    );

    -- Return helpful metrics
    SELECT COUNT(*) INTO v_message_count
    FROM messages
    WHERE encryption_version = p_from_version AND deleted_at IS NULL;

    RETURN QUERY SELECT
        v_message_count,
        CASE
            WHEN v_message_count < 10000 THEN 5
            WHEN v_message_count < 100000 THEN 30
            WHEN v_message_count < 1000000 THEN 120
            ELSE 480
        END;
END;
$$ LANGUAGE plpgsql;

-- Step 14: Helper function for completing key rotation
CREATE OR REPLACE FUNCTION complete_key_rotation(
    p_from_version encryption_version_type,
    p_to_version encryption_version_type,
    p_executed_by VARCHAR(255) DEFAULT 'system'
)
RETURNS TABLE (
    rotated_count BIGINT,
    error_count BIGINT,
    completion_time VARCHAR(50)
) AS $$
DECLARE
    v_rotated BIGINT;
    v_errors BIGINT;
BEGIN
    -- Count rotated messages
    SELECT COUNT(*) INTO v_rotated
    FROM messages
    WHERE encryption_version = p_to_version AND deleted_at IS NULL;

    -- Count messages still in old version (should be 0)
    SELECT COUNT(*) INTO v_errors
    FROM messages
    WHERE encryption_version = p_from_version AND deleted_at IS NULL;

    -- Log completion
    INSERT INTO encryption_audit_log (
        operation, old_version, new_version, executed_by, details
    ) VALUES (
        'rotation_completed',
        p_from_version,
        p_to_version,
        p_executed_by,
        jsonb_build_object(
            'status', 'completed',
            'rotated_count', v_rotated,
            'remaining_count', v_errors,
            'completed_at', NOW()
        )
    );

    RETURN QUERY SELECT
        v_rotated,
        v_errors,
        CASE
            WHEN v_errors = 0 THEN 'Complete'
            ELSE format('%s messages still need rotation', v_errors)
        END;
END;
$$ LANGUAGE plpgsql;

-- Step 15: Log migration
INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
VALUES (
    '068',
    'messages,encryption_keys,encryption_audit_log',
    'Added encryption versioning with ENUM type (saves 96% space). Created encryption_keys config table. Added key rotation tracking and audit logging.'
)
ON CONFLICT DO NOTHING;

-- Step 16: Analyze tables
ANALYZE messages;
ANALYZE encryption_keys;
ANALYZE encryption_audit_log;
