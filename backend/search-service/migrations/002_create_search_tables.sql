-- Migration: Create search-related tables for event tracking and suggestions
-- Purpose: Store search event logs and precomputed suggestions

-- Table: search_event_logs
-- Purpose: Local event tracking for search queries (backup to ClickHouse)
CREATE TABLE IF NOT EXISTS search_event_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    query TEXT NOT NULL,
    results_count INTEGER NOT NULL DEFAULT 0,
    clicked_type VARCHAR(50), -- 'post', 'user', 'hashtag', null
    clicked_id UUID,
    session_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    INDEX idx_search_user (user_id),
    INDEX idx_search_query (query),
    INDEX idx_search_created (created_at DESC)
);

-- Table: search_suggestions
-- Purpose: Precomputed search suggestions for autocomplete
CREATE TABLE IF NOT EXISTS search_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_prefix VARCHAR(100) NOT NULL,
    suggestion TEXT NOT NULL,
    suggestion_type VARCHAR(20) NOT NULL, -- 'query', 'user', 'hashtag'
    popularity_score INTEGER NOT NULL DEFAULT 0,
    last_used_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (query_prefix, suggestion, suggestion_type)
);

CREATE INDEX idx_suggestions_prefix ON search_suggestions (query_prefix);
CREATE INDEX idx_suggestions_popularity ON search_suggestions (popularity_score DESC);

-- Table: trending_queries (cache table)
-- Purpose: Cache trending searches to reduce ClickHouse queries
CREATE TABLE IF NOT EXISTS trending_queries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query TEXT NOT NULL,
    search_count INTEGER NOT NULL DEFAULT 0,
    trend_score FLOAT NOT NULL DEFAULT 0,
    time_window VARCHAR(10) NOT NULL, -- '1h', '24h', '7d'
    cached_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (query, time_window)
);

CREATE INDEX idx_trending_time_window ON trending_queries (time_window, trend_score DESC);
CREATE INDEX idx_trending_cached ON trending_queries (cached_at DESC);

-- Add comments for documentation
COMMENT ON TABLE search_event_logs IS 'Local backup of search events (primary storage in ClickHouse)';
COMMENT ON TABLE search_suggestions IS 'Precomputed autocomplete suggestions';
COMMENT ON TABLE trending_queries IS 'Cached trending search queries from ClickHouse';

COMMENT ON COLUMN search_event_logs.clicked_type IS 'Type of result clicked: post, user, hashtag, or null if no click';
COMMENT ON COLUMN search_suggestions.query_prefix IS 'Prefix for autocomplete matching (max 100 chars)';
COMMENT ON COLUMN trending_queries.time_window IS 'Time window for trending calculation: 1h, 24h, or 7d';
