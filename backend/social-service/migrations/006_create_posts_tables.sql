-- ============================================================================
-- Migration: 006_create_posts_tables
-- Description: Create posts and media management tables for social-service
-- Author: Nova Team
-- Date: 2025-12-04
-- Note: Adapted from global 003_posts_schema.sql, removed cross-service FK to users
-- ============================================================================

-- ============================================
-- Table: posts
-- Description: User-created image posts
-- ============================================
CREATE TABLE IF NOT EXISTS posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,  -- Reference to user in identity-service (no FK constraint)
    caption TEXT,
    image_key VARCHAR(512) NOT NULL,
    image_sizes JSONB,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    soft_delete TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT posts_caption_length CHECK (LENGTH(caption) <= 2200),
    CONSTRAINT posts_image_key_not_empty CHECK (LENGTH(image_key) > 0),
    CONSTRAINT posts_status_valid CHECK (status IN ('pending', 'processing', 'published', 'failed')),
    CONSTRAINT posts_soft_delete_logic CHECK (soft_delete IS NULL OR soft_delete <= NOW())
);

-- Indexes for posts table
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status);
CREATE INDEX IF NOT EXISTS idx_posts_soft_delete ON posts(soft_delete) WHERE soft_delete IS NULL;

-- Composite index for common query: user's posts ordered by recent
CREATE INDEX IF NOT EXISTS idx_posts_user_created ON posts(user_id, created_at DESC) WHERE soft_delete IS NULL;

-- Index for feed queries
CREATE INDEX IF NOT EXISTS idx_posts_feed ON posts(created_at DESC) WHERE status = 'published' AND soft_delete IS NULL;

COMMENT ON TABLE posts IS 'User-created image posts with captions and metadata';
COMMENT ON COLUMN posts.user_id IS 'Reference to user in identity-service (validated at application layer)';
COMMENT ON COLUMN posts.image_key IS 'CDN/S3 object key for the uploaded image';
COMMENT ON COLUMN posts.image_sizes IS 'JSON object containing URLs for different image sizes';
COMMENT ON COLUMN posts.status IS 'Processing status: pending, processing, published, or failed';
COMMENT ON COLUMN posts.soft_delete IS 'Soft delete timestamp for GDPR compliance';

-- ============================================
-- Table: post_images
-- Description: Transcoded image variants tracking (thumbnail, medium, original)
-- ============================================
CREATE TABLE IF NOT EXISTS post_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    cdn_key VARCHAR(512) NOT NULL,
    cdn_url VARCHAR(1024),
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    size_variant VARCHAR(50) NOT NULL,
    file_size INT,
    width INT,
    height INT,
    content_type VARCHAR(100),
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT post_images_size_variant_valid CHECK (size_variant IN ('original', 'large', 'medium', 'thumbnail')),
    CONSTRAINT post_images_status_valid CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    CONSTRAINT post_images_cdn_key_not_empty CHECK (LENGTH(cdn_key) > 0)
);

-- Indexes for post_images table
CREATE INDEX IF NOT EXISTS idx_post_images_post_id ON post_images(post_id);
CREATE INDEX IF NOT EXISTS idx_post_images_status ON post_images(status);
CREATE INDEX IF NOT EXISTS idx_post_images_size_variant ON post_images(size_variant);

-- Composite index for checking if all variants are ready
CREATE INDEX IF NOT EXISTS idx_post_images_post_status ON post_images(post_id, status);

COMMENT ON TABLE post_images IS 'Transcoded image variants (thumbnail 150x150, medium 600x600, large 1200x1200, original)';
COMMENT ON COLUMN post_images.cdn_key IS 'CDN object key for this specific variant';
COMMENT ON COLUMN post_images.cdn_url IS 'Full CDN URL for this image variant';
COMMENT ON COLUMN post_images.size_variant IS 'Which variant: thumbnail, medium, large, or original';
COMMENT ON COLUMN post_images.status IS 'Processing status for this variant';

-- ============================================
-- Table: post_metadata
-- Description: Post statistics and engagement metrics (denormalized for reads)
-- ============================================
CREATE TABLE IF NOT EXISTS post_metadata (
    post_id UUID PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
    like_count BIGINT NOT NULL DEFAULT 0,
    comment_count BIGINT NOT NULL DEFAULT 0,
    share_count BIGINT NOT NULL DEFAULT 0,
    view_count BIGINT NOT NULL DEFAULT 0,
    save_count BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT post_metadata_counts_non_negative CHECK (
        like_count >= 0 AND
        comment_count >= 0 AND
        share_count >= 0 AND
        view_count >= 0 AND
        save_count >= 0
    )
);

-- Index for sorting posts by engagement
CREATE INDEX IF NOT EXISTS idx_post_metadata_like_count ON post_metadata(like_count DESC);
CREATE INDEX IF NOT EXISTS idx_post_metadata_view_count ON post_metadata(view_count DESC);
CREATE INDEX IF NOT EXISTS idx_post_metadata_updated_at ON post_metadata(updated_at DESC);

COMMENT ON TABLE post_metadata IS 'Denormalized engagement metrics for posts (synced with post_counters via triggers)';

-- ============================================
-- Table: upload_sessions
-- Description: Track ongoing file uploads with presigned URLs
-- ============================================
CREATE TABLE IF NOT EXISTS upload_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    upload_token VARCHAR(512) NOT NULL UNIQUE,
    presigned_url TEXT,
    cdn_key VARCHAR(512),
    file_hash VARCHAR(128),
    file_size BIGINT,
    content_type VARCHAR(100),
    expires_at TIMESTAMPTZ NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT upload_sessions_expires_at_future CHECK (expires_at > created_at),
    CONSTRAINT upload_sessions_upload_token_not_empty CHECK (LENGTH(upload_token) > 0)
);

-- Indexes for upload_sessions table
CREATE INDEX IF NOT EXISTS idx_upload_sessions_post_id ON upload_sessions(post_id) WHERE post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_upload_sessions_user_id ON upload_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_upload_sessions_upload_token ON upload_sessions(upload_token);
CREATE INDEX IF NOT EXISTS idx_upload_sessions_expires_at ON upload_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_upload_sessions_pending ON upload_sessions(is_completed) WHERE is_completed = FALSE;

COMMENT ON TABLE upload_sessions IS 'Track ongoing uploads with time-limited presigned URLs';
COMMENT ON COLUMN upload_sessions.presigned_url IS 'CDN presigned URL for direct upload';
COMMENT ON COLUMN upload_sessions.cdn_key IS 'Target CDN key where file will be stored';

-- ============================================
-- Table: saved_posts
-- Description: User bookmarked/saved posts
-- ============================================
CREATE TABLE IF NOT EXISTS saved_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT unique_saved_post_per_user UNIQUE (post_id, user_id)
);

-- Indexes for saved_posts
CREATE INDEX IF NOT EXISTS idx_saved_posts_user_id ON saved_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_posts_post_id ON saved_posts(post_id);
CREATE INDEX IF NOT EXISTS idx_saved_posts_created_at ON saved_posts(created_at DESC);

COMMENT ON TABLE saved_posts IS 'User bookmarked/saved posts';

-- ============================================
-- TRIGGERS
-- ============================================

-- Trigger function for updating updated_at timestamp
CREATE OR REPLACE FUNCTION update_posts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Update posts.updated_at on modification
DROP TRIGGER IF EXISTS trigger_update_posts_updated_at ON posts;
CREATE TRIGGER trigger_update_posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION update_posts_updated_at();

-- Trigger: Update post_images.updated_at on modification
DROP TRIGGER IF EXISTS trigger_update_post_images_updated_at ON post_images;
CREATE TRIGGER trigger_update_post_images_updated_at
    BEFORE UPDATE ON post_images
    FOR EACH ROW
    EXECUTE FUNCTION update_posts_updated_at();

-- Trigger: Update post_metadata.updated_at on modification
DROP TRIGGER IF EXISTS trigger_update_post_metadata_updated_at ON post_metadata;
CREATE TRIGGER trigger_update_post_metadata_updated_at
    BEFORE UPDATE ON post_metadata
    FOR EACH ROW
    EXECUTE FUNCTION update_posts_updated_at();

-- ============================================
-- Trigger: Create post_metadata entry on post creation
-- ============================================
CREATE OR REPLACE FUNCTION create_post_metadata()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO post_metadata (post_id, like_count, comment_count, share_count, view_count, save_count)
    VALUES (NEW.id, 0, 0, 0, 0, 0)
    ON CONFLICT (post_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_metadata_on_post_insert ON posts;
CREATE TRIGGER trigger_create_metadata_on_post_insert
    AFTER INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION create_post_metadata();

-- ============================================
-- Trigger: Sync post_counters to post_metadata
-- ============================================
CREATE OR REPLACE FUNCTION sync_post_counters_to_metadata()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO post_metadata (post_id, like_count, comment_count, share_count, updated_at)
    VALUES (NEW.post_id, NEW.like_count, NEW.comment_count, NEW.share_count, NOW())
    ON CONFLICT (post_id) DO UPDATE SET
        like_count = EXCLUDED.like_count,
        comment_count = EXCLUDED.comment_count,
        share_count = EXCLUDED.share_count,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_sync_counters_to_metadata ON post_counters;
CREATE TRIGGER trigger_sync_counters_to_metadata
    AFTER INSERT OR UPDATE ON post_counters
    FOR EACH ROW
    EXECUTE FUNCTION sync_post_counters_to_metadata();

-- ============================================
-- Trigger: Update save_count on saved_posts changes
-- ============================================
CREATE OR REPLACE FUNCTION increment_save_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE post_metadata
    SET save_count = save_count + 1,
        updated_at = NOW()
    WHERE post_id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION decrement_save_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE post_metadata
    SET save_count = GREATEST(save_count - 1, 0),
        updated_at = NOW()
    WHERE post_id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_increment_save_count ON saved_posts;
CREATE TRIGGER trigger_increment_save_count
    AFTER INSERT ON saved_posts
    FOR EACH ROW
    EXECUTE FUNCTION increment_save_count();

DROP TRIGGER IF EXISTS trigger_decrement_save_count ON saved_posts;
CREATE TRIGGER trigger_decrement_save_count
    AFTER DELETE ON saved_posts
    FOR EACH ROW
    EXECUTE FUNCTION decrement_save_count();

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function: Get post with all image URLs
CREATE OR REPLACE FUNCTION get_post_with_images(p_post_id UUID)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    caption TEXT,
    status VARCHAR,
    thumbnail_url VARCHAR,
    medium_url VARCHAR,
    large_url VARCHAR,
    original_url VARCHAR,
    like_count BIGINT,
    comment_count BIGINT,
    share_count BIGINT,
    view_count BIGINT,
    save_count BIGINT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.user_id,
        p.caption,
        p.status,
        (SELECT pi.cdn_url FROM post_images pi WHERE pi.post_id = p.id AND pi.size_variant = 'thumbnail' AND pi.status = 'completed' LIMIT 1),
        (SELECT pi.cdn_url FROM post_images pi WHERE pi.post_id = p.id AND pi.size_variant = 'medium' AND pi.status = 'completed' LIMIT 1),
        (SELECT pi.cdn_url FROM post_images pi WHERE pi.post_id = p.id AND pi.size_variant = 'large' AND pi.status = 'completed' LIMIT 1),
        (SELECT pi.cdn_url FROM post_images pi WHERE pi.post_id = p.id AND pi.size_variant = 'original' AND pi.status = 'completed' LIMIT 1),
        pm.like_count,
        pm.comment_count,
        pm.share_count,
        pm.view_count,
        pm.save_count,
        p.created_at
    FROM posts p
    LEFT JOIN post_metadata pm ON p.id = pm.post_id
    WHERE p.id = p_post_id AND p.soft_delete IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Function: Get user feed (posts from followed users)
CREATE OR REPLACE FUNCTION get_user_feed(
    p_user_id UUID,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    caption TEXT,
    image_sizes JSONB,
    like_count BIGINT,
    comment_count BIGINT,
    view_count BIGINT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.user_id,
        p.caption,
        p.image_sizes,
        COALESCE(pm.like_count, 0),
        COALESCE(pm.comment_count, 0),
        COALESCE(pm.view_count, 0),
        p.created_at
    FROM posts p
    LEFT JOIN post_metadata pm ON p.id = pm.post_id
    WHERE p.status = 'published'
      AND p.soft_delete IS NULL
    ORDER BY p.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- Function: Cleanup expired upload sessions
CREATE OR REPLACE FUNCTION cleanup_expired_uploads()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete expired and incomplete upload sessions
    DELETE FROM upload_sessions
    WHERE expires_at < NOW() AND is_completed = FALSE;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    -- Also delete orphaned posts (draft posts with no images after 24h)
    DELETE FROM posts
    WHERE status = 'pending'
      AND created_at < NOW() - INTERVAL '24 hours'
      AND NOT EXISTS (SELECT 1 FROM post_images WHERE post_id = posts.id);

    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_post_with_images(UUID) IS 'Retrieve post with all image URLs and metadata';
COMMENT ON FUNCTION get_user_feed(UUID, INT, INT) IS 'Get paginated feed of published posts';
COMMENT ON FUNCTION cleanup_expired_uploads() IS 'Delete expired upload sessions and orphaned draft posts';

-- ============================================
-- Verification: List created tables
-- ============================================
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('posts', 'post_images', 'post_metadata', 'upload_sessions', 'saved_posts');
