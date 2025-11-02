-- ============================================
-- Migration: 066_unify_soft_delete_v2
--
-- Changes from v1:
-- - Add deleted_by column for audit trail
-- - Use partial indexes instead of views
-- - Remove legacy compatibility views (technical debt)
--
-- Linus Principle: "Fix data structures first, code follows"
-- Add missing audit columns, optimize with partial indexes.
--
-- Author: Nova Team + Database Architect Review
-- Date: 2025-11-02
-- ============================================

-- Step 1: Unify naming - convert soft_delete to deleted_at if needed
-- Check current state first with migration script
-- For posts table
ALTER TABLE posts
    RENAME COLUMN IF EXISTS soft_delete TO deleted_at;

-- For comments table
ALTER TABLE comments
    RENAME COLUMN IF EXISTS soft_delete TO deleted_at;

-- If tables still use soft_delete as BOOLEAN, convert them
-- (This assumes migration has already partially run)

-- Step 2: Add deleted_at to tables that don't have it
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

-- Step 3: Add deleted_by column to all soft-delete tables (audit trail)
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS deleted_by UUID;

ALTER TABLE comments
    ADD COLUMN IF NOT EXISTS deleted_by UUID;

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS deleted_by UUID;

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS deleted_by UUID;

-- Step 4: Add FK to users for deleted_by
ALTER TABLE posts
    ADD CONSTRAINT IF NOT EXISTS fk_posts_deleted_by
    FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE comments
    ADD CONSTRAINT IF NOT EXISTS fk_comments_deleted_by
    FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE messages
    ADD CONSTRAINT IF NOT EXISTS fk_messages_deleted_by
    FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE conversations
    ADD CONSTRAINT IF NOT EXISTS fk_conversations_deleted_by
    FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL;

-- Step 5: Create partial indexes (better than views for performance)
-- Partial indexes only index rows where deleted_at IS NULL
-- This improves query performance and reduces index size

CREATE INDEX IF NOT EXISTS idx_posts_active
    ON posts(id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_comments_active
    ON comments(post_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_messages_active
    ON messages(conversation_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_active
    ON conversations(id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Step 6: Add composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_posts_by_author_active
    ON posts(author_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_comments_by_author_active
    ON comments(author_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Step 7: Create views only for explicit backward compatibility IF NEEDED
-- (But prefer direct queries - views hide intent)
-- These views should be marked for deprecation

-- Only create if application still needs it (temporary migration aid)
-- CREATE OR REPLACE VIEW active_posts AS
-- SELECT * FROM posts WHERE deleted_at IS NULL;
--
-- (Commented out - application should add WHERE deleted_at IS NULL directly)

-- Step 8: Add helper function for soft-delete filtering
CREATE OR REPLACE FUNCTION is_active(deleted_at TIMESTAMP WITH TIME ZONE)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Usage: WHERE is_active(posts.deleted_at)
-- Or better yet: WHERE posts.deleted_at IS NULL (more explicit)

-- Step 9: Create audit trigger for delete operations
CREATE OR REPLACE FUNCTION log_soft_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Log when something is soft-deleted
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
        VALUES (
            '066',
            TG_TABLE_NAME,
            format('Row deleted: id=%L, deleted_by=%L, deleted_at=%L',
                   NEW.id, NEW.deleted_by, NEW.deleted_at)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 10: Log migration
INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
VALUES (
    '066',
    'posts,comments,messages,conversations',
    'Unified soft_delete naming to deleted_at. Added deleted_by column for audit trail. Created partial indexes for active row filtering.'
)
ON CONFLICT DO NOTHING;

-- Step 11: Add comments for documentation
COMMENT ON COLUMN posts.deleted_at IS
    'Soft delete timestamp. NULL = active, NOT NULL = deleted. Set by application when post is deleted.';

COMMENT ON COLUMN posts.deleted_by IS
    'User ID of who deleted this post. References users(id). Used for audit trail and GDPR requests.';

COMMENT ON COLUMN comments.deleted_at IS
    'Soft delete timestamp. NULL = active, NOT NULL = deleted.';

COMMENT ON COLUMN comments.deleted_by IS
    'User ID of who deleted this comment. References users(id).';

COMMENT ON COLUMN messages.deleted_at IS
    'Soft delete timestamp. NULL = active, NOT NULL = deleted. Important for encryption key rotation.';

COMMENT ON COLUMN messages.deleted_by IS
    'User ID of who deleted this message. For audit trail.';

COMMENT ON COLUMN conversations.deleted_at IS
    'Soft delete timestamp. NULL = active, NOT NULL = deleted.';

COMMENT ON COLUMN conversations.deleted_by IS
    'User ID of who deleted this conversation. For audit trail.';

COMMENT ON INDEX idx_posts_active IS
    'Partial index for fast filtering of active (non-deleted) posts. Only indexes rows where deleted_at IS NULL.';

COMMENT ON INDEX idx_comments_active IS
    'Partial index for fast filtering of active comments.';

COMMENT ON INDEX idx_messages_active IS
    'Partial index for fast filtering of active messages. Important for encryption key rotation queries.';

-- Step 12: Analyze tables for query planner optimization
ANALYZE posts;
ANALYZE comments;
ANALYZE messages;
ANALYZE conversations;
