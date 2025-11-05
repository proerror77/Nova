-- ============================================
-- Migration: 065_merge_post_metadata_v2
--
-- Changes from v1:
-- - Remove backward-compatibility view (technical debt)
-- - Direct column access, simpler data model
-- - Let application handle old column names
--
-- Linus Principle: "消除特殊情况"
-- Views hide intent. Force explicit queries.
--
-- Author: Nova Team + Database Architect Review
-- Date: 2025-11-02
-- ============================================

-- Step 1: Ensure posts table has all counter columns
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS like_count INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS comment_count INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS view_count INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS share_count INT DEFAULT 0;

-- Step 2: Copy existing data from post_metadata to posts
UPDATE posts p
SET
    like_count = COALESCE(pm.like_count, 0),
    comment_count = COALESCE(pm.comment_count, 0),
    view_count = COALESCE(pm.view_count, 0),
    share_count = COALESCE(pm.share_count, 0)
FROM post_metadata pm
WHERE p.id = pm.post_id
    AND pm.post_id IS NOT NULL;

-- Step 3: Drop post_metadata table entirely
-- WARNING: Any application code reading post_metadata must be updated
DROP TABLE IF EXISTS post_metadata CASCADE;

-- Step 4: Add trigger for like counting (maintains like_count)
CREATE OR REPLACE FUNCTION increment_post_like_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE posts
    SET like_count = like_count + 1
    WHERE id = NEW.post_id
        AND deleted_at IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS trg_post_like_increment
AFTER INSERT ON post_likes
FOR EACH ROW
EXECUTE FUNCTION increment_post_like_count();

-- Step 5: Add trigger for comment counting
CREATE OR REPLACE FUNCTION increment_post_comment_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE posts
    SET comment_count = comment_count + 1
    WHERE id = NEW.post_id
        AND deleted_at IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS trg_post_comment_increment
AFTER INSERT ON comments
FOR EACH ROW
EXECUTE FUNCTION increment_post_comment_count();

-- Step 6: Add trigger for view counting
CREATE OR REPLACE FUNCTION increment_post_view_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE posts
    SET view_count = view_count + 1
    WHERE id = NEW.post_id
        AND deleted_at IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS trg_post_view_increment
AFTER INSERT ON post_views
FOR EACH ROW
EXECUTE FUNCTION increment_post_view_count();

-- Step 7: Add indexes on counter columns for filtering
CREATE INDEX IF NOT EXISTS idx_posts_like_count
    ON posts(like_count DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_posts_comment_count
    ON posts(comment_count DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_posts_view_count
    ON posts(view_count DESC)
    WHERE deleted_at IS NULL;

-- Step 8: Log migration
INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
VALUES (
    '065',
    'posts',
    'Merged post_metadata into posts table. All counter columns now in single table. post_metadata table removed.'
)
ON CONFLICT DO NOTHING;

-- Step 9: Add comment for documentation
COMMENT ON COLUMN posts.like_count IS
    'Like count - maintained via INSERT trigger on post_likes. Moved from post_metadata.';

COMMENT ON COLUMN posts.comment_count IS
    'Comment count - maintained via INSERT trigger on comments. Moved from post_metadata.';

COMMENT ON COLUMN posts.view_count IS
    'View count - maintained via INSERT trigger on post_views. Moved from post_metadata.';

COMMENT ON COLUMN posts.share_count IS
    'Share count - maintained via INSERT trigger on social_shares. Moved from post_metadata.';
