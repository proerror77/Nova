-- Passkey (WebAuthn/FIDO2) Credentials Migration
-- This table stores WebAuthn credentials for passwordless authentication
-- Follows the oauth_connections pattern for consistency

-- Create passkey_credentials table
CREATE TABLE IF NOT EXISTS passkey_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- WebAuthn Credential Data
    credential_id BYTEA NOT NULL UNIQUE,                -- Raw credential ID from authenticator
    credential_id_base64 VARCHAR(512) NOT NULL UNIQUE,  -- Base64URL encoded for indexing
    public_key BYTEA NOT NULL,                          -- COSE encoded public key

    -- Credential Metadata
    credential_name VARCHAR(255),                       -- User-friendly name (e.g., "iPhone 15 Pro")
    aaguid BYTEA,                                       -- Authenticator Attestation GUID (16 bytes)

    -- Counter and Backup State (WebAuthn spec)
    sign_count BIGINT NOT NULL DEFAULT 0,               -- Signature counter for clone detection
    backup_eligible BOOLEAN NOT NULL DEFAULT FALSE,     -- BE flag: can be backed up
    backup_state BOOLEAN NOT NULL DEFAULT FALSE,        -- BS flag: is backed up

    -- Transports (JSON array for flexibility)
    transports JSONB DEFAULT '[]'::JSONB,               -- ['internal', 'hybrid', 'usb', etc.]

    -- Device info (for display in settings)
    device_type VARCHAR(100),                           -- 'iPhone', 'iPad', 'Mac', etc.
    os_version VARCHAR(50),                             -- e.g., '18.0'

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    revoked_at TIMESTAMPTZ,
    revoke_reason VARCHAR(255),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

-- Create indexes for performance
CREATE INDEX idx_passkey_user_id ON passkey_credentials(user_id);
CREATE INDEX idx_passkey_credential_id_base64 ON passkey_credentials(credential_id_base64);
CREATE INDEX idx_passkey_active ON passkey_credentials(user_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_passkey_aaguid ON passkey_credentials(aaguid) WHERE aaguid IS NOT NULL;
CREATE INDEX idx_passkey_last_used ON passkey_credentials(last_used_at DESC NULLS LAST);

-- Add trigger for updated_at
CREATE TRIGGER update_passkey_credentials_updated_at
    BEFORE UPDATE ON passkey_credentials
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Add comments
COMMENT ON TABLE passkey_credentials IS 'WebAuthn/FIDO2 credentials for passwordless authentication';
COMMENT ON COLUMN passkey_credentials.credential_id IS 'Raw credential ID bytes from authenticator';
COMMENT ON COLUMN passkey_credentials.credential_id_base64 IS 'Base64URL encoded credential ID for efficient lookups';
COMMENT ON COLUMN passkey_credentials.public_key IS 'COSE encoded public key for signature verification';
COMMENT ON COLUMN passkey_credentials.sign_count IS 'Monotonic counter to detect cloned authenticators';
COMMENT ON COLUMN passkey_credentials.backup_eligible IS 'Whether credential can be backed up (iCloud Keychain)';
COMMENT ON COLUMN passkey_credentials.backup_state IS 'Whether credential is currently backed up';
COMMENT ON COLUMN passkey_credentials.transports IS 'Supported transports: internal, hybrid, usb, ble, nfc';
