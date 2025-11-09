-- ============================================
-- Migration: 005_add_deleted_at_to_users
-- Description: Align users table with soft-delete logic
-- Author: Nova Team
-- Date: 2025-03-15
-- ============================================

-- Add deleted_at column used by repository filters
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

-- Allow nullable email/username so we can scrub PII on soft delete
ALTER TABLE users
    ALTER COLUMN email DROP NOT NULL;

ALTER TABLE users
    ALTER COLUMN username DROP NOT NULL;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_email_key;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_username_key;

-- Ensure deleted records do not appear in existing unique indexes by expanding partial index
DROP INDEX IF EXISTS idx_users_email;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_active
    ON users(email)
    WHERE deleted_at IS NULL;

DROP INDEX IF EXISTS idx_users_username;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active
    ON users(username)
    WHERE deleted_at IS NULL;

-- Preserve fast lookup for active users
DROP INDEX IF EXISTS idx_users_is_active;
CREATE INDEX IF NOT EXISTS idx_users_is_active_active
    ON users(is_active)
    WHERE is_active = TRUE AND deleted_at IS NULL;

-- Store file sizes for completed upload sessions
ALTER TABLE upload_sessions
    ADD COLUMN IF NOT EXISTS file_size BIGINT;
