-- Add missing JTI (JWT ID) columns to sessions table for token tracking
-- These columns are required by the Session model for device management

ALTER TABLE IF EXISTS sessions
    ADD COLUMN IF NOT EXISTS access_token_jti VARCHAR(255),
    ADD COLUMN IF NOT EXISTS refresh_token_jti VARCHAR(255),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Create index for JTI lookups (useful for token revocation)
CREATE INDEX IF NOT EXISTS idx_sessions_access_jti ON sessions(access_token_jti) WHERE access_token_jti IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_refresh_jti ON sessions(refresh_token_jti) WHERE refresh_token_jti IS NOT NULL;

-- Add trigger to update updated_at on session changes
DROP TRIGGER IF EXISTS update_sessions_updated_at ON sessions;
CREATE TRIGGER update_sessions_updated_at BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMENT ON COLUMN sessions.access_token_jti IS 'JWT ID of the current access token';
COMMENT ON COLUMN sessions.refresh_token_jti IS 'JWT ID of the current refresh token';
