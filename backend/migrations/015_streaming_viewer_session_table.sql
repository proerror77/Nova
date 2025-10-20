-- ============================================
-- Migration: 015_streaming_viewer_session_table
-- Description: Create viewer_sessions table for analytics and QoS tracking
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- ============================================
-- Type: quality_level_enum
-- Description: Video quality tiers
-- ============================================
CREATE TYPE quality_level_enum AS ENUM (
    'source',  -- Original broadcaster quality
    '1080p',   -- Full HD
    '720p',    -- HD
    '480p',    -- SD
    '360p',    -- Low
    'audio'    -- Audio-only fallback
);

COMMENT ON TYPE quality_level_enum IS 'Adaptive bitrate streaming quality levels';

-- ============================================
-- Table: viewer_sessions
-- Description: Individual viewer playback sessions for analytics
-- ============================================
CREATE TABLE viewer_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
    stream_id UUID NOT NULL REFERENCES streams(stream_id) ON DELETE CASCADE,

    -- Session lifecycle
    joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (COALESCE(left_at, NOW()) - joined_at))::INTEGER
    ) STORED,

    -- Quality of Service (QoS) metrics
    initial_quality quality_level_enum NOT NULL,
    final_quality quality_level_enum,
    quality_switches INTEGER NOT NULL DEFAULT 0,

    -- Buffering analytics
    buffer_events INTEGER NOT NULL DEFAULT 0,
    total_buffer_time_ms INTEGER NOT NULL DEFAULT 0,

    -- Bandwidth consumption
    bytes_transferred BIGINT NOT NULL DEFAULT 0,

    -- Client metadata
    ip_address INET,
    user_agent TEXT,
    player_version VARCHAR(50),
    cdn_edge_node VARCHAR(100),

    -- Constraints
    CONSTRAINT left_after_joined CHECK (left_at IS NULL OR left_at >= joined_at),
    CONSTRAINT quality_switches_non_negative CHECK (quality_switches >= 0),
    CONSTRAINT buffer_events_non_negative CHECK (buffer_events >= 0),
    CONSTRAINT total_buffer_time_non_negative CHECK (total_buffer_time_ms >= 0),
    CONSTRAINT bytes_transferred_non_negative CHECK (bytes_transferred >= 0)
);

-- ============================================
-- Indexes for viewer_sessions table
-- ============================================
-- Query active sessions for a stream (for concurrent viewer count)
CREATE INDEX idx_viewer_sessions_stream_active
    ON viewer_sessions(stream_id, joined_at DESC)
    WHERE left_at IS NULL;

-- Analytics: viewer history per user
CREATE INDEX idx_viewer_sessions_viewer_id
    ON viewer_sessions(viewer_id, joined_at DESC)
    WHERE viewer_id IS NOT NULL;

-- Analytics: time-series queries
CREATE INDEX idx_viewer_sessions_joined_at
    ON viewer_sessions(joined_at DESC);

-- QoS analysis: find sessions with poor quality
CREATE INDEX idx_viewer_sessions_qos
    ON viewer_sessions(stream_id, buffer_events DESC, total_buffer_time_ms DESC)
    WHERE buffer_events > 5 OR total_buffer_time_ms > 10000;

-- CDN routing optimization
CREATE INDEX idx_viewer_sessions_cdn_edge
    ON viewer_sessions(cdn_edge_node, joined_at DESC)
    WHERE cdn_edge_node IS NOT NULL;

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE viewer_sessions IS 'Individual viewer playback sessions for analytics and QoS monitoring';
COMMENT ON COLUMN viewer_sessions.session_id IS 'Unique identifier for each viewer session';
COMMENT ON COLUMN viewer_sessions.viewer_id IS 'User who watched stream (NULL for anonymous viewers)';
COMMENT ON COLUMN viewer_sessions.stream_id IS 'Stream being watched';
COMMENT ON COLUMN viewer_sessions.joined_at IS 'Timestamp when viewer started watching';
COMMENT ON COLUMN viewer_sessions.left_at IS 'Timestamp when viewer stopped watching';
COMMENT ON COLUMN viewer_sessions.duration_seconds IS 'Computed session duration in seconds';
COMMENT ON COLUMN viewer_sessions.initial_quality IS 'Quality level selected at session start';
COMMENT ON COLUMN viewer_sessions.final_quality IS 'Quality level at session end';
COMMENT ON COLUMN viewer_sessions.quality_switches IS 'Number of ABR quality changes during session';
COMMENT ON COLUMN viewer_sessions.buffer_events IS 'Number of times player entered buffering state';
COMMENT ON COLUMN viewer_sessions.total_buffer_time_ms IS 'Total time spent buffering in milliseconds';
COMMENT ON COLUMN viewer_sessions.bytes_transferred IS 'Total bytes delivered to viewer';
COMMENT ON COLUMN viewer_sessions.cdn_edge_node IS 'CDN edge server identifier serving this session';
