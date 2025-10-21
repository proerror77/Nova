-- ============================================
-- Notifications Schema for Phase 5
-- ============================================

-- Notification preferences table
CREATE TABLE IF NOT EXISTS notification_preferences (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Notification types
    push_enabled BOOLEAN DEFAULT true,
    email_enabled BOOLEAN DEFAULT true,
    in_app_enabled BOOLEAN DEFAULT true,

    -- Notification preferences by type
    likes_enabled BOOLEAN DEFAULT true,
    comments_enabled BOOLEAN DEFAULT true,
    follows_enabled BOOLEAN DEFAULT true,
    messages_enabled BOOLEAN DEFAULT true,
    live_notifications_enabled BOOLEAN DEFAULT true,

    -- Quiet hours
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    quiet_hours_enabled BOOLEAN DEFAULT false,

    -- Created/updated timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(user_id)
);

-- Notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Notification content
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,

    -- Metadata
    related_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    related_post_id UUID,
    related_entity_id VARCHAR(255),

    -- Status
    read BOOLEAN DEFAULT false,
    read_at TIMESTAMP WITH TIME ZONE,
    dismissed BOOLEAN DEFAULT false,
    dismissed_at TIMESTAMP WITH TIME ZONE,

    -- Delivery status
    push_sent BOOLEAN DEFAULT false,
    email_sent BOOLEAN DEFAULT false,
    in_app_created BOOLEAN DEFAULT true,

    -- Push notification tokens
    push_token_id UUID,
    device_platform VARCHAR(20), -- 'ios', 'android', 'web'

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP + INTERVAL '30 days',

    CONSTRAINT valid_type CHECK (type IN ('like', 'comment', 'follow', 'message', 'live_start', 'stream_update'))
);

-- Device push tokens
CREATE TABLE IF NOT EXISTS device_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Token info
    token VARCHAR(500) NOT NULL,
    platform VARCHAR(20) NOT NULL, -- 'ios', 'android'
    device_id VARCHAR(255),
    app_version VARCHAR(20),
    os_version VARCHAR(50),

    -- Status
    active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMP WITH TIME ZONE,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_platform CHECK (platform IN ('ios', 'android'))
);

-- Notification delivery logs (for auditing)
CREATE TABLE IF NOT EXISTS notification_delivery_logs (
    id BIGSERIAL PRIMARY KEY,
    notification_id BIGINT REFERENCES notifications(id) ON DELETE CASCADE,

    -- Delivery details
    channel VARCHAR(50) NOT NULL, -- 'push', 'email', 'in_app'
    status VARCHAR(50) NOT NULL, -- 'pending', 'sent', 'failed', 'delivered'

    -- Error details
    error_message TEXT,
    error_code VARCHAR(50),

    -- Retry info
    attempt_number INT DEFAULT 1,
    max_retries INT DEFAULT 3,
    next_retry_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read_created ON notifications(user_id, read, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_user_id ON notification_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_device_push_tokens_user_id ON device_push_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_device_push_tokens_active ON device_push_tokens(active);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_notification_id ON notification_delivery_logs(notification_id);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_status ON notification_delivery_logs(status);

-- Updated trigger for notification_preferences
CREATE OR REPLACE FUNCTION update_notification_preferences_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notification_preferences_update_timestamp
    BEFORE UPDATE ON notification_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_notification_preferences_timestamp();
