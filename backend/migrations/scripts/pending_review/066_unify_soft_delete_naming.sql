-- ============================================
-- Migration: 066_unify_soft_delete_naming
-- Description: Unify inconsistent soft delete column naming
--
-- Problem: Inconsistent naming across tables:
--          - posts.soft_delete (TIMESTAMP)
--          - comments.soft_delete (TIMESTAMP)
--          - messages.deleted_at (TIMESTAMP) <- different name!
--          - conversations has no soft delete column
--
--          This inconsistency causes:
--          1. Query errors (developers use wrong column names)
--          2. Difficult maintenance (need conditional queries)
--          3. Unclear semantics (is it a boolean flag or timestamp?)
--
-- Solution: Standardize all tables to use deleted_at column name.
--           Uses TIMESTAMP to track deletion time (better for auditing).
--
-- Author: Nova Team (Linus-style architecture review)
-- Date: 2025-11-02
-- ============================================

-- Step 1: Rename soft_delete to deleted_at in posts table
ALTER TABLE posts
    RENAME COLUMN soft_delete TO deleted_at;

-- Update the constraint name for clarity
ALTER TABLE posts
    DROP CONSTRAINT IF EXISTS soft_delete_logic,
    ADD CONSTRAINT deleted_at_logic
        CHECK (deleted_at IS NULL OR deleted_at <= NOW());

-- Update indexes to reflect new name
DROP INDEX IF EXISTS idx_posts_soft_delete;
CREATE INDEX idx_posts_deleted_at ON posts(deleted_at)
    WHERE deleted_at IS NULL;

-- Step 2: Rename soft_delete to deleted_at in comments table
ALTER TABLE comments
    RENAME COLUMN soft_delete TO deleted_at;

-- Update composite index
DROP INDEX IF EXISTS idx_comments_post_deleted;
CREATE INDEX idx_comments_post_deleted ON comments(post_id, deleted_at)
    WHERE deleted_at IS NULL;

-- Step 3: Add deleted_at column to conversations table
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

-- Update composite index for conversations
CREATE INDEX IF NOT EXISTS idx_conversations_deleted_at ON conversations(deleted_at)
    WHERE deleted_at IS NULL;

-- Step 4: Verify messages.deleted_at already exists (it does from 018_messaging_schema)
-- This is just to document that messages already has the correct name

-- Step 5: Add helper function to get active records (not deleted)
CREATE OR REPLACE FUNCTION is_active_post(post_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM posts WHERE id = post_id AND deleted_at IS NULL);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_active_comment(comment_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM comments WHERE id = comment_id AND deleted_at IS NULL);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_active_message(message_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM messages WHERE id = message_id AND deleted_at IS NULL);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_active_conversation(conversation_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM conversations WHERE id = conversation_id AND deleted_at IS NULL);
END;
$$ LANGUAGE plpgsql;

-- Step 6: Document migration in system metadata
-- This helps track schema evolution
COMMENT ON COLUMN posts.deleted_at IS
    'Timestamp when post was soft-deleted (NULL = active). Replaces soft_delete.';
COMMENT ON COLUMN comments.deleted_at IS
    'Timestamp when comment was soft-deleted (NULL = active). Replaces soft_delete.';
COMMENT ON COLUMN messages.deleted_at IS
    'Timestamp when message was soft-deleted (NULL = active).';
COMMENT ON COLUMN conversations.deleted_at IS
    'Timestamp when conversation was soft-deleted (NULL = active).';

-- Step 7: Update materialized view for deleted posts (if it exists)
CREATE OR REPLACE VIEW active_posts AS
SELECT * FROM posts WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW active_comments AS
SELECT * FROM comments WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW active_messages AS
SELECT * FROM messages WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW active_conversations AS
SELECT * FROM conversations WHERE deleted_at IS NULL;

-- Step 8: Create view mapping old name to new for any legacy queries
CREATE OR REPLACE VIEW posts_with_legacy_soft_delete AS
SELECT
    id,
    user_id,
    caption,
    image_key,
    image_sizes,
    status,
    created_at,
    updated_at,
    deleted_at AS soft_delete,
    like_count,
    comment_count,
    view_count,
    share_count
FROM posts;

CREATE OR REPLACE VIEW comments_with_legacy_soft_delete AS
SELECT
    id,
    post_id,
    user_id,
    content,
    parent_comment_id,
    created_at,
    updated_at,
    deleted_at AS soft_delete
FROM comments;
