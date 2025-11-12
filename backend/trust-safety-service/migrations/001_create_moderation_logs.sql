-- Migration: Create moderation_logs table for Trust & Safety Service
-- Description: Stores moderation decisions for all UGC (User Generated Content)

CREATE TABLE IF NOT EXISTS moderation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id VARCHAR(255) NOT NULL,
    content_type VARCHAR(50) NOT NULL,
    user_id UUID NOT NULL,

    -- Risk scores (0.0 - 1.0)
    nsfw_score FLOAT NOT NULL DEFAULT 0.0,
    toxicity_score FLOAT NOT NULL DEFAULT 0.0,
    spam_score FLOAT NOT NULL DEFAULT 0.0,
    overall_score FLOAT NOT NULL,

    -- Decision
    approved BOOLEAN NOT NULL,
    violations TEXT[],

    -- Timestamps
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX idx_moderation_content ON moderation_logs(content_id);
CREATE INDEX idx_moderation_user ON moderation_logs(user_id);
CREATE INDEX idx_moderation_created ON moderation_logs(created_at DESC);
CREATE INDEX idx_moderation_approved ON moderation_logs(approved);

-- Index for spam detection (recent user activity)
CREATE INDEX idx_moderation_user_created ON moderation_logs(user_id, created_at DESC);

-- Comments
COMMENT ON TABLE moderation_logs IS 'Moderation decisions for all UGC';
COMMENT ON COLUMN moderation_logs.content_id IS 'Reference to content being moderated';
COMMENT ON COLUMN moderation_logs.content_type IS 'Type: post, comment, message, profile_bio, etc.';
COMMENT ON COLUMN moderation_logs.overall_score IS 'Combined risk score (0.0-1.0, higher = riskier)';
COMMENT ON COLUMN moderation_logs.approved IS 'True if auto-approved, false if flagged/rejected';
COMMENT ON COLUMN moderation_logs.violations IS 'Array of violation types found';
