-- Migration: 0010_e2ee_vodozemac_tables
-- Description: Add tables for vodozemac-based E2EE (Olm/Megolm) end-to-end encryption
-- Implements multi-device E2EE with Olm 1:1 sessions and Megolm group sessions

-- 1. User devices for multi-device E2EE
-- Tracks all devices associated with a user for E2EE key management
-- Note: user_id FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    device_id TEXT NOT NULL UNIQUE,
    device_name TEXT,

    -- Curve25519 identity key (base64 encoded for Olm)
    identity_key TEXT NOT NULL,
    -- Ed25519 signing key (base64 encoded for signature verification)
    signing_key TEXT NOT NULL,

    -- Device verification status (trust level for E2EE)
    verified BOOLEAN NOT NULL DEFAULT false,

    -- Last seen timestamp (for stale device detection)
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Uniqueness constraint per user
    CONSTRAINT unique_user_device UNIQUE (user_id, device_id)
);

CREATE INDEX idx_user_devices_user_id ON user_devices(user_id);
CREATE INDEX idx_user_devices_device_id ON user_devices(device_id);

-- 2. Olm accounts (one per device, pickled state)
-- Stores encrypted Olm account state - essential for decrypting 1:1 messages
CREATE TABLE IF NOT EXISTS olm_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id TEXT NOT NULL UNIQUE REFERENCES user_devices(device_id) ON DELETE CASCADE,

    -- Pickled Olm account (encrypted with account_encryption_key from KMS)
    -- Contains identity keys, one-time key state, etc.
    pickled_account BYTEA NOT NULL,
    -- Nonce used for encrypting the pickle (random per encryption)
    pickle_nonce BYTEA NOT NULL,

    -- Number of one-time keys currently uploaded to server
    -- Used to determine when to refresh OTK supply
    uploaded_otk_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_olm_accounts_device ON olm_accounts(device_id);

-- 3. One-time pre-keys for Olm session establishment
-- Essential for forward secrecy - ephemeral keys used to initiate Olm sessions
CREATE TABLE IF NOT EXISTS olm_one_time_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id TEXT NOT NULL REFERENCES user_devices(device_id) ON DELETE CASCADE,

    -- Key ID returned by vodozemac (e.g., "AAAAA")
    key_id TEXT NOT NULL,
    -- Curve25519 public key (base64)
    public_key TEXT NOT NULL,

    -- Whether this key has been claimed (one-time use)
    claimed BOOLEAN NOT NULL DEFAULT false,
    -- Which device claimed it
    claimed_by_device_id TEXT,
    claimed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_device_key UNIQUE (device_id, key_id)
);

-- Index for efficient unclaimed key queries (OTK distribution to clients)
CREATE INDEX idx_olm_otk_device_unclaimed ON olm_one_time_keys(device_id, claimed)
    WHERE NOT claimed;
-- Index for stale key cleanup
CREATE INDEX idx_olm_otk_created ON olm_one_time_keys(created_at);

-- 4. Olm sessions (1:1 encrypted channels between devices)
-- Each Olm session is a bilateral encrypted channel between two specific devices
CREATE TABLE IF NOT EXISTS olm_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Our device (who owns this session)
    our_device_id TEXT NOT NULL REFERENCES user_devices(device_id) ON DELETE CASCADE,
    -- Their device's identity key (Curve25519, base64)
    -- We don't store their device_id because we might not know it yet
    their_identity_key TEXT NOT NULL,

    -- Pickled Olm session (encrypted with session_encryption_key)
    pickled_session BYTEA NOT NULL,
    -- Nonce for this pickle
    pickle_nonce BYTEA NOT NULL,

    -- Session lifecycle tracking
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_olm_session UNIQUE (our_device_id, their_identity_key)
);

CREATE INDEX idx_olm_sessions_device ON olm_sessions(our_device_id);
CREATE INDEX idx_olm_sessions_identity_key ON olm_sessions(their_identity_key);

-- 5. Megolm outbound sessions (for sending to rooms/groups)
-- One session per room per device - used for encrypting messages to that room
CREATE TABLE IF NOT EXISTS megolm_outbound_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Room/conversation this session is for
    room_id UUID NOT NULL,
    -- Device that owns this outbound session
    device_id TEXT NOT NULL REFERENCES user_devices(device_id) ON DELETE CASCADE,

    -- Pickled Megolm outbound session (encrypted with session_encryption_key)
    pickled_session BYTEA NOT NULL,
    pickle_nonce BYTEA NOT NULL,

    -- Session ID (from vodozemac - unique identifier for this session)
    session_id TEXT NOT NULL,

    -- Message count tracking (for rotation policy)
    message_count INTEGER NOT NULL DEFAULT 0,
    -- Max messages before rotation (prevents key reuse after many messages)
    max_messages INTEGER NOT NULL DEFAULT 100,

    -- Creation time (for time-based rotation)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Max age before rotation (default 1 week = 604800 seconds)
    max_age_seconds INTEGER NOT NULL DEFAULT 604800,

    CONSTRAINT unique_outbound_room_device UNIQUE (room_id, device_id)
);

CREATE INDEX idx_megolm_outbound_room ON megolm_outbound_sessions(room_id);
CREATE INDEX idx_megolm_outbound_session_id ON megolm_outbound_sessions(session_id);
-- Index for rotation policy enforcement
CREATE INDEX idx_megolm_outbound_age ON megolm_outbound_sessions(created_at);

-- 6. Megolm inbound sessions (for receiving from rooms/groups)
-- Received from other devices - needed to decrypt group messages
CREATE TABLE IF NOT EXISTS megolm_inbound_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Room this session is for
    room_id UUID NOT NULL,
    -- Our device (who received this session)
    our_device_id TEXT NOT NULL REFERENCES user_devices(device_id) ON DELETE CASCADE,

    -- Sender's identity key (who created/shared this session)
    sender_identity_key TEXT NOT NULL,
    -- Session ID (matches the outbound session_id from sender)
    session_id TEXT NOT NULL UNIQUE,

    -- Pickled Megolm inbound session (encrypted with session_encryption_key)
    pickled_session BYTEA NOT NULL,
    pickle_nonce BYTEA NOT NULL,

    -- First known message index (for replay protection)
    -- When we first receive a key, we mark the index to prevent decrypting earlier messages
    first_known_index INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_inbound_session UNIQUE (our_device_id, session_id)
);

CREATE INDEX idx_megolm_inbound_room ON megolm_inbound_sessions(room_id);
CREATE INDEX idx_megolm_inbound_session_id ON megolm_inbound_sessions(session_id);
CREATE INDEX idx_megolm_inbound_device ON megolm_inbound_sessions(our_device_id);

-- 7. To-device messages queue (for key sharing, verification, etc.)
-- Used for reliable delivery of encryption-related messages
CREATE TABLE IF NOT EXISTS to_device_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Sender information
    sender_user_id UUID NOT NULL,
    sender_device_id TEXT NOT NULL,

    -- Recipient information
    recipient_user_id UUID NOT NULL,
    recipient_device_id TEXT NOT NULL,

    -- Message type (m.room_key, m.key.verification.start, m.key.verification.accept, etc.)
    message_type TEXT NOT NULL,

    -- Encrypted content (JSON payload encrypted with Olm)
    content BYTEA NOT NULL,

    -- Delivery tracking
    delivered BOOLEAN NOT NULL DEFAULT false,
    delivered_at TIMESTAMPTZ,

    -- TTL (messages expire after 7 days if not delivered)
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_to_device_recipient ON to_device_messages(
    recipient_user_id, recipient_device_id, delivered
);
-- Index for efficient expiration cleanup
CREATE INDEX idx_to_device_expires ON to_device_messages(expires_at)
    WHERE NOT delivered;
-- Index for cleanup queries
CREATE INDEX idx_to_device_created ON to_device_messages(created_at);

-- 8. Room key history (for late-joining members)
-- Stores shared room keys for users who join after encryption started
-- Essential for message history access in E2EE rooms
CREATE TABLE IF NOT EXISTS room_key_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    room_id UUID NOT NULL,
    session_id TEXT NOT NULL,

    -- Exported room key (Olm encrypted for each authorized device)
    -- This is the Megolm session key exported and then encrypted with each device's Olm session
    exported_key BYTEA NOT NULL,

    -- Which device this export is for (one entry per authorized device)
    for_device_id TEXT NOT NULL REFERENCES user_devices(device_id) ON DELETE CASCADE,

    -- From which message index this key is valid
    from_index INTEGER NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_room_key_history_room ON room_key_history(room_id);
CREATE INDEX idx_room_key_history_device ON room_key_history(for_device_id);
CREATE INDEX idx_room_key_history_session ON room_key_history(session_id);

-- ============================================================================
-- PERFORMANCE AND MAINTENANCE INDEXES
-- ============================================================================

-- Periodic cleanup indexes
CREATE INDEX idx_to_device_cleanup ON to_device_messages(expires_at);

-- Device verification workflow
CREATE INDEX idx_user_devices_verified ON user_devices(verified);

-- ============================================================================
-- FOREIGN KEYS (ensure referential integrity)
-- ============================================================================

-- Add constraint for sender_device_id in to_device_messages
ALTER TABLE to_device_messages
ADD CONSTRAINT fk_to_device_sender
FOREIGN KEY (sender_user_id, sender_device_id)
REFERENCES user_devices(user_id, device_id)
ON DELETE CASCADE;

-- Add constraint for recipient_device_id in to_device_messages
ALTER TABLE to_device_messages
ADD CONSTRAINT fk_to_device_recipient
FOREIGN KEY (recipient_user_id, recipient_device_id)
REFERENCES user_devices(user_id, device_id)
ON DELETE CASCADE;

-- ============================================================================
-- ENCRYPTION NOTES
-- ============================================================================
--
-- All pickled_* columns should be encrypted at the application layer:
--   - pickled_account: Encrypted with account-specific KMS key
--   - pickled_session (Olm): Encrypted with session-specific KMS key
--   - pickled_session (Megolm): Encrypted with session-specific KMS key
--   - exported_key: Encrypted with recipient device Olm session
--
-- Nonce columns are stored plaintext and should be random per encryption.
--
-- This schema assumes:
--   - PostgreSQL 13+ for gen_random_uuid()
--   - All timestamps in UTC (TIMESTAMPTZ)
--   - Identity keys and public keys are stored as base64 TEXT
--
-- ============================================================================

-- DOWN MIGRATION (for rollback)
-- If you need to rollback, execute in this order:
--
-- DROP TABLE IF EXISTS room_key_history CASCADE;
-- DROP TABLE IF EXISTS to_device_messages CASCADE;
-- DROP TABLE IF EXISTS megolm_inbound_sessions CASCADE;
-- DROP TABLE IF EXISTS megolm_outbound_sessions CASCADE;
-- DROP TABLE IF EXISTS olm_sessions CASCADE;
-- DROP TABLE IF EXISTS olm_one_time_keys CASCADE;
-- DROP TABLE IF EXISTS olm_accounts CASCADE;
-- DROP TABLE IF EXISTS user_devices CASCADE;
