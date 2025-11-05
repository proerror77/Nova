-- Migration: Notification Device Tokens for Push Notifications
-- Purpose: Store APNs/FCM device tokens for users
-- Created: 2025-10-26

CREATE TABLE IF NOT EXISTS notification_device_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    device_platform VARCHAR(32) NOT NULL DEFAULT 'ios',
    app_version VARCHAR(32),
    locale VARCHAR(32),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_token)
);

CREATE INDEX IF NOT EXISTS idx_notification_device_tokens_user
ON notification_device_tokens(user_id)
WHERE is_active = TRUE;
