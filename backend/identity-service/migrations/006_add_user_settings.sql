-- P0: User Settings migration (from user-service)
-- Single-writer: identity-service owns user preferences/settings

CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    dm_permission VARCHAR(20) NOT NULL DEFAULT 'anyone',  -- 'anyone', 'followers', 'mutuals', 'nobody'
    email_notifications BOOLEAN NOT NULL DEFAULT true,
    push_notifications BOOLEAN NOT NULL DEFAULT true,
    marketing_emails BOOLEAN NOT NULL DEFAULT false,
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    dark_mode BOOLEAN NOT NULL DEFAULT false,
    privacy_level VARCHAR(20) NOT NULL DEFAULT 'public',  -- 'public', 'friends_only', 'private'
    allow_messages BOOLEAN NOT NULL DEFAULT true,
    show_online_status BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Constraint for dm_permission values
ALTER TABLE user_settings
    ADD CONSTRAINT chk_dm_permission
    CHECK (dm_permission IN ('anyone', 'followers', 'mutuals', 'nobody'));

-- Constraint for privacy_level values
ALTER TABLE user_settings
    ADD CONSTRAINT chk_privacy_level
    CHECK (privacy_level IN ('public', 'friends_only', 'private'));

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_user_settings_dm_permission ON user_settings (dm_permission);

-- Function to auto-create settings when user is created
CREATE OR REPLACE FUNCTION create_default_user_settings()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_settings (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-create settings on user creation
DROP TRIGGER IF EXISTS trg_create_user_settings ON users;
CREATE TRIGGER trg_create_user_settings
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION create_default_user_settings();

-- Backfill existing users (idempotent)
INSERT INTO user_settings (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;

COMMENT ON TABLE user_settings IS 'User preferences and settings (P0 migration from user-service)';
