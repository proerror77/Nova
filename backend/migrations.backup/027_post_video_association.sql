-- ============================================
-- Migration: 027_post_video_association
-- Description: Enable posts to contain videos alongside images
-- Author: Nova Team
-- Date: 2025-01-24
-- ============================================

-- Design Philosophy (Linus-style):
-- 1. Posts are content "containers", images and videos are "attachments"
-- 2. No polymorphic associations - direct foreign keys only
-- 3. Zero breaking changes - all existing posts remain 'image' type
-- 4. Engagement (likes/comments) stays at post level, not individual attachments

-- ============================================
-- Step 1: Add content_type to posts table
-- ============================================

-- Add content_type column with default 'image' for backward compatibility
ALTER TABLE posts
ADD COLUMN IF NOT EXISTS content_type VARCHAR(50) NOT NULL DEFAULT 'image';

-- Add constraint to ensure valid content types
ALTER TABLE posts
DROP CONSTRAINT IF EXISTS posts_content_type_check;

ALTER TABLE posts
ADD CONSTRAINT posts_content_type_check
CHECK (content_type IN ('image', 'video', 'mixed'));

-- Backfill existing rows (idempotent)
UPDATE posts
SET content_type = 'image'
WHERE content_type IS NULL OR content_type = '';

-- Index for filtering posts by content type
CREATE INDEX IF NOT EXISTS idx_posts_content_type
ON posts(content_type)
WHERE soft_delete IS NULL;

-- Composite index for user's posts by type
CREATE INDEX IF NOT EXISTS idx_posts_user_content_type
ON posts(user_id, content_type, created_at DESC)
WHERE soft_delete IS NULL;

-- ============================================
-- Step 2: Create post_videos junction table
-- ============================================

CREATE TABLE IF NOT EXISTS post_videos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    position INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT post_videos_position_non_negative CHECK (position >= 0),
    CONSTRAINT post_videos_unique_post_video UNIQUE(post_id, video_id),
    CONSTRAINT post_videos_unique_position UNIQUE(post_id, position)
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_post_videos_post_id
ON post_videos(post_id);

CREATE INDEX IF NOT EXISTS idx_post_videos_video_id
ON post_videos(video_id);

CREATE INDEX IF NOT EXISTS idx_post_videos_post_position
ON post_videos(post_id, position);

-- ============================================
-- Step 3: Add validation trigger
-- ============================================

-- Ensure post content_type matches its attachments
CREATE OR REPLACE FUNCTION validate_post_content_type()
RETURNS TRIGGER AS $$
DECLARE
    has_images BOOLEAN;
    has_videos BOOLEAN;
    expected_type VARCHAR(50);
BEGIN
    -- Check what attachments exist for this post
    SELECT EXISTS(SELECT 1 FROM post_images WHERE post_id = NEW.post_id) INTO has_images;
    SELECT EXISTS(SELECT 1 FROM post_videos WHERE post_id = NEW.post_id) INTO has_videos;

    -- Determine expected content_type
    IF has_images AND has_videos THEN
        expected_type := 'mixed';
    ELSIF has_videos THEN
        expected_type := 'video';
    ELSIF has_images THEN
        expected_type := 'image';
    ELSE
        -- No attachments yet, allow any type
        RETURN NEW;
    END IF;

    -- Update post content_type if it doesn't match
    UPDATE posts
    SET content_type = expected_type
    WHERE id = NEW.post_id AND content_type != expected_type;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on post_videos insert/delete
DROP TRIGGER IF EXISTS trg_validate_post_content_type_videos ON post_videos;
CREATE TRIGGER trg_validate_post_content_type_videos
AFTER INSERT OR DELETE ON post_videos
FOR EACH ROW
EXECUTE FUNCTION validate_post_content_type();

-- Trigger on post_images insert/delete
DROP TRIGGER IF EXISTS trg_validate_post_content_type_images ON post_images;
CREATE TRIGGER trg_validate_post_content_type_images
AFTER INSERT OR DELETE ON post_images
FOR EACH ROW
EXECUTE FUNCTION validate_post_content_type();

-- ============================================
-- Step 4: Helper functions
-- ============================================

-- Function to get post with all media (images + videos)
CREATE OR REPLACE FUNCTION get_post_with_media(p_post_id UUID)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    caption TEXT,
    content_type VARCHAR,
    status VARCHAR,
    images JSONB,
    videos JSONB,
    like_count INT,
    comment_count INT,
    view_count INT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.user_id,
        p.caption,
        p.content_type,
        p.status,
        -- Aggregate images
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'size_variant', pi.size_variant,
                    'url', pi.url,
                    'width', pi.width,
                    'height', pi.height
                )
            )
            FROM post_images pi
            WHERE pi.post_id = p.id AND pi.status = 'completed'),
            '[]'::jsonb
        ) AS images,
        -- Aggregate videos
        COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'id', v.id,
                    'cdn_url', v.cdn_url,
                    'thumbnail_url', v.thumbnail_url,
                    'duration_seconds', v.duration_seconds,
                    'position', pv.position
                ) ORDER BY pv.position
            )
            FROM post_videos pv
            JOIN videos v ON pv.video_id = v.id
            WHERE pv.post_id = p.id),
            '[]'::jsonb
        ) AS videos,
        -- Metadata from post_metadata (Phase 1) or social_metadata (Phase 3)
        COALESCE(pm.like_count, sm.like_count, 0),
        COALESCE(pm.comment_count, sm.comment_count, 0),
        COALESCE(pm.view_count, sm.view_count, 0),
        p.created_at
    FROM posts p
    LEFT JOIN post_metadata pm ON p.id = pm.post_id
    LEFT JOIN social_metadata sm ON p.id = sm.post_id
    WHERE p.id = p_post_id AND p.soft_delete IS NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Step 5: Comments and documentation
-- ============================================

COMMENT ON COLUMN posts.content_type IS 'Type of content: image (legacy), video, or mixed (both images and videos)';
COMMENT ON TABLE post_videos IS 'Junction table linking posts to videos with positioning support';
COMMENT ON COLUMN post_videos.position IS 'Display order for multiple videos in a post (0-indexed)';
COMMENT ON FUNCTION get_post_with_media(UUID) IS 'Retrieve post with all images and videos in a single query';

-- ============================================
-- Migration Complete
-- ============================================
-- Backward compatibility: ✅ All existing posts remain 'image' type
-- Data integrity: ✅ Triggers auto-update content_type based on attachments
-- Performance: ✅ Indexes on content_type and post_videos relationships
-- Extensibility: ✅ Position field supports multiple videos per post
-- ============================================
