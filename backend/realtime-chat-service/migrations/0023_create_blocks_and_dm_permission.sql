-- ============================================================================
-- Migration: 0023_create_blocks_and_dm_permission
-- Description: Add blocks table and dm_permission for messaging authorization
-- Author: Nova Team
-- Date: 2025-11-30
-- ============================================================================

-- ============ BLOCKS TABLE ============
-- Stores user block relationships for messaging authorization
CREATE TABLE IF NOT EXISTS blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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

-- ============ ADD DM PERMISSION TO USER SETTINGS ============
-- Extend user_settings with dm_permission column
DO $$
BEGIN
    -- Add column if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_settings' AND column_name = 'dm_permission'
    ) THEN
        ALTER TABLE user_settings
        ADD COLUMN dm_permission VARCHAR(20) NOT NULL DEFAULT 'mutuals';

        -- Add check constraint
        ALTER TABLE user_settings
        ADD CONSTRAINT dm_permission_check
        CHECK (dm_permission IN ('anyone', 'followers', 'mutuals', 'nobody'));
    END IF;
END $$;

-- ============ MESSAGE REQUESTS TABLE (Optional) ============
-- For handling DM requests from non-permitted users
CREATE TABLE IF NOT EXISTS message_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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

-- ============ TRIGGER: Auto-remove follows when blocked ============
CREATE OR REPLACE FUNCTION remove_follows_on_block()
RETURNS TRIGGER AS $$
BEGIN
    -- Remove any follow relationship between blocker and blocked (both directions)
    DELETE FROM follows
    WHERE (follower_id = NEW.blocker_id AND following_id = NEW.blocked_id)
       OR (follower_id = NEW.blocked_id AND following_id = NEW.blocker_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_remove_follows_on_block ON blocks;
CREATE TRIGGER trg_remove_follows_on_block
AFTER INSERT ON blocks
FOR EACH ROW
EXECUTE FUNCTION remove_follows_on_block();

-- ============ COMMENTS ============
COMMENT ON TABLE blocks IS 'User block relationships - blocked users cannot send messages';
COMMENT ON COLUMN blocks.blocker_id IS 'User who initiated the block';
COMMENT ON COLUMN blocks.blocked_id IS 'User who is blocked';
COMMENT ON COLUMN blocks.reason IS 'Optional reason for blocking (for moderation)';

COMMENT ON COLUMN user_settings.dm_permission IS 'Who can send DMs: anyone, followers, mutuals (default), nobody';

COMMENT ON TABLE message_requests IS 'Pending message requests from non-permitted users';
COMMENT ON COLUMN message_requests.status IS 'Request status: pending, accepted, rejected, ignored';
COMMENT ON COLUMN message_requests.message_preview IS 'Preview of the first message (for recipient to decide)';
