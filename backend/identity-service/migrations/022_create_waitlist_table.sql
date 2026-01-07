-- Waitlist table for collecting emails from users without invite codes
-- Issue #255: "Don't have an invite?" email collection

CREATE TABLE IF NOT EXISTS waitlist_emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    source VARCHAR(50) DEFAULT 'invite_page',  -- where user signed up
    status VARCHAR(50) DEFAULT 'pending',       -- pending, invited, registered
    invited_at TIMESTAMPTZ,                     -- when invite was sent
    invite_code_id UUID REFERENCES invite_codes(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Prevent duplicate entries
    CONSTRAINT unique_waitlist_email UNIQUE (email)
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_waitlist_emails_email ON waitlist_emails(email);
CREATE INDEX IF NOT EXISTS idx_waitlist_emails_status ON waitlist_emails(status);
CREATE INDEX IF NOT EXISTS idx_waitlist_emails_created_at ON waitlist_emails(created_at DESC);

-- Add comment for documentation
COMMENT ON TABLE waitlist_emails IS 'Stores email addresses from users who want to join but do not have an invite code';
COMMENT ON COLUMN waitlist_emails.status IS 'pending = waiting, invited = invite sent, registered = user registered';
