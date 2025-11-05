-- Migration: Moderation and Reports System
-- Purpose: Support user reporting, moderation, and content management
-- Created: 2025-10-26

-- Create report reasons lookup table
CREATE TABLE IF NOT EXISTS report_reasons (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reason_code VARCHAR(50) NOT NULL UNIQUE, -- 'spam', 'harassment', 'hate_speech', 'nsfw', 'misinformation', 'copyright', 'other'
    reason_label VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert default report reasons
INSERT INTO report_reasons (reason_code, reason_label, description) VALUES
    ('spam', 'Spam or Abuse', 'Repetitive or unsolicited messages'),
    ('harassment', 'Harassment or Bullying', 'Threatening or harassing behavior'),
    ('hate_speech', 'Hate Speech', 'Promotes hate based on protected characteristics'),
    ('nsfw', 'NSFW Content', 'Sexually explicit or adult content'),
    ('misinformation', 'Misinformation', 'False or misleading information'),
    ('copyright', 'Copyright Infringement', 'Violates intellectual property rights'),
    ('scam', 'Scam or Fraud', 'Fraudulent or deceptive activity'),
    ('other', 'Other Violation', 'Other policy violation')
ON CONFLICT (reason_code) DO NOTHING;

-- Create reports table
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    reason_id UUID NOT NULL REFERENCES report_reasons(id),
    reason_code VARCHAR(50) NOT NULL,
    target_type VARCHAR(50) NOT NULL, -- 'user', 'post', 'message', 'comment'
    target_id UUID NOT NULL, -- ID of the reported content/user
    description TEXT,
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'investigating', 'resolved', 'dismissed'
    severity VARCHAR(50) DEFAULT 'low', -- 'low', 'medium', 'high', 'critical'
    priority INT DEFAULT 0, -- For prioritization
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- Index for filtering reports
CREATE INDEX IF NOT EXISTS idx_reports_status
ON reports(status, created_at DESC);

-- Index for finding reports about a user
CREATE INDEX IF NOT EXISTS idx_reports_reported_user
ON reports(reported_user_id, status, created_at DESC)
WHERE status != 'dismissed';

-- Index for finding reports by reporter
CREATE INDEX IF NOT EXISTS idx_reports_reporter
ON reports(reporter_id, created_at DESC);

-- Index for finding reports of content
CREATE INDEX IF NOT EXISTS idx_reports_target
ON reports(target_type, target_id, status);

-- Create moderation actions table
CREATE TABLE IF NOT EXISTS moderation_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID REFERENCES reports(id) ON DELETE CASCADE,
    moderator_id UUID NOT NULL REFERENCES users(id),
    action_type VARCHAR(50) NOT NULL, -- 'warn', 'mute', 'suspend', 'ban', 'delete_content', 'resolve'
    target_type VARCHAR(50), -- 'user', 'post', 'message', 'comment'
    target_id UUID,
    duration_days INT, -- For temporary actions (mute, suspend)
    reason TEXT,
    notes TEXT,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'appealed', 'reversed'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ, -- When the action expires (for temporary actions)
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tracking active actions
CREATE INDEX IF NOT EXISTS idx_moderation_actions_target
ON moderation_actions(target_type, target_id, status)
WHERE status = 'active';

-- Index for user restrictions
CREATE INDEX IF NOT EXISTS idx_moderation_actions_user
ON moderation_actions(target_id, action_type, expires_at)
WHERE target_type = 'user' AND status = 'active';

-- Create appeal table for action appeals
CREATE TABLE IF NOT EXISTS moderation_appeals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    action_id UUID NOT NULL REFERENCES moderation_actions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    supporting_info TEXT,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'approved', 'denied'
    decision_reason TEXT,
    reviewed_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

-- Index for pending appeals
CREATE INDEX IF NOT EXISTS idx_appeals_pending
ON moderation_appeals(status, created_at)
WHERE status = 'pending';

-- Create moderation queue table
CREATE TABLE IF NOT EXISTS moderation_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_id UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
    queue_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'assigned', 'completed'
    assigned_to UUID REFERENCES users(id),
    priority INT DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- Index for queue management
CREATE INDEX IF NOT EXISTS idx_queue_status
ON moderation_queue(queue_status, priority DESC, created_at ASC);

-- Create content filter table (for automatic flagging)
CREATE TABLE IF NOT EXISTS content_filters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    filter_type VARCHAR(50), -- 'keyword', 'pattern', 'ml_model'
    filter_value TEXT NOT NULL,
    severity VARCHAR(50) DEFAULT 'low',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create suspicious activity log
CREATE TABLE IF NOT EXISTS activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(50), -- 'mass_report', 'spam_messages', 'rapid_follows'
    severity VARCHAR(50) DEFAULT 'low',
    description TEXT,
    metadata JSONB,
    action_taken VARCHAR(50), -- 'flagged', 'warned', 'restricted'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for activity tracking
CREATE INDEX IF NOT EXISTS idx_activity_logs_user
ON activity_logs(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_activity_logs_severity
ON activity_logs(severity, created_at DESC)
WHERE action_taken IS NULL;
