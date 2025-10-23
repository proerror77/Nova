-- ============================================
-- Migration: 022_video_schema_postgres_fix
-- Description: Postgres compatibility fixes for videos schema
-- ============================================

-- Ensure uuid functions are available (safe if already installed)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Align videos.id default with uuid_generate_v4 (Postgres native)
ALTER TABLE IF EXISTS videos
    ALTER COLUMN id SET DEFAULT uuid_generate_v4();

-- Clean up legacy MySQL-style indexes if they ever existed
DROP INDEX IF EXISTS idx_creator_id;
DROP INDEX IF EXISTS idx_status;
DROP INDEX IF EXISTS idx_created_at;
DROP INDEX IF EXISTS idx_published_at;
DROP INDEX IF EXISTS idx_view_count;
DROP INDEX IF EXISTS idx_like_count;

-- Recreate indexes using valid Postgres syntax
CREATE INDEX IF NOT EXISTS idx_videos_creator_status
    ON videos (creator_id, status, published_at DESC);

CREATE INDEX IF NOT EXISTS idx_videos_published_visibility
    ON videos (published_at DESC, visibility)
    WHERE status = 'published' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_videos_hashtags
    ON videos USING GIN (hashtags);

CREATE INDEX IF NOT EXISTS idx_video_engagement_view_count
    ON video_engagement (view_count);

CREATE INDEX IF NOT EXISTS idx_video_engagement_like_count
    ON video_engagement (like_count);
