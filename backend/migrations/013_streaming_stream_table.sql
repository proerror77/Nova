-- ============================================
-- Migration: 013_streaming_stream_table
-- Description: Create streams table for live broadcast management
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- ============================================
-- Type: stream_status_enum
-- Description: Enumeration of possible stream states
-- ============================================
CREATE TYPE IF NOT EXISTS stream_status_enum AS ENUM (
    'idle',         -- Stream key created but never started
    'pending',      -- Starting up, not yet accepting viewers
    'live',         -- Actively broadcasting
    'paused',       -- Temporarily paused by broadcaster
    'ended',        -- Gracefully ended by broadcaster
    'interrupted',  -- Unexpectedly disconnected
    'error'         -- Failed to start or encountered fatal error
);

COMMENT ON TYPE stream_status_enum IS 'Stream lifecycle states';

-- ============================================
-- Table: streams
-- Description: Live broadcast stream metadata and lifecycle
-- ============================================
CREATE TABLE IF NOT EXISTS streams (
    stream_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    broadcaster_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Lifecycle
    status stream_status_enum NOT NULL DEFAULT 'idle',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,

    -- Viewer metrics
    concurrent_viewers INTEGER NOT NULL DEFAULT 0,
    total_viewers INTEGER NOT NULL DEFAULT 0,
    peak_concurrent_viewers INTEGER NOT NULL DEFAULT 0,

    -- Stream metadata
    title VARCHAR(255) NOT NULL,
    description TEXT,
    tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    thumbnail_url VARCHAR(512),

    -- Stream configuration
    is_mature_content BOOLEAN NOT NULL DEFAULT FALSE,
    is_subscribers_only BOOLEAN NOT NULL DEFAULT FALSE,
    language_code VARCHAR(5),

    -- Constraints
    CONSTRAINT title_not_empty CHECK (LENGTH(TRIM(title)) > 0),
    CONSTRAINT started_after_created CHECK (started_at IS NULL OR started_at >= created_at),
    CONSTRAINT ended_after_started CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT concurrent_viewers_non_negative CHECK (concurrent_viewers >= 0),
    CONSTRAINT total_viewers_non_negative CHECK (total_viewers >= 0),
    CONSTRAINT peak_viewers_non_negative CHECK (peak_concurrent_viewers >= 0),
    CONSTRAINT peak_ge_concurrent CHECK (peak_concurrent_viewers >= concurrent_viewers),
    CONSTRAINT tags_is_array CHECK (jsonb_typeof(tags) = 'array')
);

-- ============================================
-- Indexes for streams table
-- ============================================
-- Query live streams by status and start time
CREATE INDEX IF NOT EXISTS idx_streams_status_started_at
    ON streams(status, started_at DESC)
    WHERE status IN ('live', 'pending');

-- Query all streams by broadcaster
CREATE INDEX IF NOT EXISTS idx_streams_broadcaster_id
    ON streams(broadcaster_id);

-- Query recent live streams
CREATE INDEX IF NOT EXISTS idx_streams_started_at
    ON streams(started_at DESC NULLS LAST);

-- Query streams by creation time
CREATE INDEX IF NOT EXISTS idx_streams_created_at
    ON streams(created_at DESC);

-- Full-text search on stream title and tags
CREATE INDEX IF NOT EXISTS idx_streams_title_trgm
    ON streams USING gin(title gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_streams_tags_gin
    ON streams USING gin(tags);

-- Query by language
CREATE INDEX IF NOT EXISTS idx_streams_language_code
    ON streams(language_code)
    WHERE language_code IS NOT NULL;

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE streams IS 'Live broadcast stream lifecycle and metadata';
COMMENT ON COLUMN streams.stream_id IS 'Unique identifier for each stream session';
COMMENT ON COLUMN streams.broadcaster_id IS 'User who owns this stream';
COMMENT ON COLUMN streams.status IS 'Current lifecycle state of the stream';
COMMENT ON COLUMN streams.started_at IS 'Timestamp when RTMP ingest began';
COMMENT ON COLUMN streams.ended_at IS 'Timestamp when stream stopped or was interrupted';
COMMENT ON COLUMN streams.concurrent_viewers IS 'Real-time count of active viewers';
COMMENT ON COLUMN streams.total_viewers IS 'Cumulative unique viewers who joined this stream';
COMMENT ON COLUMN streams.peak_concurrent_viewers IS 'Maximum concurrent viewers reached';
COMMENT ON COLUMN streams.tags IS 'JSON array of stream category tags (e.g., ["gaming", "fps"])';
COMMENT ON COLUMN streams.thumbnail_url IS 'CDN URL to stream preview thumbnail';
COMMENT ON COLUMN streams.is_mature_content IS 'Whether stream contains adult/mature content';
COMMENT ON COLUMN streams.is_subscribers_only IS 'Whether only subscribers can view';
