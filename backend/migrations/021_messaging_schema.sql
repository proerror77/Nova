-- ============================================
-- Private Messaging Schema for Phase 5
-- ============================================

-- Conversations table (1-1 chats)
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Participants
    user_1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Metadata
    last_message_at TIMESTAMP WITH TIME ZONE,
    last_message_id UUID,
    message_count INT DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT different_users CHECK (user_1_id != user_2_id)
);

-- Messages table
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,

    -- Sender
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Content
    content TEXT NOT NULL,
    content_type VARCHAR(50) DEFAULT 'text', -- 'text', 'image', 'video', 'file', 'link'

    -- Attachments
    attachment_urls TEXT[], -- Array of attachment URLs
    attachment_types VARCHAR(50)[], -- Corresponding types

    -- Status
    delivered BOOLEAN DEFAULT false,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read BOOLEAN DEFAULT false,
    read_at TIMESTAMP WITH TIME ZONE,
    edited BOOLEAN DEFAULT false,
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted BOOLEAN DEFAULT false,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- Reactions/interactions
    reaction_count INT DEFAULT 0,
    reply_count INT DEFAULT 0,
    is_reply_to UUID REFERENCES messages(id) ON DELETE SET NULL,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    scheduled_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT content_not_empty CHECK (LENGTH(TRIM(content)) > 0 OR attachment_urls IS NOT NULL)
);

-- Message reactions/emoji responses
CREATE TABLE IF NOT EXISTS message_reactions (
    id BIGSERIAL PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    emoji VARCHAR(10) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(message_id, user_id, emoji)
);

-- Conversation participants (for groups in future)
CREATE TABLE IF NOT EXISTS conversation_participants (
    id BIGSERIAL PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Role
    role VARCHAR(50) DEFAULT 'member', -- 'member', 'admin', 'moderator'

    -- Notification settings
    notifications_enabled BOOLEAN DEFAULT true,
    muted BOOLEAN DEFAULT false,
    muted_until TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP WITH TIME ZONE,

    UNIQUE(conversation_id, user_id)
);

-- Message search index (for Elasticsearch integration)
CREATE TABLE IF NOT EXISTS message_search_index (
    id BIGSERIAL PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,

    -- Indexed content
    content_vector tsvector,
    conversation_id UUID NOT NULL,

    -- Search metadata
    indexed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Blocked users (for privacy)
CREATE TABLE IF NOT EXISTS blocked_users (
    id BIGSERIAL PRIMARY KEY,
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    reason VARCHAR(255),
    blocked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT different_users CHECK (blocker_id != blocked_id),
    UNIQUE(blocker_id, blocked_id)
);

-- Indexes
DO $$
BEGIN
    -- Only create conversation indexes if expected columns exist
    IF EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_name='conversations' AND column_name='user_1_id'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_name='conversations' AND column_name='user_2_id'
    ) THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_conversations_user_1_id ON conversations(user_1_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_conversations_user_2_id ON conversations(user_2_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON conversations(last_message_at DESC)';
        EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_users_pair ON conversations (LEAST(user_1_id, user_2_id), GREATEST(user_1_id, user_2_id))';
    ELSE
        RAISE NOTICE 'Skipping conversation indexes: expected columns not present';
    END IF;

    -- Messages indexes (guarded by columns existence)
    IF EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='conversation_id'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='sender_id'
    ) THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id)';
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='receiver_id') THEN
            EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_receiver_id ON messages(receiver_id)';
        END IF;
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC)';
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='read') THEN
            EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_read ON messages(read)';
        END IF;
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at DESC)';
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='content') THEN
            EXECUTE 'CREATE INDEX IF NOT EXISTS idx_messages_content_fts ON messages USING GIN(to_tsvector(''english'', content))';
        END IF;
    ELSE
        RAISE NOTICE 'Skipping messages indexes: expected columns not present';
    END IF;

    -- Reactions/search/participants/blocked indexes (create if tables exist)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='message_reactions') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON message_reactions(message_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id ON message_reactions(user_id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='conversation_participants') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id ON conversation_participants(user_id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='message_search_index') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_message_search_index_conversation_id ON message_search_index(conversation_id)';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='blocked_users') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker_id ON blocked_users(blocker_id)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_id ON blocked_users(blocked_id)';
    END IF;
END $$;

-- Updated trigger
CREATE OR REPLACE FUNCTION update_conversations_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_name='conversations' AND column_name='updated_at'
    ) THEN
        EXECUTE 'DROP TRIGGER IF EXISTS conversations_update_timestamp ON conversations';
        EXECUTE 'CREATE TRIGGER conversations_update_timestamp BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION update_conversations_timestamp()';
    ELSE
        RAISE NOTICE 'Skipping conversations_update_timestamp trigger: updated_at column not present';
    END IF;
END $$;
