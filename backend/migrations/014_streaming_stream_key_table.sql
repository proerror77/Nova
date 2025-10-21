-- ============================================
-- Migration: 014_streaming_stream_key_table
-- Description: Create stream_keys table for RTMP authentication
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- ============================================
-- Table: stream_keys
-- Description: Broadcaster authentication tokens for RTMP ingest
-- ============================================
CREATE TABLE IF NOT EXISTS stream_keys (
    key_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    broadcaster_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Key material
    key_value VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) NOT NULL UNIQUE,

    -- Key lifecycle
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE,

    -- Usage tracking
    last_used_at TIMESTAMP WITH TIME ZONE,
    last_used_ip INET,
    usage_count INTEGER NOT NULL DEFAULT 0,

    -- Metadata
    description VARCHAR(255),

    -- Constraints
    CONSTRAINT key_value_not_empty CHECK (LENGTH(key_value) > 0),
    CONSTRAINT key_hash_not_empty CHECK (LENGTH(key_hash) > 0),
    CONSTRAINT revoked_consistency CHECK (
        (is_active = TRUE AND revoked_at IS NULL) OR
        (is_active = FALSE AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT last_used_after_created CHECK (last_used_at IS NULL OR last_used_at >= created_at),
    CONSTRAINT usage_count_non_negative CHECK (usage_count >= 0)
);

-- ============================================
-- Indexes for stream_keys table
-- ============================================
-- Query active keys by broadcaster
CREATE INDEX IF NOT EXISTS idx_stream_keys_broadcaster_active
    ON stream_keys(broadcaster_id, is_active)
    WHERE is_active = TRUE;

-- Authenticate by key hash during RTMP handshake
CREATE UNIQUE INDEX IF NOT EXISTS idx_stream_keys_key_hash
    ON stream_keys(key_hash);

-- Query keys by creation time
CREATE INDEX IF NOT EXISTS idx_stream_keys_created_at
    ON stream_keys(created_at DESC);

-- Query recently used keys
CREATE INDEX IF NOT EXISTS idx_stream_keys_last_used_at
    ON stream_keys(last_used_at DESC NULLS LAST);

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE stream_keys IS 'RTMP ingest authentication keys for broadcasters';
COMMENT ON COLUMN stream_keys.key_id IS 'Unique identifier for the stream key';
COMMENT ON COLUMN stream_keys.broadcaster_id IS 'User who owns this stream key';
COMMENT ON COLUMN stream_keys.key_value IS 'Plain text stream key (displayed once, then hashed)';
COMMENT ON COLUMN stream_keys.key_hash IS 'bcrypt hash of key_value for authentication';
COMMENT ON COLUMN stream_keys.is_active IS 'Whether key can be used for new streams';
COMMENT ON COLUMN stream_keys.revoked_at IS 'Timestamp when key was manually revoked';
COMMENT ON COLUMN stream_keys.last_used_at IS 'Most recent RTMP connection using this key';
COMMENT ON COLUMN stream_keys.last_used_ip IS 'IP address of most recent RTMP connection';
COMMENT ON COLUMN stream_keys.usage_count IS 'Total number of streams initiated with this key';
COMMENT ON COLUMN stream_keys.description IS 'User-defined label for key management (e.g., "OBS key")';
