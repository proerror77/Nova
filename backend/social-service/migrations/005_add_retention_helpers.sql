-- ============================================================================
-- Migration: Add retention helper function for social-service processed events
-- Service: social-service
-- Purpose:
--   - Provide an explicit helper to clean up old idempotent processed_events rows
-- Safety:
--   - No schema changes, only CREATE OR REPLACE FUNCTION
--   - Must be called explicitly (e.g., via cronjob)
-- ============================================================================

-- Cleanup processed_events older than N days
-- Usage:
--   SELECT cleanup_social_processed_events(7);  -- keep last 7 days
CREATE OR REPLACE FUNCTION cleanup_social_processed_events(retention_days INTEGER)
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM processed_events
    WHERE created_at < NOW() - make_interval(days => retention_days);

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

