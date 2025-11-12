-- Migration 119: Message Encryption Version Support
--
-- Background:
-- - Migration 104 created messages table with encryption_version INT DEFAULT 1
-- - Migration 105 added content, version_number, recalled_at columns
-- - Migration 113 added content_encrypted BYTEA, content_nonce BYTEA (already has encryption_version)
--
-- Current State Check:
-- messages table already has:
-- - encryption_version INT (from 104)
-- - content_encrypted BYTEA (from 113)
-- - content_nonce BYTEA (from 113)
--
-- This Migration:
-- - NO-OP for columns (already exist)
-- - Add validation and documentation
-- - Ensure proper constraints for encryption versioning
--
-- Note: This migration is intentionally minimal to avoid conflicts with existing schema

-- Step 1: Verify encryption columns exist (no-op if already present)
-- These were already added in migration 113, but we ensure idempotency
DO $$
BEGIN
    -- Verify content_encrypted exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'messages' AND column_name = 'content_encrypted'
    ) THEN
        RAISE EXCEPTION 'content_encrypted column missing - migration 113 should have created it';
    END IF;

    -- Verify content_nonce exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'messages' AND column_name = 'content_nonce'
    ) THEN
        RAISE EXCEPTION 'content_nonce column missing - migration 113 should have created it';
    END IF;

    -- Verify encryption_version exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'messages' AND column_name = 'encryption_version'
    ) THEN
        RAISE EXCEPTION 'encryption_version column missing - migration 104 should have created it';
    END IF;
END $$;

-- Step 2: Add check constraint for encryption version (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_messages_encryption_version_valid'
    ) THEN
        ALTER TABLE messages
        ADD CONSTRAINT chk_messages_encryption_version_valid
        CHECK (encryption_version IN (1, 2));
    END IF;
END $$;

-- Step 3: Add index for querying by encryption version (if not exists)
CREATE INDEX IF NOT EXISTS idx_messages_encryption_version
ON messages(encryption_version)
WHERE encryption_version IS NOT NULL;

-- Step 4: Add helpful comments
COMMENT ON COLUMN messages.content_encrypted IS 'Encrypted message content (BYTEA). NULL for plaintext messages (version 1).';
COMMENT ON COLUMN messages.content_nonce IS 'Nonce for encrypted content (BYTEA). NULL for plaintext messages (version 1).';
COMMENT ON COLUMN messages.encryption_version IS 'Encryption version: 1=plaintext (legacy), 2=E2EE with X25519+ChaCha20-Poly1305';

-- Step 5: Create helper function to check encryption status
CREATE OR REPLACE FUNCTION get_message_encryption_stats()
RETURNS TABLE(
    total_messages BIGINT,
    plaintext_v1 BIGINT,
    encrypted_v2 BIGINT,
    invalid_state BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) as total_messages,
        COUNT(*) FILTER (WHERE encryption_version = 1) as plaintext_v1,
        COUNT(*) FILTER (WHERE encryption_version = 2) as encrypted_v2,
        COUNT(*) FILTER (WHERE encryption_version NOT IN (1, 2)) as invalid_state
    FROM messages;
END;
$$ LANGUAGE plpgsql;

-- Note for implementation:
-- - encryption_version = 1: Legacy plaintext or simple encryption (content stored in 'content' column)
-- - encryption_version = 2: E2EE with X25519 key exchange + ChaCha20-Poly1305 (content_encrypted + content_nonce)
-- - When upgrading encryption, set encryption_version = 2 and populate content_encrypted/content_nonce
