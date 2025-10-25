-- OAuth Token Encryption Migration
--
-- CRITICAL FIX for OAuth token refresh functionality
--
-- Current Problem:
-- - Refresh tokens are stored hashed in oauth_connections table
-- - Hashed values cannot be decrypted/used for refresh
-- - This blocks automatic token refresh implementation
--
-- Solution:
-- 1. Add new encrypted token columns to oauth_connections
-- 2. Migrate existing tokens (mark as "hashed" - cannot be used)
-- 3. Gradually move to encrypted storage as new tokens are issued
--
-- Security Notes:
-- - Encryption key should be stored in secure location (e.g., AWS KMS)
-- - Old hashed tokens will be marked as unusable
-- - New tokens must be encrypted with the master key

-- Add columns for encrypted tokens
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS access_token_encrypted BYTEA;
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS refresh_token_encrypted BYTEA;
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS token_encryption_method VARCHAR(50) DEFAULT 'aes-256-gcm';
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS tokens_encrypted BOOLEAN DEFAULT FALSE;

-- Add index for finding tokens that need refresh
CREATE INDEX IF NOT EXISTS idx_oauth_expiring_tokens
ON oauth_connections(token_expires_at, provider)
WHERE refresh_token_encrypted IS NOT NULL AND token_expires_at IS NOT NULL;

-- Add column to track last refresh attempt (for monitoring)
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS last_token_refresh_attempt TIMESTAMP WITH TIME ZONE;
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS last_token_refresh_status VARCHAR(50); -- 'success', 'failed', 'skipped'
ALTER TABLE oauth_connections ADD COLUMN IF NOT EXISTS token_refresh_error_message TEXT;

-- Add index for tracking refresh attempts
CREATE INDEX IF NOT EXISTS idx_oauth_last_refresh
ON oauth_connections(user_id, last_token_refresh_attempt DESC);

-- Migration helper function to mark old tokens
CREATE OR REPLACE FUNCTION mark_old_tokens_for_migration()
RETURNS TABLE(migrated_count INT) AS $$
DECLARE
    v_count INT;
BEGIN
    -- Count tokens that use old hashed method (for monitoring)
    SELECT COUNT(*) INTO v_count
    FROM oauth_connections
    WHERE tokens_encrypted = FALSE
      AND (access_token_hash IS NOT NULL OR refresh_token_hash IS NOT NULL);

    -- Return count of tokens that need to be re-encrypted
    RETURN QUERY SELECT v_count;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comment documenting the migration
COMMENT ON COLUMN oauth_connections.access_token_encrypted IS 'Encrypted access token using AES-256-GCM. Set when new token is issued or refreshed.';
COMMENT ON COLUMN oauth_connections.refresh_token_encrypted IS 'Encrypted refresh token using AES-256-GCM. Set when new token is issued or refreshed.';
COMMENT ON COLUMN oauth_connections.tokens_encrypted IS 'TRUE if tokens are encrypted and ready for refresh. FALSE if still using old hashed tokens.';
COMMENT ON COLUMN oauth_connections.last_token_refresh_attempt IS 'Timestamp of last token refresh attempt (successful or failed).';
COMMENT ON COLUMN oauth_connections.last_token_refresh_status IS 'Status of last refresh: success, failed, or skipped.';
COMMENT ON COLUMN oauth_connections.token_refresh_error_message IS 'Error message from last failed refresh attempt (for debugging).';

-- Grant permissions
ALTER TABLE oauth_connections OWNER TO postgres;

-- Note for implementation:
-- 1. When OAuth login issues new tokens, encrypt them and store in encrypted columns, set tokens_encrypted = TRUE
-- 2. OAuth token refresh job will use encrypted tokens from encrypted columns
-- 3. Old hashed tokens will eventually be deprecated as users refresh their credentials
-- 4. Keep hashed columns for backward compatibility during transition period
