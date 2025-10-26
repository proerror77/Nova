-- Migration: Search Suggestions and History
-- Purpose: Support search autocomplete, trending searches, and personalized suggestions
-- Created: 2025-10-26

-- Up: Create search suggestions tables

-- Track search queries for autocomplete and trending
CREATE TABLE IF NOT EXISTS search_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    query_type VARCHAR(50) NOT NULL, -- 'user', 'post', 'hashtag', 'video', 'stream'
    query_text VARCHAR(500) NOT NULL,
    result_count INT DEFAULT 0,
    searched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    clicked_result_id UUID, -- Which result user clicked (if any)
    clicked_at TIMESTAMPTZ -- When user clicked
);

-- Index for user's search history
CREATE INDEX IF NOT EXISTS idx_search_history_user_time
ON search_history(user_id, searched_at DESC);

-- Index for trending queries (global)
CREATE INDEX IF NOT EXISTS idx_search_history_query_time
ON search_history(query_type, query_text, searched_at DESC)
WHERE searched_at > NOW() - INTERVAL '30 days';

-- Popular/trending searches
CREATE TABLE IF NOT EXISTS trending_searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_type VARCHAR(50) NOT NULL,
    query_text VARCHAR(500) NOT NULL,
    search_count INT NOT NULL DEFAULT 1,
    trending_score FLOAT NOT NULL DEFAULT 0.0, -- Calculated by job
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(query_type, query_text)
);

-- Index for fetching trending searches
CREATE INDEX IF NOT EXISTS idx_trending_searches_score
ON trending_searches(query_type, trending_score DESC, last_updated_at DESC);

-- Search suggestions (pre-computed for fast autocomplete)
-- Generated from trending_searches + user's own history
CREATE TABLE IF NOT EXISTS search_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE, -- NULL = global suggestions
    query_type VARCHAR(50) NOT NULL,
    suggestion_text VARCHAR(500) NOT NULL,
    suggestion_type VARCHAR(50) NOT NULL, -- 'trending', 'recent', 'personalized'
    relevance_score FLOAT NOT NULL DEFAULT 0.0,
    position INT NOT NULL, -- For ordering in autocomplete
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL, -- Cache expiry
    UNIQUE(user_id, query_type, suggestion_text, suggestion_type)
);

-- Index for fast suggestion lookup
CREATE INDEX IF NOT EXISTS idx_search_suggestions_user_type
ON search_suggestions(user_id, query_type, created_at DESC)
WHERE expires_at > NOW();

-- Create composite index for autocomplete queries
CREATE INDEX IF NOT EXISTS idx_suggestions_autocomplete
ON search_suggestions(query_type, suggestion_text, relevance_score DESC)
WHERE user_id IS NULL AND expires_at > NOW();

-- Table to track popular search results (for relevance ranking)
CREATE TABLE IF NOT EXISTS popular_search_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_type VARCHAR(50) NOT NULL,
    query_hash VARCHAR(64) NOT NULL, -- Hash of query_text
    result_id UUID NOT NULL, -- ID of the result (user_id, post_id, etc)
    click_count INT NOT NULL DEFAULT 0,
    impression_count INT NOT NULL DEFAULT 0,
    ctr FLOAT NOT NULL DEFAULT 0.0, -- Click-through rate
    last_clicked_at TIMESTAMPTZ,
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(query_hash, result_id)
);

-- Index for finding popular results
CREATE INDEX IF NOT EXISTS idx_popular_results_query
ON popular_search_results(query_hash, click_count DESC);

-- Down: Drop all search suggestion tables

-- DROP TABLE IF EXISTS popular_search_results CASCADE;
-- DROP TABLE IF EXISTS search_suggestions CASCADE;
-- DROP TABLE IF EXISTS trending_searches CASCADE;
-- DROP TABLE IF EXISTS search_history CASCADE;
