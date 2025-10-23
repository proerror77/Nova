-- ============================================
-- Migration: 017_streaming_quality_level_table
-- Description: Create quality_levels table with predefined ABR tiers
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- ============================================
-- Table: quality_levels
-- Description: Adaptive bitrate streaming quality tier definitions
-- ============================================
CREATE TABLE quality_levels (
    level_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Quality identifier
    name quality_level_enum NOT NULL UNIQUE,
    display_name VARCHAR(50) NOT NULL,

    -- Video resolution
    resolution_width INTEGER NOT NULL,
    resolution_height INTEGER NOT NULL,

    -- Bitrate constraints (Kbps)
    bitrate_min_kbps INTEGER NOT NULL,
    bitrate_target_kbps INTEGER NOT NULL,
    bitrate_max_kbps INTEGER NOT NULL,

    -- Codec configuration
    video_codec VARCHAR(20) NOT NULL,
    audio_codec VARCHAR(20) NOT NULL,

    -- Frame rate
    frame_rate INTEGER NOT NULL,

    -- HLS/DASH segment configuration
    segment_duration_seconds INTEGER NOT NULL DEFAULT 4,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT resolution_width_positive CHECK (resolution_width > 0 OR name = 'audio'),
    CONSTRAINT resolution_height_positive CHECK (resolution_height > 0 OR name = 'audio'),
    CONSTRAINT bitrate_min_positive CHECK (bitrate_min_kbps > 0),
    CONSTRAINT bitrate_target_positive CHECK (bitrate_target_kbps > 0),
    CONSTRAINT bitrate_max_positive CHECK (bitrate_max_kbps > 0),
    CONSTRAINT bitrate_ordering CHECK (
        bitrate_min_kbps <= bitrate_target_kbps AND
        bitrate_target_kbps <= bitrate_max_kbps
    ),
    CONSTRAINT frame_rate_positive CHECK (frame_rate > 0 OR name = 'audio'),
    CONSTRAINT segment_duration_positive CHECK (segment_duration_seconds > 0)
);

-- ============================================
-- Indexes for quality_levels table
-- ============================================
CREATE UNIQUE INDEX idx_quality_levels_name
    ON quality_levels(name);

CREATE INDEX idx_quality_levels_resolution
    ON quality_levels(resolution_width DESC, resolution_height DESC);

-- ============================================
-- Seed data: Hardcoded quality tiers
-- ============================================

-- Source quality (pass-through from broadcaster)
INSERT INTO quality_levels (
    name, display_name,
    resolution_width, resolution_height,
    bitrate_min_kbps, bitrate_target_kbps, bitrate_max_kbps,
    video_codec, audio_codec,
    frame_rate, segment_duration_seconds
) VALUES (
    'source', 'Source',
    1920, 1080,
    5000, 6000, 8000,
    'h264', 'aac',
    60, 4
);

-- 1080p Full HD
INSERT INTO quality_levels (
    name, display_name,
    resolution_width, resolution_height,
    bitrate_min_kbps, bitrate_target_kbps, bitrate_max_kbps,
    video_codec, audio_codec,
    frame_rate, segment_duration_seconds
) VALUES (
    '1080p', '1080p60',
    1920, 1080,
    4000, 5000, 6000,
    'h264', 'aac',
    60, 4
);

-- 720p HD
INSERT INTO quality_levels (
    name, display_name,
    resolution_width, resolution_height,
    bitrate_min_kbps, bitrate_target_kbps, bitrate_max_kbps,
    video_codec, audio_codec,
    frame_rate, segment_duration_seconds
) VALUES (
    '720p', '720p60',
    1280, 720,
    2000, 2500, 3500,
    'h264', 'aac',
    60, 4
);

-- 480p SD
INSERT INTO quality_levels (
    name, display_name,
    resolution_width, resolution_height,
    bitrate_min_kbps, bitrate_target_kbps, bitrate_max_kbps,
    video_codec, audio_codec,
    frame_rate, segment_duration_seconds
) VALUES (
    '480p', '480p30',
    854, 480,
    800, 1000, 1500,
    'h264', 'aac',
    30, 4
);

-- 360p Low
INSERT INTO quality_levels (
    name, display_name,
    resolution_width, resolution_height,
    bitrate_min_kbps, bitrate_target_kbps, bitrate_max_kbps,
    video_codec, audio_codec,
    frame_rate, segment_duration_seconds
) VALUES (
    '360p', '360p30',
    640, 360,
    400, 600, 900,
    'h264', 'aac',
    30, 4
);

-- Audio-only fallback
INSERT INTO quality_levels (
    name, display_name,
    resolution_width, resolution_height,
    bitrate_min_kbps, bitrate_target_kbps, bitrate_max_kbps,
    video_codec, audio_codec,
    frame_rate, segment_duration_seconds
) VALUES (
    'audio', 'Audio Only',
    0, 0,
    96, 128, 160,
    'none', 'aac',
    0, 4
);

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE quality_levels IS 'Predefined adaptive bitrate streaming quality tiers';
COMMENT ON COLUMN quality_levels.level_id IS 'Unique identifier for quality tier';
COMMENT ON COLUMN quality_levels.name IS 'Internal quality level identifier (matches quality_level_enum)';
COMMENT ON COLUMN quality_levels.display_name IS 'User-facing quality name (e.g., "1080p60")';
COMMENT ON COLUMN quality_levels.resolution_width IS 'Video width in pixels';
COMMENT ON COLUMN quality_levels.resolution_height IS 'Video height in pixels';
COMMENT ON COLUMN quality_levels.bitrate_min_kbps IS 'Minimum bitrate for ABR (Kbps)';
COMMENT ON COLUMN quality_levels.bitrate_target_kbps IS 'Target bitrate for encoding (Kbps)';
COMMENT ON COLUMN quality_levels.bitrate_max_kbps IS 'Maximum bitrate for ABR (Kbps)';
COMMENT ON COLUMN quality_levels.video_codec IS 'Video codec identifier (e.g., "h264", "av1")';
COMMENT ON COLUMN quality_levels.audio_codec IS 'Audio codec identifier (e.g., "aac", "opus")';
COMMENT ON COLUMN quality_levels.frame_rate IS 'Target frame rate (fps)';
COMMENT ON COLUMN quality_levels.segment_duration_seconds IS 'HLS/DASH segment length (seconds)';
