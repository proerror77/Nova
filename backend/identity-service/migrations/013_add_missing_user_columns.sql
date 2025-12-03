-- Migration 013: Add missing columns to users table
--
-- This migration adds columns that exist in the User struct (models/user.rs)
-- but were never created in the database schema.
--
-- Required by: models/user.rs - User struct fields
-- Required by: db/users.rs - RETURNING * queries that map to User struct
--
-- Pattern: Expand-Contract migration (add columns with defaults, no breaking change)

-- Add phone authentication columns
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS phone_number VARCHAR(20),
    ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- Add profile display columns
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS bio TEXT,
    ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500),
    ADD COLUMN IF NOT EXISTS cover_photo_url VARCHAR(500),
    ADD COLUMN IF NOT EXISTS location VARCHAR(255),
    ADD COLUMN IF NOT EXISTS private_account BOOLEAN NOT NULL DEFAULT FALSE;

-- Rename password_changed_at to last_password_change_at if it exists
-- (matches User struct field name)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'password_changed_at'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'last_password_change_at'
    ) THEN
        ALTER TABLE users RENAME COLUMN password_changed_at TO last_password_change_at;
    ELSIF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'last_password_change_at'
    ) THEN
        ALTER TABLE users ADD COLUMN last_password_change_at TIMESTAMPTZ;
    END IF;
END$$;

-- Create indexes for new columns
CREATE INDEX IF NOT EXISTS idx_users_phone_number ON users(phone_number) WHERE phone_number IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN users.phone_number IS 'User phone number for SMS verification';
COMMENT ON COLUMN users.phone_verified IS 'Whether phone number has been verified via SMS';
COMMENT ON COLUMN users.bio IS 'User biography/about text';
COMMENT ON COLUMN users.avatar_url IS 'URL to user profile avatar image';
COMMENT ON COLUMN users.cover_photo_url IS 'URL to user profile cover/banner image';
COMMENT ON COLUMN users.location IS 'User location display string';
COMMENT ON COLUMN users.private_account IS 'Whether account is private (requires follow approval)';
