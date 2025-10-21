-- ============================================
-- Migration: 003_posts_schema
-- Description: Create posts and post management tables
-- Author: Nova Team
-- Date: 2025-01-16
-- ============================================

-- Enable JSON extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- Table: posts
-- Description: User-created image posts
-- ============================================
CREATE TABLE IF NOT EXISTS posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    caption TEXT,
    image_key VARCHAR(512) NOT NULL,
    image_sizes JSONB,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    soft_delete TIMESTAMP WITH TIME ZONE,

    -- Constraints
    CONSTRAINT caption_length CHECK (LENGTH(caption) <= 2200),
    CONSTRAINT image_key_not_empty CHECK (LENGTH(image_key) > 0),
    CONSTRAINT status_valid CHECK (status IN ('pending', 'processing', 'published', 'failed')),
    CONSTRAINT soft_delete_logic CHECK (soft_delete IS NULL OR soft_delete <= NOW())
);

-- Indexes for posts table
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status);
CREATE INDEX IF NOT EXISTS idx_posts_soft_delete ON posts(soft_delete) WHERE soft_delete IS NULL;

-- Composite index for common query: user's posts ordered by recent
CREATE INDEX IF NOT EXISTS idx_posts_user_created ON posts(user_id, created_at DESC) WHERE soft_delete IS NULL;

-- Index for feed queries (Phase 3)
CREATE INDEX IF NOT EXISTS idx_posts_created_published ON posts(created_at DESC) WHERE status = 'published' AND soft_delete IS NULL;

-- ============================================
-- Table: post_images
-- Description: Transcoded image variants tracking
-- ============================================
CREATE TABLE IF NOT EXISTS post_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    s3_key VARCHAR(512) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    size_variant VARCHAR(50) NOT NULL,
    file_size INT,
    width INT,
    height INT,
    url VARCHAR(1024),
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT size_variant_valid CHECK (size_variant IN ('original', 'medium', 'thumbnail')),
    CONSTRAINT status_valid CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    CONSTRAINT s3_key_not_empty CHECK (LENGTH(s3_key) > 0)
);

-- Indexes for post_images table
CREATE INDEX IF NOT EXISTS idx_post_images_post_id ON post_images(post_id);
CREATE INDEX IF NOT EXISTS idx_post_images_status ON post_images(status);
CREATE INDEX IF NOT EXISTS idx_post_images_size_variant ON post_images(size_variant);

-- Composite index for checking if all variants are ready
CREATE INDEX IF NOT EXISTS idx_post_images_post_status ON post_images(post_id, status);

-- ============================================
-- Table: post_metadata
-- Description: Post statistics and engagement metrics
-- ============================================
CREATE TABLE IF NOT EXISTS post_metadata (
    post_id UUID PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
    like_count INT NOT NULL DEFAULT 0,
    comment_count INT NOT NULL DEFAULT 0,
    view_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT counts_non_negative CHECK (like_count >= 0 AND comment_count >= 0 AND view_count >= 0)
);

-- Index for sorting posts by engagement
CREATE INDEX IF NOT EXISTS idx_post_metadata_like_count ON post_metadata(like_count DESC);
CREATE INDEX IF NOT EXISTS idx_post_metadata_updated_at ON post_metadata(updated_at DESC);

-- ============================================
-- Table: upload_sessions
-- Description: Track ongoing file uploads with tokens
-- ============================================
CREATE TABLE IF NOT EXISTS upload_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    upload_token VARCHAR(512) NOT NULL UNIQUE,
    file_hash VARCHAR(64),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT expires_at_future CHECK (expires_at > created_at),
    CONSTRAINT upload_token_not_empty CHECK (LENGTH(upload_token) > 0)
);

-- Indexes for upload_sessions table
CREATE INDEX IF NOT EXISTS idx_upload_sessions_post_id ON upload_sessions(post_id);
CREATE INDEX IF NOT EXISTS idx_upload_sessions_upload_token ON upload_sessions(upload_token);
CREATE INDEX IF NOT EXISTS idx_upload_sessions_expires_at ON upload_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_upload_sessions_is_completed ON upload_sessions(is_completed) WHERE is_completed = FALSE;

-- ============================================
-- Trigger: Update updated_at timestamp on posts
-- ============================================
DROP TRIGGER IF EXISTS update_posts_updated_at ON posts;
CREATE TRIGGER update_posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Trigger: Update updated_at timestamp on post_images
-- ============================================
DROP TRIGGER IF EXISTS update_post_images_updated_at ON post_images;
CREATE TRIGGER update_post_images_updated_at
    BEFORE UPDATE ON post_images
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Trigger: Update updated_at timestamp on post_metadata
-- ============================================
DROP TRIGGER IF EXISTS update_post_metadata_updated_at ON post_metadata;
CREATE TRIGGER update_post_metadata_updated_at
    BEFORE UPDATE ON post_metadata
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Trigger: Create post_metadata entry on post creation
-- ============================================
CREATE OR REPLACE FUNCTION create_post_metadata()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO post_metadata (post_id, like_count, comment_count, view_count)
    VALUES (NEW.id, 0, 0, 0)
    ON CONFLICT (post_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS create_metadata_on_post_insert ON posts;
CREATE TRIGGER create_metadata_on_post_insert
    AFTER INSERT ON posts
    FOR EACH ROW
    EXECUTE FUNCTION create_post_metadata();

-- ============================================
-- Function: Get post with all image URLs
-- ============================================
CREATE OR REPLACE FUNCTION get_post_with_images(p_post_id UUID)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    caption TEXT,
    status VARCHAR,
    thumbnail_url VARCHAR,
    medium_url VARCHAR,
    original_url VARCHAR,
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
        p.status,
        (SELECT url FROM post_images WHERE post_id = p.id AND size_variant = 'thumbnail' AND status = 'completed' LIMIT 1),
        (SELECT url FROM post_images WHERE post_id = p.id AND size_variant = 'medium' AND status = 'completed' LIMIT 1),
        (SELECT url FROM post_images WHERE post_id = p.id AND size_variant = 'original' AND status = 'completed' LIMIT 1),
        pm.like_count,
        pm.comment_count,
        pm.view_count,
        p.created_at
    FROM posts p
    LEFT JOIN post_metadata pm ON p.id = pm.post_id
    WHERE p.id = p_post_id AND p.soft_delete IS NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Function: Cleanup expired upload sessions
-- ============================================
CREATE OR REPLACE FUNCTION cleanup_expired_uploads()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM upload_sessions
    WHERE expires_at < NOW() AND is_completed = FALSE;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE posts IS 'User-created image posts with captions and metadata';
COMMENT ON COLUMN posts.image_key IS 'S3 object key for the uploaded image';
COMMENT ON COLUMN posts.image_sizes IS 'JSON object containing URLs for different image sizes';
COMMENT ON COLUMN posts.status IS 'Processing status: pending, processing, published, or failed';
COMMENT ON COLUMN posts.soft_delete IS 'Soft delete timestamp for GDPR compliance';

COMMENT ON TABLE post_images IS 'Transcoded image variants (thumbnail, medium, original)';
COMMENT ON COLUMN post_images.s3_key IS 'S3 object key for this specific variant';
COMMENT ON COLUMN post_images.size_variant IS 'Which variant: thumbnail (150x150), medium (600x600), or original';
COMMENT ON COLUMN post_images.status IS 'Processing status for this variant';

COMMENT ON TABLE post_metadata IS 'Engagement metrics for posts (likes, comments, views)';
COMMENT ON TABLE upload_sessions IS 'Track ongoing uploads with time-limited tokens';

COMMENT ON FUNCTION get_post_with_images(UUID) IS 'Retrieve post with all image URLs and metadata';
COMMENT ON FUNCTION cleanup_expired_uploads() IS 'Delete expired upload sessions for cleanup jobs';
