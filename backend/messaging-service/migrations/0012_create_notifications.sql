-- Migration: Notifications System
-- Purpose: Support real-time notifications for messages, reactions, and user actions
-- Created: 2025-10-26

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL, -- 'message', 'reaction', 'mention', 'follow', 'comment', 'like'
    action_type VARCHAR(50), -- Details about the action
    target_type VARCHAR(50), -- 'message', 'post', 'user', 'conversation'
    target_id UUID, -- ID of the target (message_id, post_id, user_id, etc.)
    message JSONB, -- Rich notification data
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ -- Optional: auto-delete old notifications
);

-- Index for querying notifications by recipient
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_created
ON notifications(recipient_id, created_at DESC)
WHERE is_read = FALSE;

-- Index for fetching unread notifications
CREATE INDEX IF NOT EXISTS idx_notifications_unread
ON notifications(recipient_id, is_read, created_at DESC)
WHERE is_read = FALSE;

-- Index for marking read in bulk
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_type
ON notifications(recipient_id, notification_type, created_at DESC);

-- Create notification subscriptions table (for opt-in/opt-out)
CREATE TABLE IF NOT EXISTS notification_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL, -- 'message', 'reaction', 'mention', 'follow', 'comment', 'like'
    is_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, notification_type)
);

-- Create notification preferences table
CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    enable_push_notifications BOOLEAN DEFAULT TRUE,
    enable_email_notifications BOOLEAN DEFAULT FALSE,
    enable_sms_notifications BOOLEAN DEFAULT FALSE,
    notification_frequency VARCHAR(50) DEFAULT 'immediate', -- 'immediate', 'hourly', 'daily'
    quiet_hours_start TIME, -- e.g., 22:00
    quiet_hours_end TIME,   -- e.g., 08:00
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create notification_read_receipts for tracking read status
CREATE TABLE IF NOT EXISTS notification_read_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unread_count INT DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for quick access to read receipts
CREATE INDEX IF NOT EXISTS idx_notification_read_receipts_user
ON notification_read_receipts(user_id);

-- Create notification delivery log (for Firebase Cloud Messaging/APNs)
CREATE TABLE IF NOT EXISTS notification_delivery_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    delivery_method VARCHAR(50), -- 'fcm', 'apns', 'websocket'
    device_token TEXT,
    status VARCHAR(50), -- 'pending', 'sent', 'failed', 'delivered'
    error_message TEXT,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for delivery tracking
CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_notification
ON notification_delivery_logs(notification_id, status);
