-- Migration: Add encrypted payload columns for messages

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS content_encrypted BYTEA,
    ADD COLUMN IF NOT EXISTS content_nonce BYTEA,
    ADD COLUMN IF NOT EXISTS encryption_version INT NOT NULL DEFAULT 1;

UPDATE messages
SET encryption_version = 1
WHERE encryption_version IS NULL;

ALTER TABLE messages
    ALTER COLUMN encryption_version DROP DEFAULT;

-- Down migration

ALTER TABLE messages
    DROP COLUMN IF EXISTS content_encrypted,
    DROP COLUMN IF EXISTS content_nonce,
    DROP COLUMN IF EXISTS encryption_version;
