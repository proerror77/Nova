-- Create sessions table for device tracking and session management
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    device_name VARCHAR(255),
    device_type VARCHAR(50), -- 'mobile', 'web', 'desktop', 'tablet'
    os_name VARCHAR(100),
    os_version VARCHAR(50),
    browser_name VARCHAR(100),
    browser_version VARCHAR(50),
    ip_address INET,
    user_agent TEXT,
    location_country VARCHAR(2),
    location_city VARCHAR(255),
    access_token_jti VARCHAR(255) UNIQUE, -- JWT ID for revocation
    refresh_token_jti VARCHAR(255) UNIQUE,
    last_activity_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indices
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_device_id ON sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_last_activity_at ON sessions(last_activity_at);

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_sessions_updated_at
BEFORE UPDATE ON sessions
FOR EACH ROW
EXECUTE FUNCTION update_sessions_updated_at();
