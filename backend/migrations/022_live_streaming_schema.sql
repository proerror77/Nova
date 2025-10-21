-- ============================================
-- Live Streaming Schema for Phase 5
-- ============================================

-- Live streams table
CREATE TABLE IF NOT EXISTS live_streams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    broadcaster_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Stream metadata
    title VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(50),
    is_mature_content BOOLEAN DEFAULT false,

    -- Stream status
    status VARCHAR(50) DEFAULT 'scheduled', -- 'scheduled', 'live', 'ended', 'archived'
    visibility VARCHAR(50) DEFAULT 'public', -- 'public', 'friends', 'private'

    -- Scheduling
    scheduled_start_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INT,

    -- RTMP/HLS
    rtmp_url VARCHAR(500),
    rtmp_key VARCHAR(255) UNIQUE,
    hls_playlist_url VARCHAR(500),
    hls_thumbnail_url VARCHAR(500),

    -- Stream statistics
    viewer_count INT DEFAULT 0,
    peak_viewers INT DEFAULT 0,
    total_watched_minutes BIGINT DEFAULT 0,
    engagement_score FLOAT DEFAULT 0.0,

    -- Quality
    bitrate_kbps INT,
    resolution VARCHAR(20), -- '1080p', '720p', '480p', etc.
    fps INT,
    video_codec VARCHAR(20),
    audio_codec VARCHAR(20),

    -- Health
    stream_health FLOAT DEFAULT 0.0, -- 0.0-1.0
    dropped_frames_count INT DEFAULT 0,
    rebuffer_count INT DEFAULT 0,

    -- Archival
    is_archived BOOLEAN DEFAULT false,
    archive_url VARCHAR(500),
    archive_available_until TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Live stream viewers
CREATE TABLE IF NOT EXISTS live_stream_viewers (
    id BIGSERIAL PRIMARY KEY,
    stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    viewer_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Session info
    session_id VARCHAR(255) UNIQUE,
    client_ip INET,
    user_agent TEXT,
    device_type VARCHAR(50), -- 'desktop', 'mobile', 'tablet', 'tv'

    -- Quality metrics
    buffer_count INT DEFAULT 0,
    average_latency_ms INT DEFAULT 0,
    bandwidth_used_mb BIGINT DEFAULT 0,

    -- Timestamps
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP WITH TIME ZONE,
    watched_duration_seconds INT DEFAULT 0
);

-- Chat messages during live streams
CREATE TABLE IF NOT EXISTS live_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Message content
    message TEXT NOT NULL,
    is_deleted BOOLEAN DEFAULT false,

    -- Moderation
    is_moderated BOOLEAN DEFAULT false,
    moderation_reason VARCHAR(255),
    moderator_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Stats
    like_count INT DEFAULT 0,
    pin_count INT DEFAULT 0,
    is_pinned BOOLEAN DEFAULT false,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Super chat (paid messages)
CREATE TABLE IF NOT EXISTS super_chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    chat_message_id UUID REFERENCES live_chat_messages(id) ON DELETE SET NULL,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Amount
    amount_cents BIGINT NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(50) DEFAULT 'completed', -- 'pending', 'completed', 'failed'

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE
);

-- Streaming hosts/co-hosts
CREATE TABLE IF NOT EXISTS stream_hosts (
    id BIGSERIAL PRIMARY KEY,
    stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,
    host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Role
    role VARCHAR(50) DEFAULT 'co-host', -- 'co-host', 'host'
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP WITH TIME ZONE,

    UNIQUE(stream_id, host_id)
);

-- Stream DVR (Digital Video Recorder) segments
CREATE TABLE IF NOT EXISTS stream_segments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stream_id UUID NOT NULL REFERENCES live_streams(id) ON DELETE CASCADE,

    -- Segment info
    segment_number INT NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE,
    duration_seconds INT,

    -- Storage
    storage_url VARCHAR(500),
    file_size_bytes BIGINT,
    bitrate_kbps INT,

    -- Status
    status VARCHAR(50) DEFAULT 'recording', -- 'recording', 'archived', 'deleted'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_live_streams_broadcaster_id ON live_streams(broadcaster_id);
CREATE INDEX IF NOT EXISTS idx_live_streams_status ON live_streams(status);
CREATE INDEX IF NOT EXISTS idx_live_streams_started_at ON live_streams(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_streams_category ON live_streams(category);

CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_stream_id ON live_stream_viewers(stream_id);
CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_viewer_id ON live_stream_viewers(viewer_id);
CREATE INDEX IF NOT EXISTS idx_live_stream_viewers_joined_at ON live_stream_viewers(joined_at DESC);

CREATE INDEX IF NOT EXISTS idx_live_chat_messages_stream_id ON live_chat_messages(stream_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_chat_messages_user_id ON live_chat_messages(user_id);

CREATE INDEX IF NOT EXISTS idx_super_chats_stream_id ON super_chats(stream_id);
CREATE INDEX IF NOT EXISTS idx_super_chats_sender_id ON super_chats(sender_id);

CREATE INDEX IF NOT EXISTS idx_stream_hosts_stream_id ON stream_hosts(stream_id);
CREATE INDEX IF NOT EXISTS idx_stream_segments_stream_id ON stream_segments(stream_id);

-- Updated trigger
CREATE OR REPLACE FUNCTION update_live_streams_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER live_streams_update_timestamp
    BEFORE UPDATE ON live_streams
    FOR EACH ROW
    EXECUTE FUNCTION update_live_streams_timestamp();
