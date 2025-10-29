-- Migration: Create notification_jobs table for push notification queue
-- Created: 2025-10-29
-- Description: Implements persistent queue for APNs and FCM push notifications with retry logic

-- Create notification_jobs table
CREATE TABLE IF NOT EXISTS notification_jobs (
    id UUID PRIMARY KEY,
    device_token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('ios', 'android')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    badge INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    last_error TEXT
);

-- Index for processing pending notifications efficiently
CREATE INDEX idx_notification_jobs_status_retry
ON notification_jobs(status, retry_count, created_at)
WHERE status = 'pending';

-- Index for looking up notification status by ID
CREATE INDEX idx_notification_jobs_created_at
ON notification_jobs(created_at DESC);

-- Index for device token lookups (useful for debugging and analytics)
CREATE INDEX idx_notification_jobs_device_token
ON notification_jobs(device_token);

-- Add comments for documentation
COMMENT ON TABLE notification_jobs IS 'Queue table for push notifications (APNs and FCM) with retry logic';
COMMENT ON COLUMN notification_jobs.id IS 'Unique job identifier';
COMMENT ON COLUMN notification_jobs.device_token IS 'APNs device token or FCM registration token';
COMMENT ON COLUMN notification_jobs.platform IS 'Target platform: ios (APNs) or android (FCM)';
COMMENT ON COLUMN notification_jobs.title IS 'Notification title';
COMMENT ON COLUMN notification_jobs.body IS 'Notification body text';
COMMENT ON COLUMN notification_jobs.badge IS 'Optional badge count for app icon';
COMMENT ON COLUMN notification_jobs.status IS 'Job status: pending, sent, or failed';
COMMENT ON COLUMN notification_jobs.retry_count IS 'Number of retry attempts made';
COMMENT ON COLUMN notification_jobs.max_retries IS 'Maximum retry attempts before marking as failed';
COMMENT ON COLUMN notification_jobs.created_at IS 'When the job was created';
COMMENT ON COLUMN notification_jobs.sent_at IS 'When the notification was successfully sent';
COMMENT ON COLUMN notification_jobs.last_error IS 'Last error message if send failed';
