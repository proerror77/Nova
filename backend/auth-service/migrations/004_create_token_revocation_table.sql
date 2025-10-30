-- Create token_revocation table for blacklisting tokens
CREATE TABLE IF NOT EXISTS token_revocation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE, -- SHA256 hash of the token
    token_type VARCHAR(20) NOT NULL, -- 'access' or 'refresh'
    jti VARCHAR(255), -- JWT ID for correlation
    reason VARCHAR(255), -- 'logout', 'password_change', 'manual', '2fa_enabled'
    revoked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL, -- When token would naturally expire
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indices
CREATE INDEX IF NOT EXISTS idx_token_revocation_user_id ON token_revocation(user_id);
CREATE INDEX IF NOT EXISTS idx_token_revocation_token_hash ON token_revocation(token_hash);
CREATE INDEX IF NOT EXISTS idx_token_revocation_expires_at ON token_revocation(expires_at);
CREATE INDEX IF NOT EXISTS idx_token_revocation_jti ON token_revocation(jti);

-- Create partition for efficient data cleanup (optional, can be added later)
-- This allows PostgreSQL to automatically clean up expired token revocations
CREATE OR REPLACE FUNCTION cleanup_expired_token_revocations()
RETURNS void AS $$
BEGIN
    DELETE FROM token_revocation WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Note: You can run this cleanup job periodically via a background job scheduler
