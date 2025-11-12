-- Migration 118: OAuth Token Encryption Enhancement
--
-- CRITICAL FIX for OAuth token refresh functionality
--
-- Current Problem:
-- - oauth_connections table does not exist in main migrations (only in archived auth-service)
-- - Need to create the table first, then add encryption columns
--
-- Solution:
-- 1. Create oauth_connections table if not exists
-- 2. Add encrypted token columns for proper token refresh
-- 3. Add monitoring columns for tracking refresh attempts
--
-- Security Notes:
-- - Encryption key should be stored in secure location (e.g., AWS KMS)
-- - Tokens must be encrypted with AES-256-GCM
-- - Old hashed tokens (if any) will be marked as unusable

-- Step 1: Create oauth_connections table if not exists
CREATE TABLE IF NOT EXISTS oauth_connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL, -- 'google', 'apple', 'facebook', 'wechat'
    provider_user_id VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    name VARCHAR(255),
    picture_url VARCHAR(1024),

    -- Legacy hash columns (deprecated, kept for backward compatibility)
    access_token_hash VARCHAR(512),
    refresh_token_hash VARCHAR(512),

    -- Token metadata
    token_type VARCHAR(50),
    token_expires_at TIMESTAMP WITH TIME ZONE,
    scopes TEXT,
    raw_data JSONB,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT oauth_connections_unique_provider UNIQUE(provider, provider_user_id)
);

-- Create indices for oauth_connections
CREATE INDEX IF NOT EXISTS idx_oauth_connections_user_id ON oauth_connections(user_id);
CREATE INDEX IF NOT EXISTS idx_oauth_connections_provider ON oauth_connections(provider);
CREATE INDEX IF NOT EXISTS idx_oauth_connections_provider_user_id ON oauth_connections(provider_user_id);

-- Step 2: Add columns for encrypted tokens
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS access_token_encrypted BYTEA;
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS refresh_token_encrypted BYTEA;
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS token_encryption_method VARCHAR(50) DEFAULT 'aes-256-gcm';
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS tokens_encrypted BOOLEAN DEFAULT FALSE;

-- Step 3: Add index for finding tokens that need refresh
CREATE INDEX IF NOT EXISTS idx_oauth_expiring_tokens
ON oauth_connections(token_expires_at, provider)
WHERE refresh_token_encrypted IS NOT NULL AND token_expires_at IS NOT NULL;

-- Step 4: Add columns to track last refresh attempt (for monitoring)
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS last_token_refresh_attempt TIMESTAMP WITH TIME ZONE;
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS last_token_refresh_status VARCHAR(50); -- 'success', 'failed', 'skipped'
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS token_refresh_error_message TEXT;

-- Step 5: Add index for tracking refresh attempts
CREATE INDEX IF NOT EXISTS idx_oauth_last_refresh
ON oauth_connections(user_id, last_token_refresh_attempt DESC);

-- Step 6: Create updated_at trigger
CREATE OR REPLACE FUNCTION update_oauth_connections_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_oauth_connections_updated_at ON oauth_connections;
CREATE TRIGGER trigger_oauth_connections_updated_at
BEFORE UPDATE ON oauth_connections
FOR EACH ROW
EXECUTE FUNCTION update_oauth_connections_updated_at();

-- Step 7: Migration helper function to count old tokens
CREATE OR REPLACE FUNCTION count_old_oauth_tokens()
RETURNS TABLE(total_connections INT, using_hash INT, using_encrypted INT) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::INT as total_connections,
        COUNT(*) FILTER (WHERE tokens_encrypted = FALSE AND (access_token_hash IS NOT NULL OR refresh_token_hash IS NOT NULL))::INT as using_hash,
        COUNT(*) FILTER (WHERE tokens_encrypted = TRUE)::INT as using_encrypted
    FROM oauth_connections;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments documenting the migration
COMMENT ON TABLE oauth_connections IS 'OAuth provider connections with encrypted token storage for automatic refresh';
COMMENT ON COLUMN oauth_connections.access_token_encrypted IS 'Encrypted access token using AES-256-GCM. Set when new token is issued or refreshed.';
COMMENT ON COLUMN oauth_connections.refresh_token_encrypted IS 'Encrypted refresh token using AES-256-GCM. Set when new token is issued or refreshed.';
COMMENT ON COLUMN oauth_connections.tokens_encrypted IS 'TRUE if tokens are encrypted and ready for refresh. FALSE if still using old hashed tokens.';
COMMENT ON COLUMN oauth_connections.last_token_refresh_attempt IS 'Timestamp of last token refresh attempt (successful or failed).';
COMMENT ON COLUMN oauth_connections.last_token_refresh_status IS 'Status of last refresh: success, failed, or skipped.';
COMMENT ON COLUMN oauth_connections.token_refresh_error_message IS 'Error message from last failed refresh attempt (for debugging).';

-- Note for implementation:
-- 1. When OAuth login issues new tokens, encrypt them and store in encrypted columns, set tokens_encrypted = TRUE
-- 2. OAuth token refresh job will use encrypted tokens from encrypted columns
-- 3. Old hashed tokens (if any) will be marked as unusable (tokens_encrypted = FALSE)
-- 4. Keep hashed columns for backward compatibility during transition period
