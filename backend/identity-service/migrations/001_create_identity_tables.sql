-- Identity Service V2 Migration
-- This service OWNS: users, sessions, refresh_tokens, outbox_events
-- Clear data ownership: Only identity-service writes to these tables

-- Create users table (authentication data only)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_locked BOOLEAN NOT NULL DEFAULT FALSE,
    failed_login_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,
    password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Indexes for performance
    CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Create indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_is_active ON users(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_users_created_at ON users(created_at);

-- Create sessions table (active user sessions)
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_token VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,

    -- Ensure sessions expire
    CONSTRAINT session_expires CHECK (expires_at > created_at)
);

-- Create indexes for sessions
CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_token ON sessions(session_token);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);
CREATE INDEX idx_sessions_active ON sessions(expires_at) WHERE revoked_at IS NULL;

-- Create refresh tokens table
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    device_id VARCHAR(255),
    device_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,

    -- Ensure tokens expire and are single-use
    CONSTRAINT refresh_token_expires CHECK (expires_at > created_at)
);

-- Create indexes for refresh tokens
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
CREATE INDEX idx_refresh_tokens_active ON refresh_tokens(expires_at)
    WHERE used_at IS NULL AND revoked_at IS NULL;

-- Create transactional outbox table for event publishing
CREATE TABLE IF NOT EXISTS outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_id VARCHAR(255) NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    error_message TEXT,

    -- Ensure retry limits
    CONSTRAINT retry_limit CHECK (retry_count <= max_retries)
);

-- Create indexes for outbox
CREATE INDEX idx_outbox_unprocessed ON outbox_events(created_at)
    WHERE processed_at IS NULL AND retry_count < max_retries;
CREATE INDEX idx_outbox_aggregate ON outbox_events(aggregate_id, aggregate_type);
CREATE INDEX idx_outbox_processed_cleanup ON outbox_events(processed_at)
    WHERE processed_at IS NOT NULL;

-- Create password reset tokens table
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '1 hour',
    used_at TIMESTAMPTZ,

    CONSTRAINT reset_token_expires CHECK (expires_at > created_at)
);

-- Create indexes for password reset
CREATE INDEX idx_password_reset_user_id ON password_reset_tokens(user_id);
CREATE INDEX idx_password_reset_hash ON password_reset_tokens(token_hash);
CREATE INDEX idx_password_reset_active ON password_reset_tokens(expires_at)
    WHERE used_at IS NULL;

-- Create email verification tokens table
CREATE TABLE IF NOT EXISTS email_verification_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours',
    used_at TIMESTAMPTZ,

    CONSTRAINT verify_token_expires CHECK (expires_at > created_at)
);

-- Create indexes for email verification
CREATE INDEX idx_email_verify_user_id ON email_verification_tokens(user_id);
CREATE INDEX idx_email_verify_hash ON email_verification_tokens(token_hash);
CREATE INDEX idx_email_verify_active ON email_verification_tokens(expires_at)
    WHERE used_at IS NULL;

-- Create audit log table for security events
CREATE TABLE IF NOT EXISTS security_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for audit log
CREATE INDEX idx_audit_user_id ON security_audit_log(user_id);
CREATE INDEX idx_audit_event_type ON security_audit_log(event_type);
CREATE INDEX idx_audit_created_at ON security_audit_log(created_at);

-- Create triggers for updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Add comments for documentation
COMMENT ON TABLE users IS 'Core user authentication data - owned by identity-service';
COMMENT ON TABLE sessions IS 'Active user sessions for authentication';
COMMENT ON TABLE refresh_tokens IS 'JWT refresh tokens for session management';
COMMENT ON TABLE outbox_events IS 'Transactional outbox for reliable event publishing';
COMMENT ON TABLE password_reset_tokens IS 'Tokens for password reset flow';
COMMENT ON TABLE email_verification_tokens IS 'Tokens for email verification';
COMMENT ON TABLE security_audit_log IS 'Security events audit trail';

-- Grant permissions (adjust for your database setup)
-- GRANT SELECT ON users TO user_service;  -- user-service can read user IDs
-- GRANT SELECT ON users TO content_service;  -- content-service can validate user exists