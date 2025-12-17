-- Migration: Add alias_accounts table for multi-account support
-- This supports the iOS sub-account (alias) feature

-- Create alias_accounts table
CREATE TABLE IF NOT EXISTS alias_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    alias_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    date_of_birth DATE,
    gender gender,  -- Reuses existing gender enum from migration 011
    profession VARCHAR(100),
    location VARCHAR(200),
    is_active BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_alias_accounts_user_id ON alias_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_alias_accounts_user_active ON alias_accounts(user_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_alias_accounts_deleted ON alias_accounts(deleted_at) WHERE deleted_at IS NOT NULL;

-- Add constraint: user can have at most 5 alias accounts (reasonable limit)
-- This is enforced at application level, but we add a comment for documentation
COMMENT ON TABLE alias_accounts IS 'Alias (sub) accounts for users. Each user can have multiple alias identities. Limit: 5 aliases per user (enforced in application).';

-- Column comments
COMMENT ON COLUMN alias_accounts.id IS 'Unique alias account UUID';
COMMENT ON COLUMN alias_accounts.user_id IS 'Owner user UUID - foreign key to users table';
COMMENT ON COLUMN alias_accounts.alias_name IS 'Display name for this alias identity';
COMMENT ON COLUMN alias_accounts.avatar_url IS 'Avatar image URL for this alias';
COMMENT ON COLUMN alias_accounts.date_of_birth IS 'Optional date of birth for alias profile';
COMMENT ON COLUMN alias_accounts.gender IS 'Optional gender for alias profile';
COMMENT ON COLUMN alias_accounts.profession IS 'Optional profession/occupation for alias';
COMMENT ON COLUMN alias_accounts.location IS 'Optional location for alias';
COMMENT ON COLUMN alias_accounts.is_active IS 'Whether this alias is currently the active account';
COMMENT ON COLUMN alias_accounts.created_at IS 'Timestamp when alias was created';
COMMENT ON COLUMN alias_accounts.updated_at IS 'Timestamp when alias was last updated';
COMMENT ON COLUMN alias_accounts.deleted_at IS 'Soft delete timestamp (null = not deleted)';

-- Add current_account_id to users table to track which account (primary or alias) is active
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS current_account_id UUID,
    ADD COLUMN IF NOT EXISTS current_account_type VARCHAR(20) DEFAULT 'primary';

COMMENT ON COLUMN users.current_account_id IS 'Currently active account ID (null = primary account, UUID = alias account ID)';
COMMENT ON COLUMN users.current_account_type IS 'Type of current account: primary or alias';

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_alias_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_alias_accounts_updated_at ON alias_accounts;
CREATE TRIGGER trigger_alias_accounts_updated_at
    BEFORE UPDATE ON alias_accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_alias_accounts_updated_at();
