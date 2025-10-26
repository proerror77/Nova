-- Add missing fields for complete group conversation support
-- Migration: 0014_add_group_conversation_fields

-- Add avatar_url to conversations table for group avatars
ALTER TABLE conversations ADD COLUMN avatar_url TEXT;
COMMENT ON COLUMN conversations.avatar_url IS 'Avatar URL for group conversations';

-- Add admin_key_version to conversations table for SearchEnabled privacy mode
-- This tracks which version of the admin key was used for encryption in SearchEnabled mode
ALTER TABLE conversations ADD COLUMN admin_key_version INT DEFAULT 1;
COMMENT ON COLUMN conversations.admin_key_version IS 'Version of admin key used for SearchEnabled mode encryption';

-- Create index for better group conversation queries
CREATE INDEX idx_conversations_kind_created_at ON conversations(kind, created_at DESC)
WHERE kind = 'group';
COMMENT ON INDEX idx_conversations_kind_created_at IS 'Index for efficiently querying group conversations';

-- Add index on conversation_members for role-based queries
CREATE INDEX idx_conversation_members_role ON conversation_members(conversation_id, role)
WHERE role IN ('admin', 'owner');
COMMENT ON INDEX idx_conversation_members_role IS 'Index for finding admin/owner members';
