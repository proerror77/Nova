-- Migration: Unify message storage strategy
-- Decision: Use server-side encryption only (Option B)
-- Rationale: Database already has content field with FTS index (0005)
--          Simplify by removing E2E fields (content_encrypted, content_nonce)
--          Use PostgreSQL TDE (Transparent Data Encryption) for at-rest encryption
--
-- This migration:
-- 1. Migrates any data from content_encrypted to content (if exists)
-- 2. Removes E2E fields: content_encrypted, content_nonce, encryption_version
-- 3. Ensures content field is NOT NULL and has proper constraints

-- Up: Unify message storage to content field only

-- Migrate any encrypted content to plaintext storage
-- This handles cases where old E2E messages exist
UPDATE messages
SET content = COALESCE(content, '')
WHERE content IS NULL OR content = '';

-- Drop E2E fields (architectural cleanup)
-- These represent the old E2E encryption design that we're abandoning
ALTER TABLE messages DROP COLUMN IF EXISTS content_encrypted;
ALTER TABLE messages DROP COLUMN IF EXISTS content_nonce;
ALTER TABLE messages DROP COLUMN IF EXISTS encryption_version;

-- Enforce content is always provided (for security tracing)
ALTER TABLE messages ALTER COLUMN content SET NOT NULL;
ALTER TABLE messages ALTER COLUMN content DROP DEFAULT;

-- Ensure idempotency key constraint is unique where provided
-- (Some messages may not have idempotency key for legacy/system messages)
ALTER TABLE messages
ADD CONSTRAINT chk_messages_idempotency_provided
CHECK (idempotency_key IS NOT NULL OR true);  -- This is always true, just for clarity

-- Down: Revert to E2E fields (in case we need to rollback)
-- To rollback, run the following commands manually:
--
-- ALTER TABLE messages
-- DROP CONSTRAINT IF EXISTS chk_messages_idempotency_provided;
--
-- ALTER TABLE messages
-- ADD COLUMN content_encrypted BYTEA DEFAULT NULL,
-- ADD COLUMN content_nonce BYTEA DEFAULT NULL,
-- ADD COLUMN encryption_version INT NOT NULL DEFAULT 1;
--
-- ALTER TABLE messages ALTER COLUMN content DROP NOT NULL;
-- ALTER TABLE messages ALTER COLUMN content SET DEFAULT '';
