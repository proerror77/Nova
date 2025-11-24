-- ============================================================================
-- Migration: 130_create_user_settings
-- Description: Create user settings table for preferences and configurations
-- Author: Nova Team
-- Date: 2025-11-24
-- iOS Model: ios/NovaSocial/Shared/Models/User/UserModels.swift:UserSettings
-- ============================================================================

-- ============ USER SETTINGS TABLE ============
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Notification preferences
    email_notifications BOOLEAN NOT NULL DEFAULT TRUE,
    push_notifications BOOLEAN NOT NULL DEFAULT TRUE,
    marketing_emails BOOLEAN NOT NULL DEFAULT FALSE,

    -- Localization
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    language VARCHAR(10) NOT NULL DEFAULT 'en',

    -- UI preferences
    dark_mode BOOLEAN NOT NULL DEFAULT FALSE,

    -- Privacy settings
    privacy_level VARCHAR(20) NOT NULL DEFAULT 'public',
    allow_messages BOOLEAN NOT NULL DEFAULT TRUE,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT privacy_level_check CHECK (privacy_level IN ('public', 'friends', 'private')),
    CONSTRAINT language_format CHECK (language ~* '^[a-z]{2}(-[A-Z]{2})?$'),
    CONSTRAINT timezone_format CHECK (LENGTH(timezone) > 0)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_user_settings_language ON user_settings(language);
CREATE INDEX IF NOT EXISTS idx_user_settings_privacy_level ON user_settings(privacy_level);

-- Trigger: Update updated_at timestamp
CREATE TRIGGER update_user_settings_updated_at
    BEFORE UPDATE ON user_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============ BACKFILL: Create default settings for existing users ============
INSERT INTO user_settings (user_id)
SELECT id FROM users WHERE deleted_at IS NULL
ON CONFLICT (user_id) DO NOTHING;

-- ============ FUNCTION: Auto-create settings for new users ============
CREATE OR REPLACE FUNCTION create_default_user_settings()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_settings (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_user_settings
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION create_default_user_settings();

-- ============ COMMENTS FOR DOCUMENTATION ============
COMMENT ON TABLE user_settings IS 'User preferences and configuration settings (1:1 with users table)';
COMMENT ON COLUMN user_settings.email_notifications IS 'Enable/disable email notifications (likes, comments, follows)';
COMMENT ON COLUMN user_settings.push_notifications IS 'Enable/disable push notifications on mobile devices';
COMMENT ON COLUMN user_settings.marketing_emails IS 'Opt-in for marketing and promotional emails';
COMMENT ON COLUMN user_settings.timezone IS 'User timezone in IANA format (e.g., America/New_York, Asia/Shanghai)';
COMMENT ON COLUMN user_settings.language IS 'User language preference in ISO 639-1 format (e.g., en, zh-CN, ja)';
COMMENT ON COLUMN user_settings.dark_mode IS 'Dark mode UI preference';
COMMENT ON COLUMN user_settings.privacy_level IS 'Account privacy: public (anyone), friends (approved followers), private (invite-only)';
COMMENT ON COLUMN user_settings.allow_messages IS 'Allow direct messages from non-followers';
