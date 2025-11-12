-- Migration: Create appeals table for Trust & Safety Service
-- Description: Appeal workflow for users to contest moderation decisions

-- Create enum for appeal status
CREATE TYPE appeal_status AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE IF NOT EXISTS appeals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    moderation_id UUID NOT NULL REFERENCES moderation_logs(id) ON DELETE RESTRICT,
    user_id UUID NOT NULL,
    reason TEXT NOT NULL,

    -- State machine: pending -> approved/rejected
    status appeal_status NOT NULL DEFAULT 'pending',

    -- Admin review
    admin_id UUID,
    admin_note TEXT,

    -- Timestamps
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMP,

    -- Constraint: Only one appeal per moderation decision
    UNIQUE(moderation_id)
);

-- Indexes
CREATE INDEX idx_appeals_moderation ON appeals(moderation_id);
CREATE INDEX idx_appeals_status ON appeals(status);
CREATE INDEX idx_appeals_user ON appeals(user_id);
CREATE INDEX idx_appeals_created ON appeals(created_at DESC);

-- Check constraint: reviewed_at must be set when status is not pending
ALTER TABLE appeals ADD CONSTRAINT check_reviewed_at
    CHECK (
        (status = 'pending' AND reviewed_at IS NULL AND admin_id IS NULL) OR
        (status IN ('approved', 'rejected') AND reviewed_at IS NOT NULL AND admin_id IS NOT NULL)
    );

-- Comments
COMMENT ON TABLE appeals IS 'User appeals for moderation decisions';
COMMENT ON COLUMN appeals.status IS 'Appeal status: pending (initial), approved (overturned), rejected (upheld)';
COMMENT ON COLUMN appeals.reason IS 'User-provided reason for appeal';
COMMENT ON COLUMN appeals.admin_note IS 'Admin comment on appeal decision';
COMMENT ON TYPE appeal_status IS 'Appeal lifecycle: pending -> approved/rejected (final)';
