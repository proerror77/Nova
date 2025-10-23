-- ============================================
-- Migration: 025_jwt_signing_keys_pg
-- Description: Postgres-compatible JWT signing keys schema
-- Notes: Legacy 010 migration used MySQL-style CHECK with subquery (unsupported)
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS jwt_signing_keys (
    id BIGSERIAL PRIMARY KEY,
    key_id VARCHAR(36) UNIQUE NOT NULL,
    version INT NOT NULL CHECK (version > 0),
    private_key_encrypted BYTEA NOT NULL,
    public_key_pem TEXT NOT NULL,
    algorithm VARCHAR(20) NOT NULL DEFAULT 'RS256',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at TIMESTAMPTZ,
    rotated_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    created_by VARCHAR(50) NOT NULL DEFAULT 'system'
);

-- Ensure only one active key at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_jwt_keys_single_active
    ON jwt_signing_keys (is_active)
    WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_jwt_keys_active
    ON jwt_signing_keys (is_active, activated_at DESC)
    WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_jwt_keys_expires
    ON jwt_signing_keys (expires_at);

CREATE INDEX IF NOT EXISTS idx_jwt_keys_key_id
    ON jwt_signing_keys (key_id);

CREATE INDEX IF NOT EXISTS idx_jwt_keys_version
    ON jwt_signing_keys (version DESC);

COMMENT ON TABLE jwt_signing_keys IS 'RSA key pairs for JWT token signing with automatic rotation';
COMMENT ON COLUMN jwt_signing_keys.key_id IS 'Unique key identifier (UUID format)';
COMMENT ON COLUMN jwt_signing_keys.version IS 'Key version number (incremental)';
COMMENT ON COLUMN jwt_signing_keys.private_key_encrypted IS 'AES-256-GCM encrypted RSA private key';
COMMENT ON COLUMN jwt_signing_keys.public_key_pem IS 'PEM-formatted RSA public key for JWKS endpoint';
COMMENT ON COLUMN jwt_signing_keys.activated_at IS 'Timestamp when this key became the active signing key';
COMMENT ON COLUMN jwt_signing_keys.rotated_at IS 'Timestamp when this key was replaced by a newer key';
COMMENT ON COLUMN jwt_signing_keys.expires_at IS 'Timestamp after which this key can be deleted';
COMMENT ON COLUMN jwt_signing_keys.is_active IS 'Whether this is the current active key for signing new tokens';
