-- ============================================================================
-- Migration: Add retention helper functions for realtime-chat-service
-- Service: realtime-chat-service
-- Purpose:
--   - Provide helpers to purge expired to-device messages and old room key history
-- Safety:
--   - No schema changes, only CREATE OR REPLACE FUNCTION
--   - Functions are opt-in and must be called explicitly
-- ============================================================================

-- Cleanup to_device_messages that passed their TTL (expires_at)
-- Usage:
--   SELECT cleanup_expired_to_device_messages();
CREATE OR REPLACE FUNCTION cleanup_expired_to_device_messages()
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM to_device_messages
    WHERE expires_at < NOW();

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

-- Optional cleanup for very old room_key_history entries
-- NOTE: Only use if product requirements allow dropping old E2EE history keys.
-- Usage:
--   SELECT cleanup_old_room_key_history(365);  -- keep last 365 days
CREATE OR REPLACE FUNCTION cleanup_old_room_key_history(retention_days INTEGER)
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM room_key_history
    WHERE created_at < NOW() - make_interval(days => retention_days);

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

