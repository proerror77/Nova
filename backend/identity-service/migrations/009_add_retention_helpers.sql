-- ============================================================================
-- Migration: Add retention helper functions for identity-service
-- Service: identity-service
-- Purpose:
--   - Provide explicit, opt-in helpers for cleaning up old audit and outbox rows
--   - Provide helpers to purge expired password/email verification tokens
-- Safety:
--   - No schema changes, only CREATE OR REPLACE FUNCTION definitions
--   - Functions must be called explicitly by an operator/cronjob
--   - Follows expand-only pattern (no implicit data deletion)
-- ============================================================================

-- Cleanup function for security_audit_log
-- Usage example:
--   SELECT cleanup_security_audit_log(180);  -- keep last 180 days
CREATE OR REPLACE FUNCTION cleanup_security_audit_log(retention_days INTEGER)
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM security_audit_log
    WHERE created_at < NOW() - make_interval(days => retention_days);

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

-- Cleanup function for processed outbox events
-- Usage example:
--   SELECT cleanup_processed_outbox_events(30);  -- keep last 30 days of processed events
CREATE OR REPLACE FUNCTION cleanup_processed_outbox_events(retention_days INTEGER)
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM outbox_events
    WHERE processed_at IS NOT NULL
      AND processed_at < NOW() - make_interval(days => retention_days);

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

-- Cleanup function for expired password reset tokens
-- Safe because tokens are unusable after expires_at
CREATE OR REPLACE FUNCTION cleanup_expired_password_reset_tokens()
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM password_reset_tokens
    WHERE expires_at < NOW();

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

-- Cleanup function for expired email verification tokens
CREATE OR REPLACE FUNCTION cleanup_expired_email_verification_tokens()
RETURNS INTEGER AS $$
DECLARE
    deleted INTEGER;
BEGIN
    DELETE FROM email_verification_tokens
    WHERE expires_at < NOW();

    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$ LANGUAGE plpgsql;

