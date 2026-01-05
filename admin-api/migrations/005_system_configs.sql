-- Migration: Create system_configs table (per spec section 3.3)
-- Date: 2026-01-05

-- System configuration table for storing key-value settings
CREATE TABLE IF NOT EXISTS system_configs (
    key VARCHAR(255) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_by UUID REFERENCES admin_users(id),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Insert default configurations
INSERT INTO system_configs (key, value, description) VALUES
    ('site.maintenance_mode', 'false'::jsonb, 'Enable/disable maintenance mode'),
    ('moderation.auto_review_enabled', 'true'::jsonb, 'Enable AI auto-moderation'),
    ('moderation.max_reports_before_review', '3'::jsonb, 'Number of reports before manual review required'),
    ('auth.max_login_attempts', '5'::jsonb, 'Maximum failed login attempts before lockout'),
    ('auth.lockout_duration_minutes', '15'::jsonb, 'Account lockout duration in minutes'),
    ('auth.session_timeout_hours', '2'::jsonb, 'JWT access token expiry in hours'),
    ('auth.refresh_token_days', '7'::jsonb, 'Refresh token expiry in days')
ON CONFLICT (key) DO NOTHING;

-- Trigger for updated_at
CREATE TRIGGER update_system_configs_updated_at
    BEFORE UPDATE ON system_configs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
