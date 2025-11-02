-- ============================================
-- Migration: 065_merge_post_metadata_tables
-- Description: Merge post_metadata and social_metadata into posts table
--
-- Problem: Two separate tables (post_metadata and social_metadata) both maintain
--          the same counters (like_count, comment_count), violating single source of truth.
--          This causes data inconsistency and requires unnecessary JOINs.
--
-- Solution: Move all counters into posts table, eliminate redundant tables.
--           Keep social_metadata temporarily for backward compatibility, but mark as deprecated.
--
-- Author: Nova Team (Linus-style architecture review)
-- Date: 2025-11-02
-- ============================================

-- Step 1: Add counter columns to posts table
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS like_count INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS comment_count INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS view_count INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS share_count INT NOT NULL DEFAULT 0;

-- Step 2: Add constraints to ensure counts are non-negative
ALTER TABLE posts
    ADD CONSTRAINT IF NOT EXISTS posts_counts_non_negative
        CHECK (like_count >= 0 AND comment_count >= 0 AND view_count >= 0 AND share_count >= 0);

-- Step 3: Migrate data from post_metadata to posts
UPDATE posts p
SET
    like_count = COALESCE(pm.like_count, 0),
    comment_count = COALESCE(pm.comment_count, 0),
    view_count = COALESCE(pm.view_count, 0)
FROM post_metadata pm
WHERE p.id = pm.post_id;

-- Step 4: Migrate data from social_metadata to posts
UPDATE posts p
SET
    like_count = COALESCE(sm.like_count, like_count),
    comment_count = COALESCE(sm.comment_count, comment_count),
    view_count = COALESCE(sm.view_count, view_count),
    share_count = COALESCE(sm.share_count, 0)
FROM social_metadata sm
WHERE p.id = sm.post_id;

-- Step 5: Drop old triggers that maintained post_metadata
DROP TRIGGER IF EXISTS trg_create_post_metadata ON posts;
DROP FUNCTION IF EXISTS create_post_metadata();

-- Step 6: Drop old triggers that maintained social_metadata counters
DROP TRIGGER IF EXISTS trg_update_like_count ON likes;
DROP TRIGGER IF EXISTS trg_update_comment_count ON comments;
DROP FUNCTION IF EXISTS update_post_like_count();
DROP FUNCTION IF EXISTS update_post_comment_count();

-- Step 7: Create new triggers to maintain counters from posts table
CREATE OR REPLACE FUNCTION update_post_like_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE posts SET like_count = like_count - 1 WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_post_like_count
AFTER INSERT OR DELETE ON likes
FOR EACH ROW
EXECUTE FUNCTION update_post_like_count();

-- Comment count trigger
CREATE OR REPLACE FUNCTION update_post_comment_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET comment_count = comment_count + 1
        WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE posts SET comment_count = comment_count - 1
        WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_post_comment_count
AFTER INSERT OR DELETE ON comments
FOR EACH ROW
EXECUTE FUNCTION update_post_comment_count();

-- Step 8: Create view for backward compatibility (if code still uses post_metadata)
CREATE OR REPLACE VIEW post_metadata AS
SELECT
    id as post_id,
    like_count,
    comment_count,
    view_count,
    updated_at
FROM posts;

-- Step 9: Add indexes on counter columns for sorting by engagement
CREATE INDEX IF NOT EXISTS idx_posts_like_count ON posts(like_count DESC);
CREATE INDEX IF NOT EXISTS idx_posts_comment_count ON posts(comment_count DESC);
CREATE INDEX IF NOT EXISTS idx_posts_view_count ON posts(view_count DESC);

-- Note: The original post_metadata and social_metadata tables are retained
--       for data integrity but should be considered deprecated.
--       Future migrations will drop these tables once all code is updated.
