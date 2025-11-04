-- ============================================
-- Migration: 072_add_notification_claim_fields
-- Description: Add claimed_at / claimed_by for safe multi-worker claiming
-- ============================================

ALTER TABLE notification_jobs
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS claimed_by TEXT NULL;

-- Index to efficiently pick pending, unclaimed (or expired claim) jobs in creation order
CREATE INDEX IF NOT EXISTS idx_notification_jobs_pending_claim
ON notification_jobs (created_at)
WHERE status = 'pending' AND (claimed_at IS NULL OR claimed_at < NOW() - INTERVAL '5 minutes');

COMMENT ON COLUMN notification_jobs.claimed_at IS 'Timestamp when a worker claimed this job. NULL = not claimed.';
COMMENT ON COLUMN notification_jobs.claimed_by IS 'Opaque worker identifier that claimed the job.';

