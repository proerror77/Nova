-- ============================================
-- Migration: 010_jwt_key_rotation
-- Description: JWT signing key rotation support
-- Author: Nova Team
-- Date: 2025-10-18
-- ============================================

-- ============================================
-- Table: jwt_signing_keys
-- Description: Store RSA key pairs for JWT signing with rotation support
-- ============================================
CREATE TABLE IF NOT EXISTS jwt_signing_keys (
    id BIGSERIAL PRIMARY KEY,
    key_id VARCHAR(36) UNIQUE NOT NULL,  -- UUID format (e.g., "key-2025-10-18-v1")
    version INT NOT NULL,
    private_key_encrypted BYTEA NOT NULL,  -- AES-256-GCM encrypted private key
    public_key_pem TEXT NOT NULL,          -- PEM format public key
    algorithm VARCHAR(20) NOT NULL DEFAULT 'RS256',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    activated_at TIMESTAMP WITH TIME ZONE,  -- When this key became active
    rotated_at TIMESTAMP WITH TIME ZONE,    -- When this key was rotated out
    expires_at TIMESTAMP WITH TIME ZONE,    -- When to delete this key
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    created_by VARCHAR(50) NOT NULL DEFAULT 'system',  -- "system" or admin user ID

    -- Constraints
    CONSTRAINT version_positive CHECK (version > 0),
    CONSTRAINT only_one_active CHECK (
        is_active = FALSE OR
        (SELECT COUNT(*) FROM jwt_signing_keys WHERE is_active = TRUE) <= 1
    )
);

-- Indexes for jwt_signing_keys table
CREATE INDEX IF NOT EXISTS idx_jwt_keys_active ON jwt_signing_keys(is_active, activated_at DESC) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_jwt_keys_expires ON jwt_signing_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_jwt_keys_key_id ON jwt_signing_keys(key_id);
CREATE INDEX IF NOT EXISTS idx_jwt_keys_version ON jwt_signing_keys(version DESC);

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE jwt_signing_keys IS 'RSA key pairs for JWT token signing with automatic rotation';
COMMENT ON COLUMN jwt_signing_keys.key_id IS 'Unique key identifier (UUID format)';
COMMENT ON COLUMN jwt_signing_keys.version IS 'Key version number (incremental)';
COMMENT ON COLUMN jwt_signing_keys.private_key_encrypted IS 'AES-256-GCM encrypted RSA private key';
COMMENT ON COLUMN jwt_signing_keys.public_key_pem IS 'PEM-formatted RSA public key for JWKS endpoint';
COMMENT ON COLUMN jwt_signing_keys.activated_at IS 'Timestamp when this key became the active signing key';
COMMENT ON COLUMN jwt_signing_keys.rotated_at IS 'Timestamp when this key was replaced by a newer key';
COMMENT ON COLUMN jwt_signing_keys.expires_at IS 'Timestamp after which this key can be deleted (grace period end)';
COMMENT ON COLUMN jwt_signing_keys.is_active IS 'Whether this is the current active key for signing new tokens';
