-- Migration: 0011_add_megolm_message_columns
-- Description: Add columns for Megolm E2EE message storage
-- Note: Must re-add encryption_version since 0009 may have dropped it

-- Re-add encryption_version if it was dropped by 0009
-- This makes migration order-independent and idempotent
ALTER TABLE messages ADD COLUMN IF NOT EXISTS encryption_version INT DEFAULT 0;

-- Add E2EE-specific columns to messages table
ALTER TABLE messages ADD COLUMN IF NOT EXISTS sender_device_id TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS megolm_session_id TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS megolm_ciphertext TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS megolm_message_index INTEGER;

-- Index for efficient session-based queries
CREATE INDEX IF NOT EXISTS idx_messages_megolm_session
ON messages(conversation_id, megolm_session_id)
WHERE megolm_session_id IS NOT NULL;

-- Index for finding messages by encryption version
CREATE INDEX IF NOT EXISTS idx_messages_encryption_version
ON messages(conversation_id, encryption_version)
WHERE encryption_version = 2;

-- Comment explaining encryption_version values:
-- 0 = plaintext (no encryption)
-- 1 = server-side encryption (legacy EncryptionService)
-- 2 = Megolm E2EE (client-side encryption with vodozemac)
COMMENT ON COLUMN messages.encryption_version IS '0=plaintext, 1=server-side, 2=Megolm E2EE';
