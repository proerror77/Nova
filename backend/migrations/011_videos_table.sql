-- Created: 2025-10-19
-- Purpose: Store video metadata for Phase 4 Reels & Video Feed System

-- ========================================
-- Videos Table (Authoritative Source)
-- ========================================
-- Ensure UUID extension is available
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS videos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    duration_seconds INT NOT NULL CHECK (duration_seconds > 0 AND duration_seconds <= 600),
    upload_url VARCHAR(512),
    cdn_url VARCHAR(512),
    thumbnail_url VARCHAR(512),
    status VARCHAR(50) NOT NULL DEFAULT 'uploading' CHECK (
        status IN ('uploading', 'processing', 'published', 'archived', 'deleted')
    ),
    content_type VARCHAR(50) NOT NULL DEFAULT 'original' CHECK (
        content_type IN ('original', 'challenge', 'duet', 'reaction', 'remix')
    ),
    hashtags JSONB DEFAULT '[]'::jsonb,
    visibility VARCHAR(20) NOT NULL DEFAULT 'public' CHECK (
        visibility IN ('public', 'friends', 'private')
    ),
    allow_comments BOOLEAN DEFAULT TRUE,
    allow_duet BOOLEAN DEFAULT TRUE,
    allow_react BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP,
    archived_at TIMESTAMP,
    deleted_at TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ========================================
-- Video Engagement Table (Denormalized)
-- ========================================
CREATE TABLE IF NOT EXISTS video_engagement (
    video_id UUID PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
    view_count BIGINT NOT NULL DEFAULT 0 CHECK (view_count >= 0),
    like_count BIGINT NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    share_count BIGINT NOT NULL DEFAULT 0 CHECK (share_count >= 0),
    comment_count BIGINT NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    completion_rate NUMERIC(3,2) DEFAULT 0.00 CHECK (completion_rate >= 0 AND completion_rate <= 1.00),
    avg_watch_seconds INT DEFAULT 0 CHECK (avg_watch_seconds >= 0),
    last_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ========================================
-- Triggers for Updated Timestamps
-- ========================================
CREATE OR REPLACE FUNCTION update_videos_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS videos_update_timestamp ON videos;
CREATE TRIGGER videos_update_timestamp
BEFORE UPDATE ON videos
FOR EACH ROW
EXECUTE FUNCTION update_videos_timestamp();

-- ========================================
-- Indexes for Common Queries (PostgreSQL style)
-- ========================================

-- From inline INDEX declarations in table definitions
CREATE INDEX IF NOT EXISTS idx_videos_creator_id ON videos(creator_id);
CREATE INDEX IF NOT EXISTS idx_videos_status ON videos(status);
CREATE INDEX IF NOT EXISTS idx_videos_created_at ON videos(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_published_at ON videos(published_at DESC);

-- For fetching creator's videos
CREATE INDEX IF NOT EXISTS idx_videos_creator_status
ON videos(creator_id, status, published_at DESC);

-- For feed queries
CREATE INDEX IF NOT EXISTS idx_videos_published_visibility
ON videos(published_at DESC, visibility)
WHERE status = 'published' AND deleted_at IS NULL;

-- For search by hashtags
CREATE INDEX IF NOT EXISTS idx_videos_hashtags
ON videos USING GIN (hashtags);

-- Engagement indexes (cannot reference other tables in partial index predicate)
CREATE INDEX IF NOT EXISTS idx_video_engagement_view_count ON video_engagement(view_count DESC);
CREATE INDEX IF NOT EXISTS idx_video_engagement_like_count ON video_engagement(like_count DESC);

-- ========================================
-- Soft Delete Support
-- ========================================
-- Soft delete: mark video as deleted instead of removing it
-- This maintains referential integrity and allows recovery

-- Function to soft-delete a video
CREATE OR REPLACE FUNCTION soft_delete_video(video_id_param UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE videos
    SET status = 'deleted', deleted_at = CURRENT_TIMESTAMP
    WHERE id = video_id_param;
END;
$$ LANGUAGE plpgsql;

-- Function to restore a soft-deleted video
CREATE OR REPLACE FUNCTION restore_video(video_id_param UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE videos
    SET status = 'published', deleted_at = NULL
    WHERE id = video_id_param AND deleted_at IS NOT NULL;
END;
$$ LANGUAGE plpgsql;
