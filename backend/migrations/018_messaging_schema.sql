-- Phase 7B Feature 2: Private Messaging System (aligned with code)
-- Conversations + Members + Messages + helper function for unread count

-- ============================================
-- 1. Conversations
-- ============================================
-- Ensure uuid extension is available
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'group')),
    name VARCHAR(255),
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT valid_group_name CHECK (
        conversation_type = 'direct' OR (conversation_type = 'group' AND name IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_conversations_updated_at ON conversations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_created_by ON conversations(created_by);

-- ============================================
-- 2. Conversation Members
-- ============================================
CREATE TABLE IF NOT EXISTS conversation_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_read_message_id UUID,
    last_read_at TIMESTAMP WITH TIME ZONE,
    is_muted BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    CONSTRAINT unique_conversation_member UNIQUE(conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_members_conversation ON conversation_members(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user_active ON conversation_members(user_id, is_archived)
    WHERE is_archived = FALSE;

-- ============================================
-- 3. Messages (Encrypted)
-- ============================================
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    encrypted_content TEXT NOT NULL,
    nonce VARCHAR(48) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'system')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);

-- Auto-update conversations.updated_at when new message is inserted
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations SET updated_at = NEW.created_at WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_update_conversation_timestamp'
    ) THEN
        CREATE TRIGGER trigger_update_conversation_timestamp
            AFTER INSERT ON messages
            FOR EACH ROW
            EXECUTE FUNCTION update_conversation_timestamp();
    END IF;
END $$;

-- ============================================
-- 4. Helper: unread count
-- ============================================
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
    SELECT last_read_message_id INTO v_last_read_message_id
    FROM conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id;

    IF v_last_read_message_id IS NULL THEN
        SELECT COUNT(*) INTO v_unread_count
        FROM messages
        WHERE conversation_id = p_conversation_id;
        RETURN v_unread_count;
    END IF;

    SELECT created_at INTO v_last_read_created_at
    FROM messages
    WHERE id = v_last_read_message_id;

    SELECT COUNT(*) INTO v_unread_count
    FROM messages
    WHERE conversation_id = p_conversation_id
      AND created_at > v_last_read_created_at;

    RETURN v_unread_count;
END;
$$ LANGUAGE plpgsql;
