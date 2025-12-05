-- ============================================
-- Migration: 125_fix_posts_schema_for_content_service
-- Description: Add missing columns for content-service compatibility
-- Author: Nova Team
-- Date: 2025-12-05
-- Updated: 2025-12-05 - Added UUID default for id column
-- ============================================

-- Ensure uuid-ossp extension exists for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Fix: Set default UUID generator for id column (required for INSERT without explicit id)
ALTER TABLE posts ALTER COLUMN id SET DEFAULT uuid_generate_v4();

-- Add missing columns to posts table that content-service expects
-- These columns are needed for the gRPC content-service to function properly

-- Add 'content' column (alias for caption, but content-service expects both)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS content TEXT;

-- Add 'media_key' column (content-service uses this instead of image_key)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS media_key VARCHAR(512);

-- Add 'media_type' column (to distinguish between image/video/text posts)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS media_type VARCHAR(50) DEFAULT 'image';

-- Add 'media_urls' column (JSONB array of CDN URLs)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]'::jsonb;

-- Add 'deleted_at' column if not exists (some schemas use soft_delete instead)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;

-- Backfill media_key from image_key for existing posts
UPDATE posts SET media_key = image_key WHERE media_key IS NULL AND image_key IS NOT NULL;

-- Set default for media_key on new posts
ALTER TABLE posts ALTER COLUMN media_key SET DEFAULT '';

-- Create indexes for new columns
CREATE INDEX IF NOT EXISTS idx_posts_media_type ON posts(media_type);
CREATE INDEX IF NOT EXISTS idx_posts_deleted_at ON posts(deleted_at) WHERE deleted_at IS NULL;

-- Comments for documentation
COMMENT ON COLUMN posts.content IS 'Post content text (used by content-service)';
COMMENT ON COLUMN posts.media_key IS 'S3/storage key for attached media';
COMMENT ON COLUMN posts.media_type IS 'Type of media: image, video, or text';
COMMENT ON COLUMN posts.media_urls IS 'JSON array of CDN URLs for attached media';
COMMENT ON COLUMN posts.deleted_at IS 'Soft delete timestamp';
