-- Phase 7B Feature 2: Private Messaging System
-- Simplified schema: conversations + messages (no partitioning, no search index)
-- Design principle: Make it work first, optimize later

-- ============================================
-- 1. Conversations Table
-- ============================================
-- Stores conversation metadata (1:1 and group)
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'group')),
    name VARCHAR(255),  -- Only for group conversations
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Business rule: group conversations must have a name
    CONSTRAINT valid_group_name CHECK (
        conversation_type = 'direct' OR
        (conversation_type = 'group' AND name IS NOT NULL)
    )
);

-- Index for conversation listing (sorted by activity)
CREATE INDEX idx_conversations_updated_at ON conversations(updated_at DESC);
CREATE INDEX idx_conversations_created_by ON conversations(created_by);

COMMENT ON TABLE conversations IS 'Conversation metadata (1:1 and group chats)';
COMMENT ON COLUMN conversations.conversation_type IS 'Type: direct (1:1) or group';
COMMENT ON COLUMN conversations.name IS 'Group chat name (NULL for direct conversations)';

-- ============================================
-- 2. Conversation Members Table
-- ============================================
-- Stores conversation participants and their metadata
CREATE TABLE IF NOT EXISTS conversation_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Read receipt tracking
    last_read_message_id UUID,  -- No FK to avoid cascading issues
    last_read_at TIMESTAMP WITH TIME ZONE,

    -- User preferences
    is_muted BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,

    -- Ensure each user can only be in a conversation once
    CONSTRAINT unique_conversation_member UNIQUE(conversation_id, user_id)
);

-- Indexes for common queries
CREATE INDEX idx_conversation_members_conversation ON conversation_members(conversation_id);
CREATE INDEX idx_conversation_members_user ON conversation_members(user_id);

-- Partial index for active conversations (most common query)
CREATE INDEX idx_conversation_members_user_active ON conversation_members(user_id, is_archived)
    WHERE is_archived = FALSE;

COMMENT ON TABLE conversation_members IS 'Conversation participants and their settings';
COMMENT ON COLUMN conversation_members.role IS 'User role: owner (creator), admin, or member';
COMMENT ON COLUMN conversation_members.last_read_message_id IS 'Last message read by this user (for unread count)';
COMMENT ON COLUMN conversation_members.is_muted IS 'Whether user has muted notifications for this conversation';
COMMENT ON COLUMN conversation_members.is_archived IS 'Whether user has archived this conversation';

-- ============================================
-- 3. Messages Table
-- ============================================
-- Stores encrypted messages
-- NOTE: No partitioning in Phase 1 (optimize later when > 10M rows)
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),

    -- Encrypted content (client-side encryption)
    encrypted_content TEXT NOT NULL,  -- Base64-encoded ciphertext
    nonce VARCHAR(48) NOT NULL,  -- Base64-encoded nonce (24 bytes)

    -- Message metadata
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'system')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Future features (not implemented in Phase 1)
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Composite index for message history queries (most common)
CREATE INDEX idx_messages_conversation_created ON messages(conversation_id, created_at DESC);

-- Index for sender queries (e.g., "messages from user X")
CREATE INDEX idx_messages_sender ON messages(sender_id);

-- Index for recent messages across all conversations (for search/sync)
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);

COMMENT ON TABLE messages IS 'Encrypted messages (E2E encryption, server cannot read content)';
COMMENT ON COLUMN messages.encrypted_content IS 'Base64-encoded ciphertext (encrypted by client)';
COMMENT ON COLUMN messages.nonce IS 'Unique nonce for encryption (24 bytes, base64-encoded)';
COMMENT ON COLUMN messages.message_type IS 'Type: text (user message) or system (join/leave events)';

-- ============================================
-- 4. Triggers
-- ============================================

-- Auto-update conversations.updated_at when new message is sent
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET updated_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_conversation_timestamp
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_timestamp();

COMMENT ON FUNCTION update_conversation_timestamp() IS 'Auto-update conversation timestamp when new message arrives';

-- ============================================
-- 5. User Public Key Storage (for E2E encryption)
-- ============================================

-- Add public_key column to users table if not exists
ALTER TABLE users ADD COLUMN IF NOT EXISTS public_key VARCHAR(64);  -- Base64-encoded (32 bytes)

CREATE INDEX IF NOT EXISTS idx_users_public_key ON users(public_key) WHERE public_key IS NOT NULL;

COMMENT ON COLUMN users.public_key IS 'User public key for E2E encryption (NaCl box, 32 bytes base64)';

-- ============================================
-- 6. Helper Functions
-- ============================================

-- Function to get unread message count for a user in a conversation
CREATE OR REPLACE FUNCTION get_unread_count(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS INTEGER AS $$
DECLARE
    v_last_read_message_id UUID;
    v_last_read_created_at TIMESTAMP WITH TIME ZONE;
    v_unread_count INTEGER;
BEGIN
    -- Get last read message ID
    SELECT last_read_message_id INTO v_last_read_message_id
    FROM conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id;

    -- If never read any message, count all messages
    IF v_last_read_message_id IS NULL THEN
        SELECT COUNT(*) INTO v_unread_count
        FROM messages
        WHERE conversation_id = p_conversation_id;
        RETURN v_unread_count;
    END IF;

    -- Get the timestamp of the last read message
    SELECT created_at INTO v_last_read_created_at
    FROM messages
    WHERE id = v_last_read_message_id;

    -- Count messages created after the last read message
    SELECT COUNT(*) INTO v_unread_count
    FROM messages
    WHERE conversation_id = p_conversation_id
      AND created_at > v_last_read_created_at;

    RETURN v_unread_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_unread_count(UUID, UUID) IS 'Calculate unread message count for a user in a conversation';

-- ============================================
-- 7. Initial Data / Constraints
-- ============================================

-- Add unique constraint for direct conversations (prevent duplicates)
-- NOTE: This is enforced at application level, not database level
-- (because checking "same set of members" requires complex logic)

-- Example: To find existing direct conversation between user A and B:
-- SELECT c.id FROM conversations c
-- INNER JOIN conversation_members cm1 ON c.id = cm1.conversation_id AND cm1.user_id = 'user-a-uuid'
-- INNER JOIN conversation_members cm2 ON c.id = cm2.conversation_id AND cm2.user_id = 'user-b-uuid'
-- WHERE c.conversation_type = 'direct'
-- GROUP BY c.id
-- HAVING COUNT(DISTINCT cm1.user_id) = 2;

-- ============================================
-- 8. Performance Notes
-- ============================================

-- Expected Performance (with proper indexes):
-- - Conversation list query (20 items): ~50ms
-- - Message history query (50 items): ~30ms
-- - Send message (INSERT + trigger): ~20ms
-- - Unread count calculation: ~10ms (using timestamp comparison)

-- Scalability:
-- - No partitioning needed until > 10M messages
-- - No read replicas needed until > 1000 QPS
-- - WebSocket scaling via Redis Pub/Sub (horizontal)

-- Future Optimizations (when needed):
-- 1. Monthly partitioning: PARTITION BY RANGE (created_at)
-- 2. Read replicas: Route SELECT queries to replicas
-- 3. Materialized views: For complex aggregations
-- 4. BRIN indexes: For time-based queries on large tables

-- ============================================
-- 9. Migration Rollback
-- ============================================

-- To rollback this migration:
-- DROP TRIGGER IF EXISTS trigger_update_conversation_timestamp ON messages;
-- DROP FUNCTION IF EXISTS update_conversation_timestamp();
-- DROP FUNCTION IF EXISTS get_unread_count(UUID, UUID);
-- DROP TABLE IF EXISTS messages CASCADE;
-- DROP TABLE IF EXISTS conversation_members CASCADE;
-- DROP TABLE IF EXISTS conversations CASCADE;
-- ALTER TABLE users DROP COLUMN IF EXISTS public_key;
