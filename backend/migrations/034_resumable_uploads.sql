-- Migration 034: Resumable Upload Support (重新编号从031)
-- Description: Add tables for chunked video upload tracking with resume capability
-- Author: System
-- Date: 2025-10-25
-- Note: 此迁移已从031_resumable_uploads.sql重新编号以解决编号冲突

-- Enum for upload status
CREATE TYPE upload_status AS ENUM ('uploading', 'completed', 'failed', 'cancelled');

-- Main uploads tracking table
CREATE TABLE IF NOT EXISTS uploads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    video_id UUID REFERENCES videos(id) ON DELETE SET NULL,  -- null until upload completes
    file_name VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    chunk_size INT NOT NULL CHECK (chunk_size > 0),
    chunks_total INT NOT NULL CHECK (chunks_total > 0),
    chunks_uploaded INT NOT NULL DEFAULT 0 CHECK (chunks_uploaded >= 0 AND chunks_uploaded <= chunks_total),
    status upload_status NOT NULL DEFAULT 'uploading',
    s3_upload_id VARCHAR(255),  -- AWS S3 multipart upload ID
    final_hash VARCHAR(64),  -- SHA256 of complete file
    expires_at TIMESTAMP NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Individual chunk tracking table
CREATE TABLE IF NOT EXISTS upload_chunks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    upload_id UUID NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
    chunk_index INT NOT NULL CHECK (chunk_index >= 0),
    chunk_size BIGINT NOT NULL CHECK (chunk_size > 0),
    chunk_hash VARCHAR(64) NOT NULL,  -- SHA256 of chunk for integrity
    s3_etag VARCHAR(255) NOT NULL,  -- S3 ETag for multipart assembly
    s3_key VARCHAR(512) NOT NULL,  -- Full S3 key path
    uploaded_at TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Prevent duplicate chunks
    UNIQUE(upload_id, chunk_index)
);

-- Indexes for performance
CREATE INDEX idx_uploads_user_id ON uploads(user_id);
CREATE INDEX idx_uploads_status ON uploads(status);
CREATE INDEX idx_uploads_expires_at ON uploads(expires_at) WHERE status = 'uploading';
CREATE INDEX idx_upload_chunks_upload_id ON upload_chunks(upload_id);
CREATE INDEX idx_upload_chunks_upload_chunk ON upload_chunks(upload_id, chunk_index);

-- Trigger to update updated_at on uploads table
CREATE OR REPLACE FUNCTION update_uploads_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_uploads_updated_at
    BEFORE UPDATE ON uploads
    FOR EACH ROW
    EXECUTE FUNCTION update_uploads_updated_at();

-- Function to cleanup expired uploads (run via cron/scheduler)
CREATE OR REPLACE FUNCTION cleanup_expired_uploads()
RETURNS TABLE(deleted_count BIGINT) AS $$
DECLARE
    expired_ids UUID[];
    deleted BIGINT;
BEGIN
    -- Find expired uploads
    SELECT ARRAY_AGG(id) INTO expired_ids
    FROM uploads
    WHERE status = 'uploading' AND expires_at < NOW();

    -- Mark as failed (chunks will cascade delete if needed)
    UPDATE uploads
    SET status = 'failed', updated_at = NOW()
    WHERE id = ANY(expired_ids);

    GET DIAGNOSTICS deleted = ROW_COUNT;

    RETURN QUERY SELECT deleted;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions (adjust roles as needed)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON uploads TO nova_app;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON upload_chunks TO nova_app;
-- GRANT USAGE ON SEQUENCE uploads_id_seq TO nova_app;
-- GRANT USAGE ON SEQUENCE upload_chunks_id_seq TO nova_app;

-- Rollback script (commented, uncomment to rollback)
/*
DROP TRIGGER IF EXISTS trigger_uploads_updated_at ON uploads;
DROP FUNCTION IF EXISTS update_uploads_updated_at();
DROP FUNCTION IF EXISTS cleanup_expired_uploads();
DROP INDEX IF EXISTS idx_uploads_user_id;
DROP INDEX IF EXISTS idx_uploads_status;
DROP INDEX IF EXISTS idx_uploads_expires_at;
DROP INDEX IF EXISTS idx_upload_chunks_upload_id;
DROP INDEX IF EXISTS idx_upload_chunks_upload_chunk;
DROP TABLE IF EXISTS upload_chunks;
DROP TABLE IF EXISTS uploads;
DROP TYPE IF EXISTS upload_status;
*/
