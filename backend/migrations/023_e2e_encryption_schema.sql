-- ============================================
-- E2E Encryption Schema for Phase 5 Feature 2
-- ============================================
-- This migration adds tables for managing end-to-end encrypted messaging
-- with support for key exchange, storage, and rotation.

-- User public keys table
-- Stores the public keys for each user (32 bytes, base64-encoded)
CREATE TABLE IF NOT EXISTS user_public_keys (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Public key (32 bytes, base64-encoded)
    public_key TEXT NOT NULL,

    -- Key rotation metadata
    rotation_interval_days INT DEFAULT 30,
    next_rotation_at TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Usage tracking
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE,

    -- Only one active key per user at a time
    UNIQUE(user_id)
);

-- Key exchange requests
-- Tracks the state of key exchange between users
CREATE TABLE IF NOT EXISTS key_exchanges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Participants
    initiator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Initiator's public key
    initiator_public_key TEXT NOT NULL,

    -- Status: 'pending', 'completed', 'failed'
    status VARCHAR(50) DEFAULT 'pending',

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Ensure different users
    CONSTRAINT different_users CHECK (initiator_id != recipient_id),

    -- Only one active key exchange per pair at a time
    UNIQUE(initiator_id, recipient_id, status)
);

-- Encrypted messages table
-- Stores encrypted message content and metadata
CREATE TABLE IF NOT EXISTS encrypted_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Participants
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Encryption metadata
    encrypted_content TEXT NOT NULL, -- Base64-encoded ciphertext
    nonce TEXT NOT NULL, -- Base64-encoded 24-byte nonce
    sender_public_key TEXT NOT NULL, -- For verification

    -- Delivery status
    delivered BOOLEAN DEFAULT false,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read BOOLEAN DEFAULT false,
    read_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Nonce history table (for replay attack prevention)
-- Tracks used nonces to prevent replay attacks
CREATE TABLE IF NOT EXISTS used_nonces (
    id BIGSERIAL PRIMARY KEY,
    conversation_pair TEXT NOT NULL, -- "{user1_id}:{user2_id}" sorted
    nonce TEXT NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Ensure nonce uniqueness per conversation pair
    UNIQUE(conversation_pair, nonce)
);

-- Key rotation history
-- Tracks key rotation events for audit purposes
CREATE TABLE IF NOT EXISTS key_rotations (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Old and new keys
    old_public_key TEXT NOT NULL,
    new_public_key TEXT NOT NULL,

    -- Rotation metadata
    reason VARCHAR(255), -- 'scheduled', 'manual', 'security'
    rotated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- Indexes
-- ============================================

DO $$
BEGIN
    -- User public keys indexes
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='user_public_keys') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_user_public_keys_user_id ON user_public_keys(user_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_user_public_keys_next_rotation ON user_public_keys(next_rotation_at)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_user_public_keys_last_used ON user_public_keys(last_used_at DESC)';
    END IF;

    -- Key exchange indexes
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='key_exchanges') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_exchanges_initiator ON key_exchanges(initiator_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_exchanges_recipient ON key_exchanges(recipient_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_exchanges_status ON key_exchanges(status)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_exchanges_created ON key_exchanges(created_at DESC)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_exchanges_pair_status ON key_exchanges(initiator_id, recipient_id, status)';
    END IF;

    -- Encrypted messages indexes
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='encrypted_messages') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_encrypted_messages_sender ON encrypted_messages(sender_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_encrypted_messages_recipient ON encrypted_messages(recipient_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_encrypted_messages_delivered ON encrypted_messages(delivered)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_encrypted_messages_read ON encrypted_messages(read)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_encrypted_messages_created ON encrypted_messages(created_at DESC)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_encrypted_messages_pair ON encrypted_messages(sender_id, recipient_id, created_at DESC)';
    END IF;

    -- Used nonces indexes
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='used_nonces') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_used_nonces_pair ON used_nonces(conversation_pair)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_used_nonces_used_at ON used_nonces(used_at)';
    END IF;

    -- Key rotations indexes
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='key_rotations') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_rotations_user ON key_rotations(user_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_key_rotations_rotated_at ON key_rotations(rotated_at DESC)';
    END IF;
END $$;

-- ============================================
-- Cleanup Job for Old Nonces
-- ============================================
-- Delete nonces older than 7 days to manage table growth
-- This can be run periodically via a background job

CREATE OR REPLACE FUNCTION cleanup_old_nonces()
RETURNS void AS $$
BEGIN
    DELETE FROM used_nonces
    WHERE used_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;
