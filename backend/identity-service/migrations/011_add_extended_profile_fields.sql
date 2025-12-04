-- Migration: Add extended profile fields for user accounts
-- These fields support the iOS Account settings page

-- Create gender enum type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gender') THEN
        CREATE TYPE gender AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');
    END IF;
END$$;

-- Add extended profile fields to users table
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS first_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS last_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS date_of_birth DATE,
    ADD COLUMN IF NOT EXISTS gender gender,
    ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS public_key TEXT;

-- Add index for soft-delete queries (deleted_by lookup)
CREATE INDEX IF NOT EXISTS idx_users_deleted_by ON users(deleted_by) WHERE deleted_by IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN users.first_name IS 'User first name for profile display';
COMMENT ON COLUMN users.last_name IS 'User last name for profile display';
COMMENT ON COLUMN users.date_of_birth IS 'User date of birth for age verification';
COMMENT ON COLUMN users.gender IS 'User gender preference';
COMMENT ON COLUMN users.deleted_by IS 'UUID of admin/user who initiated soft delete';
COMMENT ON COLUMN users.public_key IS 'Base64-encoded public key for E2E encryption';
