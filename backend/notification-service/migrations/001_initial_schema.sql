-- ============================================================================
-- Notification Service Database Schema
-- ============================================================================

-- ============================================================================
-- Table: notifications
-- Stores all user notifications
-- ============================================================================
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,

    -- Notification content
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    notification_type TEXT NOT NULL, -- 'like', 'comment', 'follow', 'mention', 'message', 'system', 'video', 'stream'
    data JSONB DEFAULT NULL,

    -- Related entities
    related_user_id UUID DEFAULT NULL,
    related_post_id UUID DEFAULT NULL,
    related_message_id UUID DEFAULT NULL,

    -- Status tracking
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ DEFAULT NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMPTZ DEFAULT NULL,

    -- Metadata
    priority TEXT DEFAULT 'normal', -- 'low', 'normal', 'high', 'critical'
    status TEXT DEFAULT 'pending', -- 'pending', 'sent', 'failed', 'delivered'
    channel TEXT DEFAULT 'in_app', -- 'push', 'email', 'in_app'

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ DEFAULT NULL,
    expires_at TIMESTAMPTZ DEFAULT NULL
);

-- Indexes for notifications
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_is_read ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_created_at ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read_created_at ON notifications(is_read, created_at DESC) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(notification_type);
CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications(status) WHERE status IN ('pending', 'failed');

-- ============================================================================
-- Table: push_tokens
-- Stores device push notification tokens (FCM/APNs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,

    -- Token details
    token TEXT NOT NULL,
    token_type TEXT NOT NULL, -- 'FCM', 'APNs'
    device_id TEXT NOT NULL,
    platform TEXT DEFAULT 'unknown', -- 'ios', 'android', 'web'
    app_version TEXT DEFAULT NULL,

    -- Status
    is_valid BOOLEAN DEFAULT TRUE,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ DEFAULT NULL,

    -- Constraints
    UNIQUE(user_id, token, token_type)
);

-- Indexes for push_tokens
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON push_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_push_tokens_token ON push_tokens(token);
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id_is_valid ON push_tokens(user_id, is_valid);
CREATE INDEX IF NOT EXISTS idx_push_tokens_device_id ON push_tokens(device_id);

-- ============================================================================
-- Table: push_delivery_logs
-- Tracks push notification delivery attempts
-- ============================================================================
CREATE TABLE IF NOT EXISTS push_delivery_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    token_id UUID NOT NULL REFERENCES push_tokens(id) ON DELETE CASCADE,

    -- Delivery status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'success', 'failed'
    error_message TEXT DEFAULT NULL,
    error_code TEXT DEFAULT NULL,

    -- Timing
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    attempted_at TIMESTAMPTZ DEFAULT NULL,
    completed_at TIMESTAMPTZ DEFAULT NULL,

    -- Retry tracking
    retry_count INT DEFAULT 0,
    next_retry_at TIMESTAMPTZ DEFAULT NULL
);

-- Indexes for push_delivery_logs
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_notification_id ON push_delivery_logs(notification_id);
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_token_id ON push_delivery_logs(token_id);
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_status ON push_delivery_logs(status) WHERE status IN ('pending', 'failed');
CREATE INDEX IF NOT EXISTS idx_push_delivery_logs_next_retry ON push_delivery_logs(next_retry_at) WHERE next_retry_at IS NOT NULL;

-- ============================================================================
-- Table: notification_preferences
-- User notification preferences
-- ============================================================================
CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE,

    -- Global toggle
    enabled BOOLEAN DEFAULT TRUE,

    -- Per-type preferences
    like_enabled BOOLEAN DEFAULT TRUE,
    comment_enabled BOOLEAN DEFAULT TRUE,
    follow_enabled BOOLEAN DEFAULT TRUE,
    mention_enabled BOOLEAN DEFAULT TRUE,
    message_enabled BOOLEAN DEFAULT TRUE,
    stream_enabled BOOLEAN DEFAULT TRUE,
    video_enabled BOOLEAN DEFAULT TRUE,
    system_enabled BOOLEAN DEFAULT TRUE,

    -- Quiet hours (ISO 8601 time format, e.g., "22:00-08:00")
    quiet_hours_start TEXT DEFAULT NULL,
    quiet_hours_end TEXT DEFAULT NULL,

    -- Preferred channels
    prefer_fcm BOOLEAN DEFAULT TRUE,
    prefer_apns BOOLEAN DEFAULT TRUE,
    prefer_email BOOLEAN DEFAULT FALSE,

    -- Timestamps
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for notification_preferences
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user_id ON notification_preferences(user_id);

-- ============================================================================
-- Table: notification_dedup
-- Tracks notification deduplication (1-minute window)
-- ============================================================================
CREATE TABLE IF NOT EXISTS notification_dedup (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    event_key TEXT NOT NULL, -- Composite key: e.g., "like:post_id" or "follow:follower_id"

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '1 minute'),

    -- Constraints
    UNIQUE(user_id, event_type, event_key)
);

-- Indexes for notification_dedup
CREATE INDEX IF NOT EXISTS idx_notification_dedup_expires_at ON notification_dedup(expires_at);
CREATE INDEX IF NOT EXISTS idx_notification_dedup_user_event ON notification_dedup(user_id, event_type, event_key);

-- Auto-cleanup expired dedup entries (every 5 minutes)
-- This can be done via a cron job or background task

-- ============================================================================
-- Functions and Triggers
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for push_tokens
DROP TRIGGER IF EXISTS update_push_tokens_updated_at ON push_tokens;
CREATE TRIGGER update_push_tokens_updated_at
    BEFORE UPDATE ON push_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for notification_preferences
DROP TRIGGER IF EXISTS update_notification_preferences_updated_at ON notification_preferences;
CREATE TRIGGER update_notification_preferences_updated_at
    BEFORE UPDATE ON notification_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Sample Data (Optional - for testing)
-- ============================================================================

-- Insert default preferences for a test user (optional)
-- INSERT INTO notification_preferences (user_id, enabled)
-- VALUES ('00000000-0000-0000-0000-000000000001', TRUE)
-- ON CONFLICT (user_id) DO NOTHING;

COMMENT ON TABLE notifications IS 'User notifications across all channels';
COMMENT ON TABLE push_tokens IS 'Device push notification tokens (FCM/APNs)';
COMMENT ON TABLE push_delivery_logs IS 'Push notification delivery tracking';
COMMENT ON TABLE notification_preferences IS 'User notification preferences';
COMMENT ON TABLE notification_dedup IS 'Notification deduplication tracking (1-minute window)';
