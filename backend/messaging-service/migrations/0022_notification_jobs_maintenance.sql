-- Maintenance functions for notification_jobs in messaging-service DB

-- Requeue stale claimed jobs older than N minutes (default 5)
CREATE OR REPLACE FUNCTION requeue_stale_notification_jobs(p_stale_minutes INTEGER DEFAULT 5)
RETURNS BIGINT AS $$
DECLARE
    v_updated BIGINT;
BEGIN
    UPDATE notification_jobs
    SET claimed_at = NULL,
        claimed_by = NULL
    WHERE status = 'pending'
      AND claimed_at IS NOT NULL
      AND claimed_at < NOW() - (p_stale_minutes || ' minutes')::INTERVAL;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION requeue_stale_notification_jobs(INTEGER) IS 'Requeue stale claimed pending jobs by clearing claim fields; returns affected rows.';

-- Cleanup failed jobs older than N days (default 30)
CREATE OR REPLACE FUNCTION cleanup_failed_notification_jobs(p_retention_days INTEGER DEFAULT 30)
RETURNS BIGINT AS $$
DECLARE
    v_deleted BIGINT;
BEGIN
    DELETE FROM notification_jobs
    WHERE status = 'failed'
      AND created_at < NOW() - (p_retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_failed_notification_jobs(INTEGER) IS 'Delete failed notification jobs older than retention; returns deleted rows.';

