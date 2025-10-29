-- Device key management table for ECDH key exchange
CREATE TABLE device_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
CREATE INDEX idx_device_keys_user_id ON device_keys(user_id);
CREATE INDEX idx_device_keys_user_device ON device_keys(user_id, device_id);

-- Key exchange audit trail table
CREATE TABLE key_exchanges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL,
    initiator_id UUID NOT NULL,
    peer_id UUID NOT NULL,
    -- Hash of shared secret for audit trail (HMAC-SHA256)
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
CREATE INDEX idx_key_exchanges_conversation ON key_exchanges(conversation_id);
CREATE INDEX idx_key_exchanges_initiator ON key_exchanges(initiator_id);
CREATE INDEX idx_key_exchanges_created_at ON key_exchanges(created_at DESC);
CREATE INDEX idx_key_exchanges_conv_created ON key_exchanges(conversation_id, created_at DESC);

-- Add comment documenting the encryption versioning scheme
COMMENT ON TABLE device_keys IS 'Stores X25519 public keys for ECDH key exchange. encryption_version=2 in messages indicates E2EE.';
COMMENT ON TABLE key_exchanges IS 'Audit trail for ECDH key exchanges. Enables tracking and verification of encryption setup.';
