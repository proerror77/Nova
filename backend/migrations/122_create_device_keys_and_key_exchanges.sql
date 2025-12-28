-- Migration 120: Device Key Management and ECDH Key Exchange
--
-- ⚠️  DEPRECATED: This migration is part of the old monolith architecture.
-- E2EE is now handled by realtime-chat-service using vodozemac (Olm/Megolm).
-- See: realtime-chat-service/migrations/0010_e2ee_vodozemac_tables.sql
--
-- This migration assumes users and conversations in the same database,
-- which conflicts with the microservices architecture where:
-- - users → identity-service database
-- - conversations → realtime-chat-service database
--
-- DO NOT RUN this migration in the microservices deployment.
--
-- Dependencies:
-- - users table (exists from migration 001)
-- - conversations table (exists from migration 018)
--
-- Purpose:
-- - Create device_keys table for storing X25519 public/private key pairs
-- - Create key_exchanges table for audit trail of ECDH key exchanges
-- - Support E2EE (encryption_version=2) in messages table
--
-- Security Notes:
-- - Private keys stored encrypted at rest using master key
-- - Public keys stored as Base64-encoded X25519 keys (32 bytes)
-- - Shared secrets hashed with HMAC-SHA256 for audit trail only

-- Step 1: Verify dependencies exist
DO $$
BEGIN
    -- Verify users table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        RAISE EXCEPTION 'users table does not exist - migration 001 required';
    END IF;

    -- Verify conversations table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'conversations') THEN
        RAISE EXCEPTION 'conversations table does not exist - migration 018 required';
    END IF;
END $$;

-- Step 2: Create device_keys table for ECDH key management
CREATE TABLE IF NOT EXISTS device_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    device_id TEXT NOT NULL,

    -- Base64 encoded X25519 public key (32 bytes)
    public_key TEXT NOT NULL,

    -- Base64 encoded private key (encrypted with master key at rest)
    private_key_encrypted TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ensure one active key per device per user
    CONSTRAINT device_keys_unique_device UNIQUE (user_id, device_id),

    -- Foreign key constraint
    CONSTRAINT device_keys_user_fk FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- Create index for efficient device key lookup
CREATE INDEX IF NOT EXISTS idx_device_keys_user_id ON device_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_device_keys_user_device ON device_keys(user_id, device_id);

-- Step 3: Create key_exchanges audit trail table
CREATE TABLE IF NOT EXISTS key_exchanges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL,
    initiator_id UUID NOT NULL,
    peer_id UUID NOT NULL,

    -- Hash of shared secret for audit trail (HMAC-SHA256)
    -- Note: This is NOT the shared secret itself, only a verification hash
    shared_secret_hash BYTEA NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Foreign key constraints
    CONSTRAINT key_exchanges_conv_fk FOREIGN KEY (conversation_id)
        REFERENCES conversations(id) ON DELETE CASCADE,
    CONSTRAINT key_exchanges_initiator_fk FOREIGN KEY (initiator_id)
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT key_exchanges_peer_fk FOREIGN KEY (peer_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- Create indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_key_exchanges_conversation ON key_exchanges(conversation_id);
CREATE INDEX IF NOT EXISTS idx_key_exchanges_initiator ON key_exchanges(initiator_id);
CREATE INDEX IF NOT EXISTS idx_key_exchanges_created_at ON key_exchanges(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_key_exchanges_conv_created ON key_exchanges(conversation_id, created_at DESC);

-- Step 4: Create updated_at trigger for device_keys
CREATE OR REPLACE FUNCTION update_device_keys_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_device_keys_updated_at ON device_keys;
CREATE TRIGGER trigger_device_keys_updated_at
BEFORE UPDATE ON device_keys
FOR EACH ROW
EXECUTE FUNCTION update_device_keys_updated_at();

-- Step 5: Add helpful comments documenting the encryption scheme
COMMENT ON TABLE device_keys IS 'Stores X25519 public keys for ECDH key exchange. Used for E2EE (encryption_version=2 in messages).';
COMMENT ON TABLE key_exchanges IS 'Audit trail for ECDH key exchanges. Enables tracking and verification of encryption setup.';
COMMENT ON COLUMN device_keys.public_key IS 'Base64-encoded X25519 public key (32 bytes). Shared with peers for key exchange.';
COMMENT ON COLUMN device_keys.private_key_encrypted IS 'Base64-encoded X25519 private key encrypted with master key. Never shared.';
COMMENT ON COLUMN key_exchanges.shared_secret_hash IS 'HMAC-SHA256 hash of shared secret for audit trail. NOT the secret itself.';

-- Step 6: Create helper function for device key management
CREATE OR REPLACE FUNCTION get_device_key_stats()
RETURNS TABLE(
    total_devices BIGINT,
    total_users BIGINT,
    total_key_exchanges BIGINT,
    avg_devices_per_user NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT as total_devices,
        COUNT(DISTINCT user_id)::BIGINT as total_users,
        (SELECT COUNT(*)::BIGINT FROM key_exchanges) as total_key_exchanges,
        ROUND(COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT user_id), 0), 2) as avg_devices_per_user
    FROM device_keys;
END;
$$ LANGUAGE plpgsql;

-- Note for implementation:
-- 1. Generate X25519 key pair on client device
-- 2. Encrypt private key with master key before storing
-- 3. Store public key in device_keys table
-- 4. On key exchange, compute shared secret using X25519(my_private, peer_public)
-- 5. Store HMAC-SHA256(shared_secret) in key_exchanges for audit trail
-- 6. Use shared secret to derive encryption key for messages (encryption_version=2)
-- 7. Messages encrypted with ChaCha20-Poly1305 using derived key
