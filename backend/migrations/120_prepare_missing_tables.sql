-- ============================================
-- Migration: 120_prepare_missing_tables
-- Description: Create skeleton tables for blocks and media
-- Purpose: Prepare dependencies for migration 123 (unify_soft_delete_complete)
-- ============================================

-- Create blocks table (user blocking system)
CREATE TABLE IF NOT EXISTS blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id, deleted_at)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id, deleted_at)
WHERE deleted_at IS NULL;

COMMENT ON TABLE blocks IS 'User blocking relationships';
COMMENT ON COLUMN blocks.blocker_id IS 'User who initiated the block';
COMMENT ON COLUMN blocks.blocked_id IS 'User who was blocked';

-- Create media table (generic media attachments)
CREATE TABLE IF NOT EXISTS media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    media_type VARCHAR(50) NOT NULL,
    file_path TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    width INTEGER,
    height INTEGER,
    duration_seconds INTEGER,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT valid_media_type CHECK (media_type IN ('image', 'video', 'audio', 'document'))
);

CREATE INDEX IF NOT EXISTS idx_media_user ON media(user_id, created_at DESC)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_media_type ON media(media_type, created_at DESC)
WHERE deleted_at IS NULL;

COMMENT ON TABLE media IS 'Generic media attachments for posts, messages, profiles';
COMMENT ON COLUMN media.file_path IS 'S3/CDN path to media file';
COMMENT ON COLUMN media.duration_seconds IS 'Duration for audio/video media';
