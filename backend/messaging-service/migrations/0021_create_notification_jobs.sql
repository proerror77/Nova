-- Migration: Create notification_jobs table for messaging-service queue (claim-safe)

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
    last_error TEXT,
    claimed_at TIMESTAMPTZ,
    claimed_by TEXT
);

-- Indexes aligned with claim-safe processing
CREATE INDEX IF NOT EXISTS idx_notification_jobs_status_retry
ON notification_jobs(status, retry_count, created_at)
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_notification_jobs_created_at
ON notification_jobs(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_jobs_device_token
ON notification_jobs(device_token);

CREATE INDEX IF NOT EXISTS idx_notification_jobs_pending_claim
ON notification_jobs (created_at)
WHERE status = 'pending' AND (claimed_at IS NULL OR claimed_at < NOW() - INTERVAL '5 minutes');

