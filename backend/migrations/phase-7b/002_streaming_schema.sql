-- Phase 7B: Feature 3 - Video Live Streaming
-- Optimized schema following "good taste" principles
-- Author: Backend System Architect
-- Date: 2025-10-19

-- =============================================================================
-- Core Principle: Minimize database writes, maximize Redis for hot paths
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Live Streams (Metadata Only)
-- -----------------------------------------------------------------------------
-- This table stores ONLY persistent metadata, NOT real-time state
-- Real-time state (viewer counts) lives in Redis
CREATE TABLE IF NOT EXISTS live_streams (
    -- Identity
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL,
    stream_key VARCHAR(255) UNIQUE NOT NULL,  -- UUID for RTMP auth (never exposed in public APIs)

    -- Content metadata
    title VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(50) CHECK (category IN ('gaming', 'music', 'tech', 'lifestyle', 'education', 'other')),

    -- Stream state (SIMPLIFIED from 5 to 3 states)
    -- 'preparing' = created but not started
    -- 'live' = currently streaming
    -- 'ended' = stream finished
    status VARCHAR(20) NOT NULL DEFAULT 'preparing' CHECK (status IN ('preparing', 'live', 'ended')),

    -- URLs (computed, some cached here for convenience)
    rtmp_url VARCHAR(500),  -- rtmp://stream.nova.com/live/{stream_key}
    hls_url VARCHAR(500),   -- https://cdn.nova.com/hls/{stream_id}/playlist.m3u8 (null if not live)
    thumbnail_url VARCHAR(500),  -- Generated thumbnail

    -- Aggregated analytics (periodically synced from Redis/ClickHouse, NOT real-time)
    current_viewers INT DEFAULT 0,  -- Updated every 10 seconds from Redis
    peak_viewers INT DEFAULT 0,     -- Updated when new peak detected
    total_unique_viewers INT DEFAULT 0,  -- Updated on stream end from ClickHouse
    total_messages INT DEFAULT 0,   -- Chat message count

    -- Settings
    auto_archive BOOLEAN DEFAULT true,  -- Auto-convert to VOD on stream end

    -- Lifecycle timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,  -- When RTMP connection established
    ended_at TIMESTAMP,    -- When RTMP connection closed

    -- Foreign keys
    CONSTRAINT fk_stream_creator FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for query patterns
CREATE INDEX idx_streams_creator_status ON live_streams(creator_id, status);  -- Creator's stream list
CREATE INDEX idx_streams_status_started ON live_streams(status, started_at DESC);  -- Live stream discovery (sorted by recency)
CREATE INDEX idx_streams_status_viewers ON live_streams(status, current_viewers DESC);  -- Live stream discovery (sorted by popularity)
CREATE INDEX idx_streams_created_at ON live_streams(created_at DESC);  -- Historical streams

-- Trigger: Update updated_at timestamp (removed from table, use created_at for most queries)
-- Reason: updated_at causes write amplification when viewer count updates


-- -----------------------------------------------------------------------------
-- Stream Metadata (Technical Settings)
-- -----------------------------------------------------------------------------
-- Separated from main table to avoid bloating hot queries
CREATE TABLE IF NOT EXISTS stream_metadata (
    stream_id UUID PRIMARY KEY,

    -- Encoding settings (recommended by us, actual values may differ)
    bitrate_kbps INT DEFAULT 2500,
    resolution VARCHAR(20) DEFAULT '1080p' CHECK (resolution IN ('360p', '480p', '720p', '1080p', '1440p', '4k')),
    fps INT DEFAULT 30,
    codec VARCHAR(20) DEFAULT 'h264' CHECK (codec IN ('h264', 'h265', 'vp9', 'av1')),

    -- Health metrics (updated periodically by monitoring service)
    last_bitrate_kbps INT,
    last_fps INT,
    dropped_frames INT DEFAULT 0,
    last_health_check_at TIMESTAMP,

    CONSTRAINT fk_metadata_stream FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE
);

-- No additional indexes needed (primary key on stream_id sufficient)


-- -----------------------------------------------------------------------------
-- Stream Chat Bans (Moderation)
-- -----------------------------------------------------------------------------
-- Lightweight table for permanent bans
-- Temporary bans (<24h) stored in Redis only for performance
CREATE TABLE IF NOT EXISTS stream_chat_bans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stream_id UUID NOT NULL,
    user_id UUID NOT NULL,
    banned_by UUID NOT NULL,  -- Creator or moderator
    reason TEXT,
    expires_at TIMESTAMP,  -- NULL = permanent ban
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_ban_stream FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE,
    CONSTRAINT fk_ban_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_ban_moderator FOREIGN KEY (banned_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT unique_stream_user_ban UNIQUE (stream_id, user_id)
);

-- Index for ban check (critical path in chat)
CREATE INDEX idx_bans_stream_user ON stream_chat_bans(stream_id, user_id) WHERE expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP;


-- -----------------------------------------------------------------------------
-- Stream VODs (Video on Demand)
-- -----------------------------------------------------------------------------
-- Created after stream ends (if auto_archive enabled)
CREATE TABLE IF NOT EXISTS stream_vods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stream_id UUID UNIQUE NOT NULL,  -- One VOD per stream

    -- VOD files (uploaded to S3)
    hls_manifest_url VARCHAR(500),  -- HLS playlist for adaptive streaming
    mp4_url VARCHAR(500),            -- Direct MP4 download
    thumbnail_url VARCHAR(500),      -- Preview thumbnail

    -- Metadata
    duration_secs INT NOT NULL,
    file_size_bytes BIGINT,

    -- Processing status
    processing_status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
    processing_error TEXT,  -- Error message if failed
    retry_count INT DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processing_started_at TIMESTAMP,
    processing_completed_at TIMESTAMP,

    CONSTRAINT fk_vod_stream FOREIGN KEY (stream_id) REFERENCES live_streams(id) ON DELETE CASCADE
);

-- Index for processing queue
CREATE INDEX idx_vods_processing_status ON stream_vods(processing_status, created_at) WHERE processing_status IN ('pending', 'processing');


-- -----------------------------------------------------------------------------
-- REMOVED TABLES (moved to more appropriate storage)
-- -----------------------------------------------------------------------------

-- ❌ stream_viewers (REMOVED)
-- Reason: 100K viewers = 100K rows = write disaster
-- Replacement: Redis counters + ClickHouse events
--   - Redis: INCR stream:{stream_id}:viewers (real-time count)
--   - ClickHouse: stream_viewer_events (analytics)

-- ❌ stream_chat_messages (REMOVED)
-- Reason: Chat is real-time, doesn't need PostgreSQL ACID
-- Replacement: WebSocket broadcast + ClickHouse analytics
--   - WebSocket: Real-time delivery (in-memory)
--   - ClickHouse: stream_chat_analytics (historical analysis)

-- ❌ stream_engagement_events (REMOVED)
-- Reason: Pure analytics data, belongs in OLAP
-- Replacement: ClickHouse stream_engagement_events

-- ❌ stream_segments (REMOVED)
-- Reason: Filesystem concern, not database concern
-- Replacement: S3 object storage + metadata in stream_vods

-- ❌ stream_gifts (REMOVED)
-- Reason: Monetization is out of scope for Phase 7B
-- Timeline: Phase 9 (when payment processing added)


-- -----------------------------------------------------------------------------
-- Data Migration Notes (if upgrading from phase-7/003_streaming_schema.sql)
-- -----------------------------------------------------------------------------

-- 1. Drop old tables (if exist)
-- DROP TABLE IF EXISTS stream_viewers CASCADE;
-- DROP TABLE IF EXISTS stream_chat_messages CASCADE;
-- DROP TABLE IF EXISTS stream_engagement_events CASCADE;
-- DROP TABLE IF EXISTS stream_segments CASCADE;
-- DROP TABLE IF EXISTS stream_gifts CASCADE;

-- 2. Migrate viewer counts from stream_viewers to Redis (run script)
-- Script: backend/scripts/migrate_viewer_counts_to_redis.sh

-- 3. Migrate chat messages to ClickHouse (run script)
-- Script: backend/scripts/migrate_chat_to_clickhouse.sh


-- -----------------------------------------------------------------------------
-- Performance Tuning
-- -----------------------------------------------------------------------------

-- Vacuum settings for high-write tables (none in optimized schema!)
-- Reason: We minimized writes by moving hot data to Redis

-- Connection pooling recommendation
-- Max connections: 100 (PostgreSQL)
-- Application pool size: 20 per instance (5 instances = 100 total)

-- Read replica recommendation
-- Analytics queries (GET /streams/{id}/analytics) -> read replica
-- Write queries (POST /streams/auth) -> primary


-- -----------------------------------------------------------------------------
-- Security Notes
-- -----------------------------------------------------------------------------

-- 1. stream_key is SECRET
--    - Only returned in POST /streams/create response
--    - Never exposed in GET /streams/{id}
--    - Indexed for O(1) lookup in RTMP auth webhook

-- 2. Row-level security (RLS) not needed
--    - Authorization handled in application layer
--    - Reason: Complex RLS queries slow down PostgreSQL

-- 3. SQL injection prevention
--    - Use parameterized queries (sqlx)
--    - Never concatenate user input


-- -----------------------------------------------------------------------------
-- Monitoring Queries
-- -----------------------------------------------------------------------------

-- Active streams count
-- SELECT COUNT(*) FROM live_streams WHERE status = 'live';

-- Top streams by current viewers
-- SELECT id, title, current_viewers FROM live_streams WHERE status = 'live' ORDER BY current_viewers DESC LIMIT 10;

-- VOD processing queue depth
-- SELECT COUNT(*) FROM stream_vods WHERE processing_status IN ('pending', 'processing');

-- Failed VODs requiring manual intervention
-- SELECT * FROM stream_vods WHERE processing_status = 'failed' AND retry_count >= 3;


-- -----------------------------------------------------------------------------
-- Schema Version
-- -----------------------------------------------------------------------------
-- Version: 2.0 (optimized, removed 5 tables)
-- Previous: phase-7/003_streaming_schema.sql (version 1.0, 8 tables)
-- Changes:
--   - Removed stream_viewers (moved to Redis)
--   - Removed stream_chat_messages (moved to ClickHouse)
--   - Removed stream_engagement_events (moved to ClickHouse)
--   - Removed stream_segments (moved to S3 metadata)
--   - Removed stream_gifts (out of scope)
--   - Simplified status enum (5 -> 3 states)
--   - Added processing_error to stream_vods (debuggability)
