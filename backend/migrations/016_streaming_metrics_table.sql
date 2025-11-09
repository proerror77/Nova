-- ============================================
-- Migration: 016_streaming_metrics_table
-- Description: Create stream_metrics table with time-series partitioning
-- Author: Nova Team
-- Date: 2025-01-20
-- ============================================

-- ============================================
-- Table: stream_metrics (Partitioned)
-- Description: Time-series metrics for stream health monitoring
-- ============================================
CREATE TABLE stream_metrics (
    metrics_id UUID DEFAULT uuid_generate_v4(),
    stream_id UUID NOT NULL REFERENCES streams(stream_id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Viewer metrics
    concurrent_viewers INTEGER NOT NULL,

    -- Bandwidth metrics
    ingress_bitrate_mbps NUMERIC(8,2) NOT NULL,
    egress_bitrate_mbps NUMERIC(10,2) NOT NULL,

    -- Quality distribution (percentage of viewers per quality level)
    quality_distribution JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Stream health indicators
    dropped_frames INTEGER NOT NULL DEFAULT 0,
    buffering_events INTEGER NOT NULL DEFAULT 0,
    average_buffer_time_ms INTEGER NOT NULL DEFAULT 0,

    -- Encoder metrics
    cpu_usage_percent NUMERIC(5,2),
    memory_usage_mb INTEGER,
    encoder_preset VARCHAR(20),

    -- Constraints
    CONSTRAINT concurrent_viewers_non_negative CHECK (concurrent_viewers >= 0),
    CONSTRAINT ingress_bitrate_non_negative CHECK (ingress_bitrate_mbps >= 0),
    CONSTRAINT egress_bitrate_non_negative CHECK (egress_bitrate_mbps >= 0),
    CONSTRAINT dropped_frames_non_negative CHECK (dropped_frames >= 0),
    CONSTRAINT buffering_events_non_negative CHECK (buffering_events >= 0),
    CONSTRAINT average_buffer_time_non_negative CHECK (average_buffer_time_ms >= 0),
    CONSTRAINT quality_distribution_is_object CHECK (jsonb_typeof(quality_distribution) = 'object'),

    -- Composite primary key for partitioning
    PRIMARY KEY (timestamp, metrics_id)
) PARTITION BY RANGE (timestamp);

-- ============================================
-- Create partitions for stream_metrics
-- Description: Monthly partitions for 6 months (extend as needed)
-- ============================================

-- January 2025
CREATE TABLE stream_metrics_2025_01 PARTITION OF stream_metrics
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- February 2025
CREATE TABLE stream_metrics_2025_02 PARTITION OF stream_metrics
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- March 2025
CREATE TABLE stream_metrics_2025_03 PARTITION OF stream_metrics
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');

-- April 2025
CREATE TABLE stream_metrics_2025_04 PARTITION OF stream_metrics
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');

-- May 2025
CREATE TABLE stream_metrics_2025_05 PARTITION OF stream_metrics
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');

-- June 2025
CREATE TABLE stream_metrics_2025_06 PARTITION OF stream_metrics
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');

-- ============================================
-- Indexes for stream_metrics table
-- ============================================
-- Query recent metrics for a specific stream (time-series analysis)
CREATE INDEX idx_stream_metrics_stream_timestamp
    ON stream_metrics(stream_id, timestamp DESC);

-- Query metrics by timestamp (monitoring dashboards)
CREATE INDEX idx_stream_metrics_timestamp
    ON stream_metrics(timestamp DESC);

-- Query streams with health issues
CREATE INDEX idx_stream_metrics_health
    ON stream_metrics(stream_id, timestamp DESC)
    WHERE dropped_frames > 100 OR buffering_events > 50;

-- Analyze quality distribution
CREATE INDEX idx_stream_metrics_quality_distribution_gin
    ON stream_metrics USING gin(quality_distribution);

-- ============================================
-- Maintenance function: Create future partitions
-- ============================================
CREATE OR REPLACE FUNCTION create_next_stream_metrics_partition()
RETURNS void AS $$
DECLARE
    next_month_start DATE;
    next_month_end DATE;
    partition_name TEXT;
BEGIN
    -- Calculate next month's boundaries
    next_month_start := DATE_TRUNC('month', NOW() + INTERVAL '1 month');
    next_month_end := next_month_start + INTERVAL '1 month';

    -- Generate partition name (e.g., stream_metrics_2025_07)
    partition_name := 'stream_metrics_' || TO_CHAR(next_month_start, 'YYYY_MM');

    -- Create partition if not exists
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF stream_metrics FOR VALUES FROM (%L) TO (%L)',
        partition_name,
        next_month_start,
        next_month_end
    );

    RAISE NOTICE 'Created partition: %', partition_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION create_next_stream_metrics_partition() IS 'Automatically create next month partition for stream_metrics';

-- ============================================
-- Comments for documentation
-- ============================================
COMMENT ON TABLE stream_metrics IS 'Time-series metrics for stream health monitoring (partitioned by month)';
COMMENT ON COLUMN stream_metrics.metrics_id IS 'Unique identifier for each metrics snapshot';
COMMENT ON COLUMN stream_metrics.stream_id IS 'Stream being monitored';
COMMENT ON COLUMN stream_metrics.timestamp IS 'When these metrics were captured (30-second intervals)';
COMMENT ON COLUMN stream_metrics.concurrent_viewers IS 'Number of active viewers at this timestamp';
COMMENT ON COLUMN stream_metrics.ingress_bitrate_mbps IS 'RTMP ingest bitrate from broadcaster (Mbps)';
COMMENT ON COLUMN stream_metrics.egress_bitrate_mbps IS 'Total egress bitrate to all viewers (Mbps)';
COMMENT ON COLUMN stream_metrics.quality_distribution IS 'JSON object: {"1080p": 45, "720p": 35, "480p": 20} (percentage)';
COMMENT ON COLUMN stream_metrics.dropped_frames IS 'Frames dropped by encoder in this interval';
COMMENT ON COLUMN stream_metrics.buffering_events IS 'Aggregate buffering events across all viewers';
COMMENT ON COLUMN stream_metrics.average_buffer_time_ms IS 'Average buffering duration per event (ms)';
COMMENT ON COLUMN stream_metrics.cpu_usage_percent IS 'Transcoder CPU utilization percentage';
COMMENT ON COLUMN stream_metrics.memory_usage_mb IS 'Transcoder memory consumption (MB)';
COMMENT ON COLUMN stream_metrics.encoder_preset IS 'FFmpeg preset used (e.g., "veryfast", "medium")';
