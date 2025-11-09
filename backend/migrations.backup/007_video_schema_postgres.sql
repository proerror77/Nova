-- ============================================
-- Migration: 007_video_schema_postgres
-- Description: Postgres-native video schema (replacement for legacy MySQL-style migration)
-- ============================================

-- Ensure UUID support
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Videos table (idempotent)
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
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Video engagement table (idempotent)
CREATE TABLE IF NOT EXISTS video_engagement (
    video_id UUID PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
    view_count BIGINT NOT NULL DEFAULT 0 CHECK (view_count >= 0),
    like_count BIGINT NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    share_count BIGINT NOT NULL DEFAULT 0 CHECK (share_count >= 0),
    comment_count BIGINT NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    completion_rate DOUBLE PRECISION DEFAULT 0.0 CHECK (completion_rate >= 0 AND completion_rate <= 1.0),
    avg_watch_seconds INT DEFAULT 0 CHECK (avg_watch_seconds >= 0),
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger to keep updated_at fresh
CREATE OR REPLACE FUNCTION update_videos_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER videos_update_timestamp
BEFORE UPDATE ON videos
FOR EACH ROW
EXECUTE FUNCTION update_videos_timestamp();

-- Indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_videos_creator_id ON videos (creator_id);
CREATE INDEX IF NOT EXISTS idx_videos_status ON videos (status);
CREATE INDEX IF NOT EXISTS idx_videos_created_at ON videos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_published_at ON videos (published_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_creator_status ON videos (creator_id, status, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_published_visibility
    ON videos (published_at DESC, visibility)
    WHERE status = 'published' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_videos_hashtags ON videos USING GIN (hashtags);
CREATE INDEX IF NOT EXISTS idx_video_engagement_view_count ON video_engagement (view_count);
CREATE INDEX IF NOT EXISTS idx_video_engagement_like_count ON video_engagement (like_count);
