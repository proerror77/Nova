-- Migration: Add deleted_at column for soft delete functionality
-- This column was expected by the code but never created in the initial migration

-- Add deleted_at column (nullable timestamp, NULL = not deleted)
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Create index for efficient filtering of non-deleted users
-- Most queries filter WHERE deleted_at IS NULL
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users (deleted_at) WHERE deleted_at IS NULL;

-- Comment explaining the soft delete pattern
COMMENT ON COLUMN users.deleted_at IS 'Timestamp when user was soft-deleted. NULL means user is active.';
