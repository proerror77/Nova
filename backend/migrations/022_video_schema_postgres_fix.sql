-- ============================================
-- Migration: 022_video_schema_postgres_fix
-- Description: Postgres compatibility fixes for legacy video schema
-- ============================================

-- Ensure uuid functions are available (safe if already installed)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------
-- Create videos table with proper Postgres syntax if it is missing.
-- Legacy migration 011 used MySQL-specific INDEX syntax that fails
-- on a clean Postgres database, so we recreate the schema safely.
-- ------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'videos'
    ) THEN
        CREATE TABLE public.videos (
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
    END IF;
END
$$;

-- ------------------------------------------------------------------
-- Ensure columns use Postgres-native defaults even if the table
-- existed previously with gen_random_uuid() defaults.
-- ------------------------------------------------------------------
ALTER TABLE IF EXISTS videos
    ALTER COLUMN id SET DEFAULT uuid_generate_v4();

ALTER TABLE IF EXISTS videos
    ALTER COLUMN created_at SET DEFAULT NOW();

ALTER TABLE IF EXISTS videos
    ALTER COLUMN updated_at SET DEFAULT NOW();

-- ------------------------------------------------------------------
-- Create video_engagement table for Postgres installs if missing.
-- ------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'video_engagement'
    ) THEN
        CREATE TABLE public.video_engagement (
            video_id UUID PRIMARY KEY REFERENCES videos(id) ON DELETE CASCADE,
            view_count BIGINT NOT NULL DEFAULT 0 CHECK (view_count >= 0),
            like_count BIGINT NOT NULL DEFAULT 0 CHECK (like_count >= 0),
            share_count BIGINT NOT NULL DEFAULT 0 CHECK (share_count >= 0),
            comment_count BIGINT NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
            completion_rate DOUBLE PRECISION DEFAULT 0.0 CHECK (completion_rate >= 0 AND completion_rate <= 1.0),
            avg_watch_seconds INT DEFAULT 0 CHECK (avg_watch_seconds >= 0),
            last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
    END IF;
END
$$;

-- ------------------------------------------------------------------
-- Clean up legacy MySQL-style indexes if they ever existed.
-- ------------------------------------------------------------------
DROP INDEX IF EXISTS idx_creator_id;
DROP INDEX IF EXISTS idx_status;
DROP INDEX IF EXISTS idx_created_at;
DROP INDEX IF EXISTS idx_published_at;
DROP INDEX IF EXISTS idx_view_count;
DROP INDEX IF EXISTS idx_like_count;

-- ------------------------------------------------------------------
-- Recreate indexes using valid Postgres syntax (idempotent).
-- ------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_videos_creator_id
    ON videos (creator_id);

CREATE INDEX IF NOT EXISTS idx_videos_status
    ON videos (status);

CREATE INDEX IF NOT EXISTS idx_videos_created_at
    ON videos (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_videos_published_at
    ON videos (published_at DESC);

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

-- ------------------------------------------------------------------
-- Convert legacy TIMESTAMP columns to TIMESTAMPTZ (UTC).
-- ------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'videos'
          AND column_name = 'created_at'
          AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE videos
            ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
            ALTER COLUMN published_at TYPE TIMESTAMPTZ USING published_at AT TIME ZONE 'UTC',
            ALTER COLUMN archived_at TYPE TIMESTAMPTZ USING archived_at AT TIME ZONE 'UTC',
            ALTER COLUMN deleted_at TYPE TIMESTAMPTZ USING deleted_at AT TIME ZONE 'UTC',
            ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'video_engagement'
          AND column_name = 'last_updated'
          AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE video_engagement
            ALTER COLUMN last_updated TYPE TIMESTAMPTZ USING last_updated AT TIME ZONE 'UTC';
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'video_engagement'
          AND column_name = 'completion_rate'
          AND data_type = 'numeric'
    ) THEN
        ALTER TABLE video_engagement
            ALTER COLUMN completion_rate TYPE DOUBLE PRECISION USING completion_rate::DOUBLE PRECISION;
    END IF;
END
$$;
