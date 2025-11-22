-- Add lightweight tables for devices, invite codes, and user channel subscriptions
-- Follows expand/contract: only additive changes

-- Ensure sessions table has device metadata columns used by the service
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE IF EXISTS sessions
    ADD COLUMN IF NOT EXISTS device_id VARCHAR(255),
    ADD COLUMN IF NOT EXISTS device_name VARCHAR(255),
    ADD COLUMN IF NOT EXISTS device_type VARCHAR(100),
    ADD COLUMN IF NOT EXISTS os_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS os_version VARCHAR(100),
    ADD COLUMN IF NOT EXISTS browser_name VARCHAR(100),
    ADD COLUMN IF NOT EXISTS browser_version VARCHAR(100),
    ADD COLUMN IF NOT EXISTS location_country VARCHAR(100),
    ADD COLUMN IF NOT EXISTS location_city VARCHAR(100),
    ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_sessions_user_activity
    ON sessions (user_id, last_activity_at DESC)
    WHERE revoked_at IS NULL;

-- Invite codes (single-writer: identity-service)
CREATE TABLE IF NOT EXISTS invite_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    issuer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_email TEXT,
    target_phone TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    redeemed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    redeemed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invite_codes_code ON invite_codes (code);
CREATE INDEX IF NOT EXISTS idx_invite_codes_issuer ON invite_codes (issuer_user_id);
CREATE INDEX IF NOT EXISTS idx_invite_codes_redeemed ON invite_codes (redeemed_at);

-- User channel subscriptions (owned by identity-service, refers to channel ids from content-service)
CREATE TABLE IF NOT EXISTS user_channels (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel_id TEXT NOT NULL,
    subscribed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, channel_id)
);

CREATE INDEX IF NOT EXISTS idx_user_channels_user ON user_channels (user_id);
