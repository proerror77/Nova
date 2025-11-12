-- Performance Optimization Migration - Priority 0 (Critical)
-- This migration addresses the most critical performance bottlenecks
-- Estimated performance improvement: 5-10x for messaging operations

-- ============================================
-- 2. Denormalize conversation fields
-- ============================================
-- This eliminates subqueries in get_conversation_db

-- Add denormalized fields (if not exists)
ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS member_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_message_id UUID,
ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ;

-- Backfill existing data
UPDATE conversations c
SET
    member_count = COALESCE((SELECT COUNT(*)::int FROM conversation_members WHERE conversation_id = c.id), 0),
    last_message_id = (SELECT id FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1),
    last_message_at = (SELECT created_at FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1);

-- Trigger to maintain member_count
CREATE OR REPLACE FUNCTION update_conversation_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE conversations
        SET member_count = member_count + 1
        WHERE id = NEW.conversation_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE conversations
        SET member_count = GREATEST(member_count - 1, 0)
        WHERE id = OLD.conversation_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_member_count_on_add ON conversation_members;
DROP TRIGGER IF EXISTS update_member_count_on_remove ON conversation_members;

CREATE TRIGGER update_member_count_on_add
AFTER INSERT ON conversation_members
FOR EACH ROW EXECUTE FUNCTION update_conversation_member_count();

CREATE TRIGGER update_member_count_on_remove
AFTER DELETE ON conversation_members
FOR EACH ROW EXECUTE FUNCTION update_conversation_member_count();

-- Trigger to maintain last_message_id and last_message_at
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET
        last_message_id = NEW.id,
        last_message_at = NEW.created_at,
        updated_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_last_message_on_insert ON messages;

CREATE TRIGGER update_last_message_on_insert
AFTER INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();

-- ============================================
-- 4. Add missing columns for conversation archiving
-- ============================================

-- Add is_archived column for conversation archiving feature
ALTER TABLE conversation_members
ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

-- ============================================
-- 5. Add missing composite indexes
-- ============================================

-- Conversation list query optimization
CREATE INDEX IF NOT EXISTS idx_conversation_members_user_conversation
ON conversation_members(user_id, conversation_id)
INCLUDE (is_archived, last_read_at);

-- Message pagination optimization (cursor-based)
CREATE INDEX IF NOT EXISTS idx_messages_conversation_ts_id
ON messages(conversation_id, created_at DESC, id DESC)
WHERE deleted_at IS NULL;

-- Post queries with status filter
CREATE INDEX IF NOT EXISTS idx_posts_user_status_created
ON posts(user_id, status, created_at DESC)
WHERE soft_delete IS NULL;

-- Post metadata frequently joined with posts
CREATE INDEX IF NOT EXISTS idx_post_metadata_post_id
ON post_metadata(post_id)
INCLUDE (like_count, comment_count, view_count);

-- Post images by post_id and variant (for get_post_with_images optimization)
CREATE INDEX IF NOT EXISTS idx_post_images_post_variant
ON post_images(post_id, size_variant, status)
WHERE status = 'completed';

-- ============================================
-- 5. Add constraints for data integrity
-- ============================================

-- Ensure member_count is always >= 0
ALTER TABLE conversations
ADD CONSTRAINT chk_member_count_positive
CHECK (member_count >= 0);

-- ============================================
-- 6. Create indexes for message reactions and attachments
-- ============================================
-- These optimize the message_history_with_details query

CREATE INDEX IF NOT EXISTS idx_message_reactions_message_emoji
ON message_reactions(message_id, emoji)
INCLUDE (user_id);

CREATE INDEX IF NOT EXISTS idx_message_attachments_message
ON message_attachments(message_id)
INCLUDE (file_name, file_type, file_size, s3_key);

-- ============================================
-- Analysis and Statistics
-- ============================================

-- Update statistics for query planner
ANALYZE messages;
ANALYZE conversations;
ANALYZE conversation_members;
ANALYZE posts;
ANALYZE post_metadata;
ANALYZE post_images;
ANALYZE message_reactions;
ANALYZE message_attachments;

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'Performance optimization migration (P0) completed successfully';
    RAISE NOTICE 'Expected improvements:';
    RAISE NOTICE '  - Conversation queries: 3-5x faster (eliminated subqueries)';
    RAISE NOTICE '  - Message history: 2-3x faster (optimized indexes)';
END $$;
