-- ============================================
-- Migration: 002_add_auth_logs
-- Description: Add authentication audit logging table
-- Author: Nova Team
-- Date: 2025-01-15
-- ============================================

-- ============================================
-- Table: auth_logs
-- Description: Comprehensive authentication audit trail
-- ============================================
CREATE TABLE auth_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    ip_address INET,
    user_agent TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT event_type_valid CHECK (event_type IN (
        'login_success',
        'login_failed',
        'logout',
        'register',
        'email_verify',
        'password_reset_request',
        'password_reset_complete',
        'password_change',
        'token_refresh',
        'account_locked',
        'account_unlocked'
    )),
    CONSTRAINT status_valid CHECK (status IN ('success', 'failed', 'pending'))
);

-- Indexes for auth_logs table
CREATE INDEX idx_auth_logs_user_id ON auth_logs(user_id);
CREATE INDEX idx_auth_logs_event_type ON auth_logs(event_type);
CREATE INDEX idx_auth_logs_status ON auth_logs(status);
CREATE INDEX idx_auth_logs_created_at ON auth_logs(created_at DESC);
CREATE INDEX idx_auth_logs_ip_address ON auth_logs(ip_address);
CREATE INDEX idx_auth_logs_email ON auth_logs(email);

-- GIN index for JSONB metadata searching
CREATE INDEX idx_auth_logs_metadata ON auth_logs USING GIN (metadata);

-- Composite index for common queries
CREATE INDEX idx_auth_logs_user_event_created ON auth_logs(user_id, event_type, created_at DESC);

-- ============================================
-- Function: Clean up old auth logs (retention policy)
-- Description: Delete logs older than 90 days
-- ============================================
CREATE OR REPLACE FUNCTION cleanup_old_auth_logs()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM auth_logs
    WHERE created_at < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Function: Get failed login attempts in last hour
-- Description: Used for rate limiting and account locking
-- ============================================
CREATE OR REPLACE FUNCTION get_recent_failed_logins(
    p_email VARCHAR(255),
    p_ip_address INET,
    p_window_minutes INT DEFAULT 60
)
RETURNS INTEGER AS $$
DECLARE
    attempt_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO attempt_count
    FROM auth_logs
    WHERE (email = p_email OR ip_address = p_ip_address)
      AND event_type = 'login_failed'
      AND status = 'failed'
      AND created_at > NOW() - (p_window_minutes || ' minutes')::INTERVAL;

    RETURN attempt_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Function: Log authentication event (helper)
-- ============================================
CREATE OR REPLACE FUNCTION log_auth_event(
    p_user_id UUID,
    p_event_type VARCHAR(50),
    p_status VARCHAR(20),
    p_email VARCHAR(255) DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    log_id UUID;
BEGIN
    INSERT INTO auth_logs (
        user_id,
        event_type,
        status,
        email,
        ip_address,
        user_agent,
        metadata
    ) VALUES (
        p_user_id,
        p_event_type,
        p_status,
        p_email,
        p_ip_address,
        p_user_agent,
        p_metadata
    )
    RETURNING id INTO log_id;

    RETURN log_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- View: Recent suspicious activities
-- Description: Failed logins and locked accounts in last 24h
-- ============================================
CREATE OR REPLACE VIEW recent_suspicious_activities AS
SELECT
    al.id,
    al.user_id,
    u.email,
    u.username,
    al.event_type,
    al.ip_address,
    al.user_agent,
    al.created_at,
    COUNT(*) OVER (PARTITION BY al.ip_address) as attempts_from_ip
FROM auth_logs al
LEFT JOIN users u ON al.user_id = u.id
WHERE al.created_at > NOW() - INTERVAL '24 hours'
  AND al.status = 'failed'
ORDER BY al.created_at DESC;

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE auth_logs IS 'Comprehensive authentication audit trail for security monitoring';
COMMENT ON COLUMN auth_logs.event_type IS 'Type of authentication event (login, register, etc.)';
COMMENT ON COLUMN auth_logs.status IS 'Outcome of the event (success/failed/pending)';
COMMENT ON COLUMN auth_logs.metadata IS 'Additional context (error messages, device info, etc.)';
COMMENT ON FUNCTION cleanup_old_auth_logs() IS 'Delete logs older than 90 days for GDPR compliance';
COMMENT ON FUNCTION get_recent_failed_logins(VARCHAR, INET, INT) IS 'Count failed login attempts for rate limiting';
COMMENT ON VIEW recent_suspicious_activities IS 'Security monitoring view for failed auth attempts';
