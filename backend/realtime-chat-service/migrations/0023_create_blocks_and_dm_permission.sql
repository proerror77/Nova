-- ============================================================================
-- Migration: 0023_create_blocks_and_dm_permission
-- Description: Add blocks table and dm_permission for messaging authorization
-- Author: Nova Team
-- Date: 2025-11-30
-- ============================================================================

-- ============ BLOCKS TABLE ============
-- Stores user block relationships for messaging authorization
-- Note: user FKs removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL,
    blocked_id UUID NOT NULL,
    reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    UNIQUE(blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);

-- Indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);
-- Composite index for checking if A is blocked by B
CREATE INDEX IF NOT EXISTS idx_blocks_check ON blocks(blocked_id, blocker_id);

-- ============ DM PERMISSIONS TABLE ============
-- Note: user_settings is in identity-service, so we create a local table for DM permissions
CREATE TABLE IF NOT EXISTS dm_permissions (
    user_id UUID PRIMARY KEY,
    dm_permission VARCHAR(20) NOT NULL DEFAULT 'mutuals',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT dm_permission_check CHECK (dm_permission IN ('anyone', 'followers', 'mutuals', 'nobody'))
);

-- ============ MESSAGE REQUESTS TABLE (Optional) ============
-- For handling DM requests from non-permitted users
-- Note: user FKs removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS message_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL,
    recipient_id UUID NOT NULL,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    message_preview TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,

    -- Constraints
    UNIQUE(requester_id, recipient_id),
    CHECK (status IN ('pending', 'accepted', 'rejected', 'ignored')),
    CHECK (requester_id != recipient_id)
);

CREATE INDEX IF NOT EXISTS idx_message_requests_recipient ON message_requests(recipient_id, status);
CREATE INDEX IF NOT EXISTS idx_message_requests_requester ON message_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_message_requests_status ON message_requests(status) WHERE status = 'pending';

-- Note: Trigger for auto-removing follows on block removed
-- follows table is in graph-service database; this logic should be handled at application layer

-- ============ COMMENTS ============
COMMENT ON TABLE blocks IS 'User block relationships - blocked users cannot send messages';
COMMENT ON COLUMN blocks.blocker_id IS 'User who initiated the block';
COMMENT ON COLUMN blocks.blocked_id IS 'User who is blocked';
COMMENT ON COLUMN blocks.reason IS 'Optional reason for blocking (for moderation)';

COMMENT ON TABLE dm_permissions IS 'DM permission settings per user';
COMMENT ON COLUMN dm_permissions.dm_permission IS 'Who can send DMs: anyone, followers, mutuals (default), nobody';

COMMENT ON TABLE message_requests IS 'Pending message requests from non-permitted users';
COMMENT ON COLUMN message_requests.status IS 'Request status: pending, accepted, rejected, ignored';
COMMENT ON COLUMN message_requests.message_preview IS 'Preview of the first message (for recipient to decide)';
