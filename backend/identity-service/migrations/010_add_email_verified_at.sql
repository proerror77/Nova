-- Migration 010: Add email_verified_at column to users table
--
-- This column tracks when email verification was completed.
-- Required by: db/users.rs:310 - mark_email_verified function
-- Required by: models/user.rs:15 - User struct
--
-- Pattern: Expand-Contract migration (add column with default, no breaking change)

-- Add email_verified_at column with NULL default (backwards compatible)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;

-- Backfill existing verified users with current timestamp
UPDATE users
SET email_verified_at = COALESCE(updated_at, created_at)
WHERE email_verified = TRUE AND email_verified_at IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN users.email_verified_at IS 'Timestamp when email was verified, NULL if not verified';
