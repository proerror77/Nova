-- Signal Protocol Key Distribution Tables
-- Migration: 0028_create_signal_protocol_tables.sql
--
-- Implements storage for Signal Protocol key material:
-- - Device registration with identity keys
-- - Signed PreKeys (rotated periodically)
-- - One-time PreKeys (consumed on use)
-- - Kyber PreKeys (post-quantum)
-- - Sender Keys (group messaging)

-- Devices table: stores device registration and identity keys
CREATE TABLE IF NOT EXISTS signal_devices (
    user_id VARCHAR(255) NOT NULL,
    device_id INTEGER NOT NULL,
    registration_id INTEGER NOT NULL,
    identity_key TEXT NOT NULL,  -- Base64-encoded Curve25519 public key
    device_name VARCHAR(255),
    platform VARCHAR(50) NOT NULL DEFAULT 'unknown',
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, device_id)
);

-- Index for listing devices by user
CREATE INDEX IF NOT EXISTS idx_signal_devices_user_id ON signal_devices(user_id);

-- Signed PreKeys: rotated periodically (recommended: weekly)
CREATE TABLE IF NOT EXISTS signal_signed_prekeys (
    user_id VARCHAR(255) NOT NULL,
    device_id INTEGER NOT NULL,
    key_id INTEGER NOT NULL,
    public_key TEXT NOT NULL,     -- Base64-encoded Curve25519 public key
    signature TEXT NOT NULL,       -- Base64-encoded Ed25519 signature
    timestamp TIMESTAMPTZ NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, device_id, key_id),
    FOREIGN KEY (user_id, device_id) REFERENCES signal_devices(user_id, device_id) ON DELETE CASCADE
);

-- One-time PreKeys: consumed after single use
CREATE TABLE IF NOT EXISTS signal_prekeys (
    user_id VARCHAR(255) NOT NULL,
    device_id INTEGER NOT NULL,
    key_id INTEGER NOT NULL,
    public_key TEXT NOT NULL,     -- Base64-encoded Curve25519 public key
    claimed_at TIMESTAMPTZ,       -- NULL if not yet claimed
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, device_id, key_id),
    FOREIGN KEY (user_id, device_id) REFERENCES signal_devices(user_id, device_id) ON DELETE CASCADE
);

-- Index for finding unclaimed prekeys
CREATE INDEX IF NOT EXISTS idx_signal_prekeys_unclaimed
    ON signal_prekeys(user_id, device_id)
    WHERE claimed_at IS NULL;

-- Kyber PreKeys: post-quantum security (ML-KEM/Kyber1024)
CREATE TABLE IF NOT EXISTS signal_kyber_prekeys (
    user_id VARCHAR(255) NOT NULL,
    device_id INTEGER NOT NULL,
    key_id INTEGER NOT NULL,
    public_key TEXT NOT NULL,     -- Base64-encoded Kyber1024 public key
    signature TEXT NOT NULL,       -- Base64-encoded signature
    timestamp TIMESTAMPTZ NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, device_id, key_id),
    FOREIGN KEY (user_id, device_id) REFERENCES signal_devices(user_id, device_id) ON DELETE CASCADE
);

-- Index for finding unused Kyber prekeys
CREATE INDEX IF NOT EXISTS idx_signal_kyber_prekeys_unused
    ON signal_kyber_prekeys(user_id, device_id)
    WHERE used = FALSE;

-- Sender Keys: for efficient group messaging
CREATE TABLE IF NOT EXISTS signal_sender_keys (
    group_id VARCHAR(255) NOT NULL,
    sender_user_id VARCHAR(255) NOT NULL,
    sender_device_id INTEGER NOT NULL,
    distribution_message TEXT NOT NULL,  -- Base64-encoded SenderKeyDistributionMessage
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (group_id, sender_user_id, sender_device_id)
);

-- Index for group lookups
CREATE INDEX IF NOT EXISTS idx_signal_sender_keys_group ON signal_sender_keys(group_id);

-- Function to update last_active_at on device activity
CREATE OR REPLACE FUNCTION update_signal_device_activity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE signal_devices
    SET last_active_at = NOW()
    WHERE user_id = NEW.user_id AND device_id = NEW.device_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update device activity on prekey upload
CREATE OR REPLACE TRIGGER trigger_signal_prekey_activity
    AFTER INSERT ON signal_prekeys
    FOR EACH ROW
    EXECUTE FUNCTION update_signal_device_activity();

CREATE OR REPLACE TRIGGER trigger_signal_signed_prekey_activity
    AFTER INSERT ON signal_signed_prekeys
    FOR EACH ROW
    EXECUTE FUNCTION update_signal_device_activity();

-- Comments for documentation
COMMENT ON TABLE signal_devices IS 'Signal Protocol device registration with identity keys';
COMMENT ON TABLE signal_signed_prekeys IS 'Signal Protocol signed pre-keys (rotated periodically)';
COMMENT ON TABLE signal_prekeys IS 'Signal Protocol one-time pre-keys (consumed on use)';
COMMENT ON TABLE signal_kyber_prekeys IS 'Signal Protocol Kyber pre-keys for post-quantum security';
COMMENT ON TABLE signal_sender_keys IS 'Signal Protocol sender keys for group messaging';
