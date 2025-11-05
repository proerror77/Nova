-- Migration: Trending/Discovery System (重新编号从031)
-- Description: Real-time trending content discovery with time-decay algorithm
-- Author: System
-- Date: 2025-10-25
-- Note: 此迁移已从031_trending_system.sql重新编号以解决编号冲突

-- ============================================================================
-- Table: engagement_events
-- Purpose: Record all user engagement events for trending calculation
-- ============================================================================
CREATE TABLE IF NOT EXISTS engagement_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_id UUID NOT NULL,
    content_type VARCHAR(20) NOT NULL CHECK (content_type IN ('video', 'post', 'stream')),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type VARCHAR(20) NOT NULL CHECK (event_type IN ('view', 'like', 'share', 'comment')),
    weight NUMERIC(5,2) NOT NULL DEFAULT 1.0,  -- view=1, like=5, share=10, comment=3
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Metadata for analytics
    session_id VARCHAR(100),
    ip_address INET,
    user_agent TEXT,

    -- Prevent duplicate events within short time window (1 minute)
    UNIQUE (content_id, user_id, event_type, created_at)
);

-- Indexes for high-performance queries
CREATE INDEX idx_engagement_events_content_time
    ON engagement_events(content_id, created_at DESC);

CREATE INDEX idx_engagement_events_created_at
    ON engagement_events(created_at DESC);

CREATE INDEX idx_engagement_events_content_type_time
    ON engagement_events(content_type, created_at DESC);

CREATE INDEX idx_engagement_events_user_id
    ON engagement_events(user_id);

-- ============================================================================
-- Table: trending_scores
-- Purpose: Materialized view of trending content scores
-- ============================================================================
CREATE TABLE IF NOT EXISTS trending_scores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_id UUID NOT NULL,
    content_type VARCHAR(20) NOT NULL CHECK (content_type IN ('video', 'post', 'stream')),
    category VARCHAR(50),  -- 'entertainment', 'news', 'sports', etc.
    time_window VARCHAR(10) NOT NULL CHECK (time_window IN ('1h', '24h', '7d', 'all')),
    score NUMERIC(15,4) NOT NULL DEFAULT 0,

    -- Engagement metrics (for display)
    views_count INTEGER NOT NULL DEFAULT 0,
    likes_count INTEGER NOT NULL DEFAULT 0,
    shares_count INTEGER NOT NULL DEFAULT 0,
    comments_count INTEGER NOT NULL DEFAULT 0,

    -- Metadata
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rank INTEGER,

    -- Ensure unique entry per content+window+category
    UNIQUE (content_id, time_window, category)
);

-- High-performance indexes for trending queries
CREATE INDEX idx_trending_scores_category_window_score
    ON trending_scores(category, time_window, score DESC);

CREATE INDEX idx_trending_scores_time_window_score
    ON trending_scores(time_window, score DESC);

CREATE INDEX idx_trending_scores_content_type_score
    ON trending_scores(content_type, score DESC);

CREATE INDEX idx_trending_scores_computed_at
    ON trending_scores(computed_at DESC);

-- ============================================================================
-- Table: trending_metadata
-- Purpose: Track trending computation metadata and cache
-- ============================================================================
CREATE TABLE IF NOT EXISTS trending_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    content_type VARCHAR(20) NOT NULL CHECK (content_type IN ('video', 'post', 'stream')),
    category VARCHAR(50),
    time_window VARCHAR(10) NOT NULL CHECK (time_window IN ('1h', '24h', '7d', 'all')),
    last_computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Cached trending list (top 100 items)
    data JSONB,

    -- Metadata
    item_count INTEGER DEFAULT 0,
    computation_duration_ms INTEGER,

    UNIQUE (content_type, time_window, category)
);

CREATE INDEX idx_trending_metadata_last_computed
    ON trending_metadata(last_computed_at DESC);

-- ============================================================================
-- View: trending_global
-- Purpose: Global trending across all content types
-- ============================================================================
CREATE OR REPLACE VIEW trending_global AS
SELECT
    ts.content_id,
    ts.content_type,
    ts.category,
    ts.time_window,
    ts.score,
    ts.views_count,
    ts.likes_count,
    ts.shares_count,
    ts.comments_count,
    ts.rank,
    ts.computed_at
FROM trending_scores ts
WHERE ts.category IS NULL  -- Global trending (no category filter)
ORDER BY ts.time_window, ts.score DESC;

-- ============================================================================
-- Function: compute_trending_score
-- Purpose: Calculate time-decay score for a content item
-- Algorithm: score = Σ(weight × e^(-λ × age_hours))
-- ============================================================================
CREATE OR REPLACE FUNCTION compute_trending_score(
    p_content_id UUID,
    p_time_window VARCHAR(10),
    p_decay_rate NUMERIC DEFAULT 0.1
)
RETURNS NUMERIC AS $$
DECLARE
    v_score NUMERIC := 0;
    v_hours_cutoff INTEGER;
BEGIN
    -- Determine time cutoff based on window
    v_hours_cutoff := CASE p_time_window
        WHEN '1h' THEN 1
        WHEN '24h' THEN 24
        WHEN '7d' THEN 168  -- 7 * 24
        ELSE 999999  -- 'all' window
    END;

    -- Calculate time-decay score
    -- Formula: score = Σ(weight × e^(-λ × age_hours))
    SELECT COALESCE(SUM(
        weight * EXP(-p_decay_rate * EXTRACT(EPOCH FROM (NOW() - created_at)) / 3600)
    ), 0)
    INTO v_score
    FROM engagement_events
    WHERE content_id = p_content_id
        AND created_at >= NOW() - INTERVAL '1 hour' * v_hours_cutoff;

    RETURN v_score;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- Function: refresh_trending_scores
-- Purpose: Refresh trending scores for all content in a time window
-- ============================================================================
CREATE OR REPLACE FUNCTION refresh_trending_scores(
    p_time_window VARCHAR(10),
    p_category VARCHAR(50) DEFAULT NULL,
    p_limit INTEGER DEFAULT 100
)
RETURNS INTEGER AS $$
DECLARE
    v_updated INTEGER := 0;
    v_hours_cutoff INTEGER;
    v_start_time TIMESTAMPTZ;
BEGIN
    v_start_time := NOW();

    -- Determine time cutoff
    v_hours_cutoff := CASE p_time_window
        WHEN '1h' THEN 1
        WHEN '24h' THEN 24
        WHEN '7d' THEN 168
        ELSE 999999
    END;

    -- Delete old scores for this window/category
    DELETE FROM trending_scores
    WHERE time_window = p_time_window
        AND (p_category IS NULL OR category = p_category);

    -- Insert new trending scores
    WITH recent_events AS (
        SELECT
            ee.content_id,
            ee.content_type,
            SUM(ee.weight * EXP(-0.1 * EXTRACT(EPOCH FROM (NOW() - ee.created_at)) / 3600)) as score,
            COUNT(*) FILTER (WHERE ee.event_type = 'view') as views,
            COUNT(*) FILTER (WHERE ee.event_type = 'like') as likes,
            COUNT(*) FILTER (WHERE ee.event_type = 'share') as shares,
            COUNT(*) FILTER (WHERE ee.event_type = 'comment') as comments
        FROM engagement_events ee
        WHERE ee.created_at >= NOW() - INTERVAL '1 hour' * v_hours_cutoff
        GROUP BY ee.content_id, ee.content_type
        HAVING SUM(ee.weight) > 0  -- Filter out zero-engagement content
    ),
    ranked_content AS (
        SELECT
            re.*,
            ROW_NUMBER() OVER (ORDER BY re.score DESC) as rank
        FROM recent_events re
        ORDER BY re.score DESC
        LIMIT p_limit
    )
    INSERT INTO trending_scores (
        content_id, content_type, category, time_window, score,
        views_count, likes_count, shares_count, comments_count,
        rank, computed_at
    )
    SELECT
        rc.content_id,
        rc.content_type,
        p_category,
        p_time_window,
        rc.score,
        rc.views::INTEGER,
        rc.likes::INTEGER,
        rc.shares::INTEGER,
        rc.comments::INTEGER,
        rc.rank::INTEGER,
        v_start_time
    FROM ranked_content rc;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    -- Update metadata
    INSERT INTO trending_metadata (
        content_type, category, time_window, last_computed_at,
        item_count, computation_duration_ms
    )
    VALUES (
        'all',  -- Mixed content types
        p_category,
        p_time_window,
        v_start_time,
        v_updated,
        EXTRACT(MILLISECONDS FROM (NOW() - v_start_time))::INTEGER
    )
    ON CONFLICT (content_type, time_window, category)
    DO UPDATE SET
        last_computed_at = v_start_time,
        item_count = v_updated,
        computation_duration_ms = EXTRACT(MILLISECONDS FROM (NOW() - v_start_time))::INTEGER;

    RETURN v_updated;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function: record_engagement
-- Purpose: Record user engagement event with deduplication
-- ============================================================================
CREATE OR REPLACE FUNCTION record_engagement(
    p_content_id UUID,
    p_content_type VARCHAR(20),
    p_user_id UUID,
    p_event_type VARCHAR(20),
    p_session_id VARCHAR(100) DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_event_id UUID;
    v_weight NUMERIC;
BEGIN
    -- Assign weight based on event type
    v_weight := CASE p_event_type
        WHEN 'view' THEN 1.0
        WHEN 'like' THEN 5.0
        WHEN 'share' THEN 10.0
        WHEN 'comment' THEN 3.0
        ELSE 1.0
    END;

    -- Insert event (deduplication by UNIQUE constraint)
    INSERT INTO engagement_events (
        content_id, content_type, user_id, event_type, weight,
        session_id, ip_address, user_agent, created_at
    )
    VALUES (
        p_content_id, p_content_type, p_user_id, p_event_type, v_weight,
        p_session_id, p_ip_address, p_user_agent, NOW()
    )
    ON CONFLICT (content_id, user_id, event_type, created_at) DO NOTHING
    RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$ LANGUAGE plpgsql;
