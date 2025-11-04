-- ============================================
-- Migration: 040_reels_schema
-- Description: Foundational schema for reels, variants, and transcoding jobs
-- ============================================

-- Ensure UUID + JSON support
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Reels table storing short-form video metadata and processing state
CREATE TABLE IF NOT EXISTS reels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    upload_id UUID REFERENCES uploads(id) ON DELETE SET NULL,
    caption TEXT,
    music_title VARCHAR(255),
    music_artist VARCHAR(255),
    music_id UUID,
    duration_seconds INT CHECK (duration_seconds IS NULL OR duration_seconds > 0),
    visibility VARCHAR(16) NOT NULL DEFAULT 'public' CHECK (
        visibility IN ('public', 'friends', 'private')
    ),
    status VARCHAR(16) NOT NULL DEFAULT 'draft' CHECK (
        status IN ('draft', 'processing', 'ready', 'published', 'failed', 'deleted')
    ),
    processing_stage VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (
        processing_stage IN (
            'pending',
            'queued',
            'download',
            'transcoding',
            'packaging',
            'publishing',
            'completed',
            'failed'
        )
    ),
    processing_progress SMALLINT NOT NULL DEFAULT 0 CHECK (
        processing_progress >= 0 AND processing_progress <= 100
    ),
    view_count BIGINT NOT NULL DEFAULT 0 CHECK (view_count >= 0),
    like_count BIGINT NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    share_count BIGINT NOT NULL DEFAULT 0 CHECK (share_count >= 0),
    comment_count BIGINT NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    allow_comments BOOLEAN NOT NULL DEFAULT TRUE,
    allow_shares BOOLEAN NOT NULL DEFAULT TRUE,
    audio_track JSONB,
    cover_image_url TEXT,
    source_video_url TEXT,
    published_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_reels_creator_status
    ON reels (creator_id, status, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_reels_status_created_at
    ON reels (status, created_at DESC)
    WHERE deleted_at IS NULL;

-- Keep updated_at current
CREATE OR REPLACE FUNCTION update_reels_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER reels_update_timestamp
BEFORE UPDATE ON reels
FOR EACH ROW
EXECUTE FUNCTION update_reels_timestamp();

-- Reel variants (adaptive bitrate outputs)
CREATE TABLE IF NOT EXISTS reel_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    quality VARCHAR(16) NOT NULL,
    codec VARCHAR(32) NOT NULL DEFAULT 'h264',
    bitrate_kbps INT NOT NULL CHECK (bitrate_kbps > 0),
    width INT NOT NULL CHECK (width > 0),
    height INT NOT NULL CHECK (height > 0),
    frame_rate REAL DEFAULT 30.0,
    cdn_url TEXT,
    file_size_bytes BIGINT CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (reel_id, quality)
);

CREATE INDEX IF NOT EXISTS idx_reel_variants_reel_id
    ON reel_variants (reel_id);

CREATE OR REPLACE FUNCTION update_reel_variants_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER reel_variants_update_timestamp
BEFORE UPDATE ON reel_variants
FOR EACH ROW
EXECUTE FUNCTION update_reel_variants_timestamp();

-- Transcoding jobs per quality/profile
CREATE TABLE IF NOT EXISTS reel_transcode_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    upload_id UUID REFERENCES uploads(id) ON DELETE SET NULL,
    target_quality VARCHAR(16) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'queued' CHECK (
        status IN ('queued', 'processing', 'retrying', 'completed', 'failed', 'cancelled', 'skipped')
    ),
    stage VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (
        stage IN ('pending', 'download', 'transcode', 'package', 'publish', 'completed', 'failed')
    ),
    progress SMALLINT NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
    retry_count INT NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    error_message TEXT,
    worker_id TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reel_transcode_jobs_reel_quality
    ON reel_transcode_jobs (reel_id, target_quality);

CREATE INDEX IF NOT EXISTS idx_reel_transcode_jobs_status
    ON reel_transcode_jobs (status, updated_at DESC);

CREATE OR REPLACE FUNCTION update_reel_transcode_jobs_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER reel_transcode_jobs_update_timestamp
BEFORE UPDATE ON reel_transcode_jobs
FOR EACH ROW
EXECUTE FUNCTION update_reel_transcode_jobs_timestamp();
