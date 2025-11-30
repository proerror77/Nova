-- P0: User Reports and Enforcement tables (from user-service migration)
-- Single-writer: trust-safety-service owns all moderation enforcement data

-- User Reports (users can report content/other users)
CREATE TABLE IF NOT EXISTS user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_user_id UUID NOT NULL,       -- User submitting the report
    reported_user_id UUID,                -- User being reported (optional if reporting content)
    reported_content_id VARCHAR(255),     -- Content being reported (optional if reporting user)
    reported_content_type VARCHAR(50),    -- 'post', 'comment', 'message', 'profile', 'user'
    report_type VARCHAR(50) NOT NULL,     -- 'spam', 'harassment', 'hate_speech', 'nsfw', 'impersonation', 'other'
    description TEXT,                     -- Optional description from reporter
    status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- 'pending', 'reviewed', 'actioned', 'dismissed'
    reviewed_by UUID,                     -- Admin who reviewed
    reviewed_at TIMESTAMPTZ,
    resolution VARCHAR(100),              -- What action was taken
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Constraint for status values
ALTER TABLE user_reports
    ADD CONSTRAINT chk_report_status
    CHECK (status IN ('pending', 'reviewed', 'actioned', 'dismissed'));

-- Constraint: must have either user or content
ALTER TABLE user_reports
    ADD CONSTRAINT chk_report_target
    CHECK (reported_user_id IS NOT NULL OR reported_content_id IS NOT NULL);

-- Indexes for user reports
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON user_reports (reporter_user_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported_user ON user_reports (reported_user_id) WHERE reported_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports (status);
CREATE INDEX IF NOT EXISTS idx_user_reports_created ON user_reports (created_at DESC);

-- User Warnings (strike system)
CREATE TABLE IF NOT EXISTS user_warnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,                -- User receiving the warning
    warning_type VARCHAR(50) NOT NULL,    -- 'content_violation', 'spam', 'harassment', 'tos_violation'
    severity VARCHAR(20) NOT NULL,        -- 'mild', 'moderate', 'severe'
    strike_points INT NOT NULL DEFAULT 1, -- Points toward ban threshold
    reason TEXT NOT NULL,                 -- Explanation of the violation
    moderation_log_id UUID,               -- Reference to moderation_logs if applicable
    report_id UUID REFERENCES user_reports(id) ON DELETE SET NULL,
    issued_by UUID NOT NULL,              -- Admin who issued the warning (or system UUID)
    acknowledged BOOLEAN NOT NULL DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,               -- Warnings can expire (null = permanent)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Constraint for severity values
ALTER TABLE user_warnings
    ADD CONSTRAINT chk_warning_severity
    CHECK (severity IN ('mild', 'moderate', 'severe'));

-- Indexes for user warnings
CREATE INDEX IF NOT EXISTS idx_user_warnings_user ON user_warnings (user_id);
CREATE INDEX IF NOT EXISTS idx_user_warnings_type ON user_warnings (warning_type);
CREATE INDEX IF NOT EXISTS idx_user_warnings_created ON user_warnings (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_warnings_active ON user_warnings (user_id, expires_at)
    WHERE expires_at IS NULL OR expires_at > NOW();

-- User Bans (temporary or permanent)
CREATE TABLE IF NOT EXISTS user_bans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,                -- User being banned
    ban_type VARCHAR(20) NOT NULL,        -- 'temporary', 'permanent', 'shadow'
    reason TEXT NOT NULL,                 -- Reason for the ban
    banned_by UUID NOT NULL,              -- Admin who issued the ban
    warning_id UUID REFERENCES user_warnings(id) ON DELETE SET NULL,
    report_id UUID REFERENCES user_reports(id) ON DELETE SET NULL,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at TIMESTAMPTZ,                  -- NULL for permanent bans
    lifted_at TIMESTAMPTZ,                -- Set when ban is manually lifted
    lifted_by UUID,                       -- Admin who lifted the ban
    lift_reason TEXT,                     -- Why the ban was lifted early
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Constraint for ban type
ALTER TABLE user_bans
    ADD CONSTRAINT chk_ban_type
    CHECK (ban_type IN ('temporary', 'permanent', 'shadow'));

-- Indexes for user bans
CREATE INDEX IF NOT EXISTS idx_user_bans_user ON user_bans (user_id);
CREATE INDEX IF NOT EXISTS idx_user_bans_active ON user_bans (user_id, ends_at)
    WHERE lifted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_bans_type ON user_bans (ban_type);
CREATE INDEX IF NOT EXISTS idx_user_bans_created ON user_bans (created_at DESC);

-- View for active bans (convenience)
CREATE OR REPLACE VIEW active_user_bans AS
SELECT *
FROM user_bans
WHERE lifted_at IS NULL
  AND (ends_at IS NULL OR ends_at > NOW());

-- Function to calculate total active strike points for a user
CREATE OR REPLACE FUNCTION get_user_strike_points(p_user_id UUID)
RETURNS INT AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(strike_points)
         FROM user_warnings
         WHERE user_id = p_user_id
           AND (expires_at IS NULL OR expires_at > NOW())),
        0
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to check if user is currently banned
CREATE OR REPLACE FUNCTION is_user_banned(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM user_bans
        WHERE user_id = p_user_id
          AND lifted_at IS NULL
          AND (ends_at IS NULL OR ends_at > NOW())
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Comments
COMMENT ON TABLE user_reports IS 'User-submitted reports against content or users (P0 migration)';
COMMENT ON TABLE user_warnings IS 'Warning/strike system for policy violations (P0 migration)';
COMMENT ON TABLE user_bans IS 'Temporary and permanent user bans (P0 migration)';
COMMENT ON FUNCTION get_user_strike_points IS 'Calculate total active strike points for a user';
COMMENT ON FUNCTION is_user_banned IS 'Check if a user is currently banned';
