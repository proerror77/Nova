-- Transcoding Progress Enhancements
-- Add webhook support and job retry tracking for real-time progress updates

-- 1. Webhook configurations for video transcoding notifications
CREATE TABLE IF NOT EXISTS video_webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    webhook_url TEXT NOT NULL,
    webhook_secret TEXT,  -- Optional HMAC secret for signature verification
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,

    -- Prevent duplicate webhook registrations for same video+url
    UNIQUE(video_id, webhook_url)
);

-- 2. Webhook delivery attempts tracking (for retry logic)
CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_id UUID NOT NULL REFERENCES video_webhooks(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,  -- 'transcoding.progress', 'transcoding.completed', 'transcoding.failed'
    payload JSONB NOT NULL,
    attempt_number INT NOT NULL DEFAULT 1,
    status TEXT NOT NULL,  -- 'pending', 'success', 'failed', 'retrying'
    response_status_code INT,
    response_body TEXT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE
);

-- 3. Add transcoding job tracking fields to videos table
ALTER TABLE videos
    ADD COLUMN IF NOT EXISTS transcoding_retry_count INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS transcoding_last_retry_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS transcoding_priority INT DEFAULT 5 CHECK (transcoding_priority BETWEEN 1 AND 10),
    ADD COLUMN IF NOT EXISTS transcoding_error_message TEXT,
    ADD COLUMN IF NOT EXISTS transcoding_current_stage TEXT,
    ADD COLUMN IF NOT EXISTS transcoding_progress_percent INT DEFAULT 0 CHECK (transcoding_progress_percent BETWEEN 0 AND 100),
    ADD COLUMN IF NOT EXISTS transcoding_estimated_remaining_seconds INT;

-- 4. Indexes for efficient webhook and job queries
CREATE INDEX IF NOT EXISTS idx_video_webhooks_video_id
    ON video_webhooks(video_id);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook_id
    ON webhook_deliveries(webhook_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_status
    ON webhook_deliveries(status)
    WHERE status IN ('pending', 'retrying');

-- Index for queue status queries
CREATE INDEX IF NOT EXISTS idx_videos_transcoding_status
    ON videos(transcoding_status, transcoding_priority DESC)
    WHERE deleted_at IS NULL;

-- Index for retry scheduling
CREATE INDEX IF NOT EXISTS idx_videos_retry_schedule
    ON videos(transcoding_last_retry_at)
    WHERE transcoding_retry_count > 0 AND transcoding_status = 'failed';

-- 5. Update trigger for updated_at
CREATE OR REPLACE FUNCTION update_video_webhooks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER video_webhooks_updated_at
    BEFORE UPDATE ON video_webhooks
    FOR EACH ROW
    EXECUTE FUNCTION update_video_webhooks_updated_at();

-- 6. View for queue statistics
CREATE OR REPLACE VIEW transcoding_queue_stats AS
SELECT
    COUNT(*) FILTER (WHERE transcoding_status = 'pending') AS pending_count,
    COUNT(*) FILTER (WHERE transcoding_status = 'processing') AS processing_count,
    COUNT(*) FILTER (WHERE transcoding_status = 'failed') AS failed_count,
    COUNT(*) FILTER (WHERE transcoding_status = 'published') AS published_count,
    AVG(EXTRACT(EPOCH FROM (updated_at - created_at))) FILTER (WHERE transcoding_status = 'published') AS avg_process_time_seconds,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (updated_at - created_at)))
        FILTER (WHERE transcoding_status = 'published') AS median_process_time_seconds
FROM videos
WHERE deleted_at IS NULL;

-- 7. Function to cleanup old webhook deliveries (retention policy)
CREATE OR REPLACE FUNCTION cleanup_old_webhook_deliveries(retention_days INT DEFAULT 30)
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    DELETE FROM webhook_deliveries
    WHERE completed_at < NOW() - (retention_days || ' days')::INTERVAL
      AND status = 'success';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- 8. Comments for documentation
COMMENT ON TABLE video_webhooks IS 'Webhook endpoints registered for video transcoding notifications';
COMMENT ON TABLE webhook_deliveries IS 'Audit log of webhook delivery attempts with retry tracking';
COMMENT ON COLUMN videos.transcoding_priority IS 'Job priority (1-10), higher number = higher priority';
COMMENT ON COLUMN videos.transcoding_retry_count IS 'Number of retry attempts for failed transcoding jobs';
COMMENT ON COLUMN videos.transcoding_progress_percent IS 'Current transcoding progress (0-100)';
