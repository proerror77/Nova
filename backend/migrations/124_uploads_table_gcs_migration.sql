-- Migration 124: Update uploads table for GCS migration
-- Description: Add columns required by media-service upload flow after AWS to GCS migration
-- Author: Claude Code
-- Date: 2025-12-18
-- Database: nova_media
--
-- This migration adds columns needed for the new upload flow that supports:
-- - Direct client uploads to GCS via presigned URLs
-- - Upload progress tracking
-- - Video association after processing

-- Add new columns for the upload flow
ALTER TABLE uploads
  ADD COLUMN IF NOT EXISTS video_id UUID,
  ADD COLUMN IF NOT EXISTS file_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS file_size BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS uploaded_size BIGINT DEFAULT 0;

-- Make legacy columns nullable to support new upload flow
-- (new uploads may not populate these fields)
ALTER TABLE uploads ALTER COLUMN filename DROP NOT NULL;
ALTER TABLE uploads ALTER COLUMN mime_type DROP NOT NULL;
ALTER TABLE uploads ALTER COLUMN media_type DROP NOT NULL;
ALTER TABLE uploads ALTER COLUMN size_bytes DROP NOT NULL;

-- Migrate existing data: copy from old columns to new ones
UPDATE uploads
SET file_name = filename
WHERE file_name IS NULL AND filename IS NOT NULL;

UPDATE uploads
SET file_size = size_bytes
WHERE (file_size = 0 OR file_size IS NULL) AND size_bytes IS NOT NULL;

-- Add index for video_id lookups
CREATE INDEX IF NOT EXISTS idx_uploads_video_id ON uploads(video_id) WHERE video_id IS NOT NULL;

-- Add comment documenting the column purposes
COMMENT ON COLUMN uploads.video_id IS 'Associated video ID after upload processing completes';
COMMENT ON COLUMN uploads.file_name IS 'Original filename from client (new upload flow)';
COMMENT ON COLUMN uploads.file_size IS 'Total file size in bytes (new upload flow)';
COMMENT ON COLUMN uploads.uploaded_size IS 'Bytes uploaded so far for progress tracking';
COMMENT ON COLUMN uploads.filename IS 'Legacy: Original filename (deprecated, use file_name)';
COMMENT ON COLUMN uploads.size_bytes IS 'Legacy: File size (deprecated, use file_size)';

-- Rollback script (uncomment to rollback):
/*
DROP INDEX IF EXISTS idx_uploads_video_id;
ALTER TABLE uploads DROP COLUMN IF EXISTS video_id;
ALTER TABLE uploads DROP COLUMN IF EXISTS file_name;
ALTER TABLE uploads DROP COLUMN IF EXISTS file_size;
ALTER TABLE uploads DROP COLUMN IF EXISTS uploaded_size;
ALTER TABLE uploads ALTER COLUMN filename SET NOT NULL;
ALTER TABLE uploads ALTER COLUMN mime_type SET NOT NULL;
ALTER TABLE uploads ALTER COLUMN media_type SET NOT NULL;
ALTER TABLE uploads ALTER COLUMN size_bytes SET NOT NULL;
*/
