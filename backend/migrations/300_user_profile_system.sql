-- ============================================
-- User Profile System Migration
-- TikTok-style recommendation enhancement
-- ============================================

-- Enable UUID extension if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 1. User Demographic Profiles (用户画像 - 人口统计)
-- ============================================
-- Stores inferred user demographics from device/IP
-- Updated by user-profile-service background job

CREATE TABLE IF NOT EXISTS user_demographic_profiles (
    user_id UUID PRIMARY KEY,
    -- Inferred from IP geolocation
    country_code CHAR(2),
    region VARCHAR(100),
    city VARCHAR(100),
    timezone VARCHAR(50),
    -- Inferred from device
    device_type VARCHAR(50), -- 'iOS', 'Android', 'Web', 'iPad', 'Tablet'
    device_model VARCHAR(100),
    os_version VARCHAR(50),
    app_version VARCHAR(50),
    -- Language preference (from device locale)
    language_preference VARCHAR(10) DEFAULT 'en',
    -- Timestamps
    first_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_demographic_country ON user_demographic_profiles(country_code);
CREATE INDEX idx_user_demographic_device ON user_demographic_profiles(device_type);

-- ============================================
-- 2. User Behavior Patterns (用户行为模式)
-- ============================================
-- Computed daily from engagement data
-- Used for personalization and cold-start

CREATE TABLE IF NOT EXISTS user_behavior_patterns (
    user_id UUID PRIMARY KEY,
    -- Active hours (24-bit bitmap: bit 0 = 00:00-01:00, etc.)
    active_hours_bitmap BIGINT DEFAULT 0,
    -- Peak active hour (0-23)
    peak_active_hour SMALLINT,
    -- Session metrics
    avg_session_length_seconds INTEGER DEFAULT 0,
    avg_sessions_per_day REAL DEFAULT 0.0,
    avg_scroll_speed_pps REAL DEFAULT 0.0, -- pixels per second
    -- Content preferences
    preferred_video_length VARCHAR(20) DEFAULT 'medium', -- 'short_0-15s', 'medium_15-60s', 'long_60s+'
    preferred_content_types TEXT[] DEFAULT '{}', -- ['video', 'image', 'text', 'live']
    audio_preference VARCHAR(20) DEFAULT 'mixed', -- 'music', 'voice', 'silent', 'mixed'
    -- Engagement metrics
    overall_engagement_rate REAL DEFAULT 0.0, -- (likes+comments+shares) / impressions
    avg_watch_completion_rate REAL DEFAULT 0.5,
    like_rate REAL DEFAULT 0.0,
    comment_rate REAL DEFAULT 0.0,
    share_rate REAL DEFAULT 0.0,
    -- Retention
    days_since_first_activity INTEGER DEFAULT 0,
    days_active_last_30 INTEGER DEFAULT 0,
    -- Computation metadata
    sample_size INTEGER DEFAULT 0, -- number of events used
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_behavior_engagement ON user_behavior_patterns(overall_engagement_rate DESC);
CREATE INDEX idx_user_behavior_computed ON user_behavior_patterns(computed_at);

-- ============================================
-- 3. User Interest Tags (用户兴趣标签)
-- ============================================
-- Auto-generated from engagement history with time decay
-- Core of content-based personalization

CREATE TABLE IF NOT EXISTS user_interest_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    tag VARCHAR(100) NOT NULL,
    -- Weight: 0.0 to 1.0, normalized within user
    weight REAL NOT NULL DEFAULT 1.0 CHECK (weight >= 0.0 AND weight <= 10.0),
    -- Source of interest inference
    source VARCHAR(50) NOT NULL DEFAULT 'implicit', -- 'explicit', 'implicit_like', 'implicit_watch', 'implicit_follow', 'implicit_search'
    -- Decay parameters
    decay_rate REAL DEFAULT 0.95 CHECK (decay_rate > 0.0 AND decay_rate <= 1.0), -- daily decay multiplier
    -- Interaction tracking
    interaction_count INTEGER DEFAULT 1,
    last_interaction_at TIMESTAMPTZ DEFAULT NOW(),
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_user_tag UNIQUE (user_id, tag)
);

CREATE INDEX idx_user_interest_user_weight ON user_interest_tags(user_id, weight DESC);
CREATE INDEX idx_user_interest_tag ON user_interest_tags(tag);
CREATE INDEX idx_user_interest_last_interaction ON user_interest_tags(last_interaction_at);

-- ============================================
-- 4. User Social Features (社交图谱特征)
-- ============================================
-- Computed from social graph for ranking

CREATE TABLE IF NOT EXISTS user_social_features (
    user_id UUID PRIMARY KEY,
    -- Counts (denormalized for fast access)
    following_count INTEGER DEFAULT 0,
    follower_count INTEGER DEFAULT 0,
    mutual_follow_count INTEGER DEFAULT 0,
    -- Interaction patterns
    avg_interactions_per_followee REAL DEFAULT 0.0, -- how much user engages with followees
    followee_diversity_score REAL DEFAULT 0.5, -- diversity of followed accounts
    -- Creator metrics (if user creates content)
    is_creator BOOLEAN DEFAULT FALSE,
    creator_score REAL DEFAULT 0.0 CHECK (creator_score >= 0.0 AND creator_score <= 1.0),
    avg_post_engagement_rate REAL DEFAULT 0.0,
    total_posts INTEGER DEFAULT 0,
    -- Influencer metrics
    influencer_score REAL DEFAULT 0.0 CHECK (influencer_score >= 0.0 AND influencer_score <= 1.0),
    avg_follower_engagement_rate REAL DEFAULT 0.0,
    -- Community detection
    community_clusters TEXT[] DEFAULT '{}', -- cluster IDs user belongs to
    -- Computation metadata
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_social_creator ON user_social_features(is_creator, creator_score DESC) WHERE is_creator = TRUE;
CREATE INDEX idx_user_social_influencer ON user_social_features(influencer_score DESC);

-- ============================================
-- 5. Watch Events (观看事件 - 核心信号)
-- ============================================
-- Critical TikTok-style signal: watch duration and completion rate
-- High-volume table, partitioned by date

CREATE TABLE IF NOT EXISTS watch_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    content_id UUID NOT NULL,
    content_type VARCHAR(20) NOT NULL DEFAULT 'video', -- 'video', 'live', 'story'
    -- Duration tracking
    watch_duration_ms INTEGER NOT NULL CHECK (watch_duration_ms >= 0),
    content_duration_ms INTEGER NOT NULL CHECK (content_duration_ms > 0),
    -- Computed completion rate (stored for query efficiency)
    completion_rate REAL GENERATED ALWAYS AS (
        CASE
            WHEN content_duration_ms > 0 THEN LEAST(1.0, watch_duration_ms::REAL / content_duration_ms)
            ELSE 0.0
        END
    ) STORED,
    -- Replay detection
    is_replay BOOLEAN DEFAULT FALSE,
    replay_count SMALLINT DEFAULT 0,
    -- Session context
    session_id VARCHAR(100),
    -- Scroll behavior
    scroll_away_at_ms INTEGER, -- when user scrolled away (null if watched to end)
    -- Device context
    device_type VARCHAR(50),
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create partitions for the next 12 months
CREATE TABLE watch_events_2024_01 PARTITION OF watch_events FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE watch_events_2024_02 PARTITION OF watch_events FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE watch_events_2024_03 PARTITION OF watch_events FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
CREATE TABLE watch_events_2024_04 PARTITION OF watch_events FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE watch_events_2024_05 PARTITION OF watch_events FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE watch_events_2024_06 PARTITION OF watch_events FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
CREATE TABLE watch_events_2024_07 PARTITION OF watch_events FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
CREATE TABLE watch_events_2024_08 PARTITION OF watch_events FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
CREATE TABLE watch_events_2024_09 PARTITION OF watch_events FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
CREATE TABLE watch_events_2024_10 PARTITION OF watch_events FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
CREATE TABLE watch_events_2024_11 PARTITION OF watch_events FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
CREATE TABLE watch_events_2024_12 PARTITION OF watch_events FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
CREATE TABLE watch_events_2025_01 PARTITION OF watch_events FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE watch_events_2025_02 PARTITION OF watch_events FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE watch_events_2025_03 PARTITION OF watch_events FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE watch_events_2025_04 PARTITION OF watch_events FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE watch_events_2025_05 PARTITION OF watch_events FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE watch_events_2025_06 PARTITION OF watch_events FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE watch_events_2025_07 PARTITION OF watch_events FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE watch_events_2025_08 PARTITION OF watch_events FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE watch_events_2025_09 PARTITION OF watch_events FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE watch_events_2025_10 PARTITION OF watch_events FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE watch_events_2025_11 PARTITION OF watch_events FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE watch_events_2025_12 PARTITION OF watch_events FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE INDEX idx_watch_events_user_time ON watch_events(user_id, created_at DESC);
CREATE INDEX idx_watch_events_content ON watch_events(content_id, created_at DESC);
CREATE INDEX idx_watch_events_session ON watch_events(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_watch_events_completion ON watch_events(completion_rate DESC);

-- ============================================
-- 6. Author Quality Scores (作者质量分数)
-- ============================================
-- Computed from historical engagement on author's content
-- Used in ranking to boost high-quality creators

CREATE TABLE IF NOT EXISTS author_quality_scores (
    author_id UUID PRIMARY KEY,
    -- Engagement metrics
    avg_completion_rate REAL DEFAULT 0.5 CHECK (avg_completion_rate >= 0.0 AND avg_completion_rate <= 1.0),
    avg_engagement_rate REAL DEFAULT 0.0 CHECK (avg_engagement_rate >= 0.0),
    avg_like_rate REAL DEFAULT 0.0,
    avg_comment_rate REAL DEFAULT 0.0,
    avg_share_rate REAL DEFAULT 0.0,
    -- Content quality
    content_consistency_score REAL DEFAULT 0.5, -- posting regularity
    content_quality_avg REAL DEFAULT 0.5,
    -- Audience metrics
    audience_retention_score REAL DEFAULT 0.5, -- how well they retain viewers
    audience_growth_rate REAL DEFAULT 0.0,
    -- Trust & safety
    violation_count INTEGER DEFAULT 0,
    is_verified BOOLEAN DEFAULT FALSE,
    -- Overall score (weighted combination)
    overall_quality_score REAL DEFAULT 0.5 CHECK (overall_quality_score >= 0.0 AND overall_quality_score <= 1.0),
    -- Stats
    total_posts INTEGER DEFAULT 0,
    total_views BIGINT DEFAULT 0,
    -- Computation metadata
    sample_size INTEGER DEFAULT 0,
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_author_quality_overall ON author_quality_scores(overall_quality_score DESC);
CREATE INDEX idx_author_quality_computed ON author_quality_scores(computed_at);

-- ============================================
-- 7. Content Quality Scores (内容质量分数)
-- ============================================
-- Per-content quality metrics for ranking

CREATE TABLE IF NOT EXISTS content_quality_scores (
    content_id UUID PRIMARY KEY,
    content_type VARCHAR(20) NOT NULL DEFAULT 'video',
    author_id UUID,
    -- Engagement-based scores
    completion_rate_score REAL DEFAULT 0.5 CHECK (completion_rate_score >= 0.0 AND completion_rate_score <= 1.0),
    engagement_rate_score REAL DEFAULT 0.5 CHECK (engagement_rate_score >= 0.0 AND engagement_rate_score <= 1.0),
    like_rate_score REAL DEFAULT 0.5,
    comment_rate_score REAL DEFAULT 0.5,
    share_rate_score REAL DEFAULT 0.5,
    -- Technical quality (from content analysis)
    technical_quality_score REAL DEFAULT 0.5, -- video/image quality
    audio_quality_score REAL DEFAULT 0.5,
    -- Virality
    virality_score REAL DEFAULT 0.0, -- share/view ratio boosted
    viral_velocity REAL DEFAULT 0.0, -- rate of engagement growth
    -- Freshness (time decay applied)
    freshness_score REAL DEFAULT 1.0 CHECK (freshness_score >= 0.0 AND freshness_score <= 1.0),
    -- Overall score (weighted combination)
    overall_quality_score REAL DEFAULT 0.5 CHECK (overall_quality_score >= 0.0 AND overall_quality_score <= 1.0),
    -- Stats
    total_impressions BIGINT DEFAULT 0,
    total_engagements BIGINT DEFAULT 0,
    -- Computation metadata
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_content_quality_overall ON content_quality_scores(overall_quality_score DESC);
CREATE INDEX idx_content_quality_author ON content_quality_scores(author_id);
CREATE INDEX idx_content_quality_freshness ON content_quality_scores(freshness_score DESC);

-- ============================================
-- 8. New Content Exploration Pool (新内容探索池)
-- ============================================
-- UCB-based exploration for new content discovery
-- Content graduates after reaching impression threshold

CREATE TABLE IF NOT EXISTS new_content_pool (
    content_id UUID PRIMARY KEY,
    content_type VARCHAR(20) NOT NULL DEFAULT 'video',
    author_id UUID NOT NULL,
    -- Upload time for freshness
    upload_time TIMESTAMPTZ NOT NULL,
    -- Exploration statistics
    exploration_impressions INTEGER DEFAULT 0,
    exploration_engagements INTEGER DEFAULT 0,
    exploration_completions INTEGER DEFAULT 0,
    -- UCB score (updated after each impression)
    exploration_score REAL DEFAULT 0.5,
    ucb_score REAL DEFAULT 1000.0, -- High initial score for exploration
    -- Graduation
    graduation_threshold INTEGER DEFAULT 1000, -- impressions before graduation
    graduated_at TIMESTAMPTZ, -- null means still in pool
    graduation_reason VARCHAR(50), -- 'threshold_reached', 'performance_poor', 'manual'
    -- Pool status
    is_active BOOLEAN DEFAULT TRUE,
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_new_content_pool_active ON new_content_pool(is_active, ucb_score DESC) WHERE is_active = TRUE;
CREATE INDEX idx_new_content_pool_author ON new_content_pool(author_id);
CREATE INDEX idx_new_content_pool_upload ON new_content_pool(upload_time DESC);

-- ============================================
-- 9. User-Content Interaction Cache (用户-内容交互缓存)
-- ============================================
-- Fast lookup for user's recent interactions with content
-- Used to avoid re-recommending seen content

CREATE TABLE IF NOT EXISTS user_content_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    content_id UUID NOT NULL,
    -- Interaction types and weights
    interaction_type VARCHAR(30) NOT NULL, -- 'view', 'like', 'comment', 'share', 'save', 'skip', 'not_interested'
    interaction_weight REAL DEFAULT 1.0,
    -- Watch metrics (for view type)
    watch_duration_ms INTEGER,
    completion_rate REAL,
    -- Context
    session_id VARCHAR(100),
    source VARCHAR(50), -- 'feed', 'search', 'profile', 'share'
    -- Timestamp
    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_user_content_interaction UNIQUE (user_id, content_id, interaction_type)
);

CREATE INDEX idx_user_content_user_time ON user_content_interactions(user_id, created_at DESC);
CREATE INDEX idx_user_content_content ON user_content_interactions(content_id);
CREATE INDEX idx_user_content_type ON user_content_interactions(interaction_type);

-- ============================================
-- 10. Feature Cache Table (特征缓存表)
-- ============================================
-- Materialized features for fast ranking lookups

CREATE TABLE IF NOT EXISTS ranking_feature_cache (
    entity_type VARCHAR(20) NOT NULL, -- 'user', 'content', 'author'
    entity_id UUID NOT NULL,
    feature_name VARCHAR(100) NOT NULL,
    feature_value REAL NOT NULL,
    -- TTL management
    expires_at TIMESTAMPTZ,
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (entity_type, entity_id, feature_name)
);

CREATE INDEX idx_ranking_feature_cache_expires ON ranking_feature_cache(expires_at) WHERE expires_at IS NOT NULL;

-- ============================================
-- Trigger Functions
-- ============================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers to all tables
CREATE TRIGGER update_user_demographic_profiles_updated_at BEFORE UPDATE ON user_demographic_profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_behavior_patterns_updated_at BEFORE UPDATE ON user_behavior_patterns FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_interest_tags_updated_at BEFORE UPDATE ON user_interest_tags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_social_features_updated_at BEFORE UPDATE ON user_social_features FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_author_quality_scores_updated_at BEFORE UPDATE ON author_quality_scores FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_content_quality_scores_updated_at BEFORE UPDATE ON content_quality_scores FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_new_content_pool_updated_at BEFORE UPDATE ON new_content_pool FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_ranking_feature_cache_updated_at BEFORE UPDATE ON ranking_feature_cache FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Helper Functions
-- ============================================

-- Function to update UCB score for new content
CREATE OR REPLACE FUNCTION update_ucb_score(
    p_content_id UUID,
    p_is_engagement BOOLEAN DEFAULT FALSE
)
RETURNS VOID AS $$
DECLARE
    v_impressions INTEGER;
    v_engagements INTEGER;
    v_total_impressions INTEGER;
    v_exploit REAL;
    v_explore REAL;
    v_ucb REAL;
    v_exploration_constant REAL := 1.414; -- sqrt(2)
BEGIN
    -- Get current stats
    SELECT exploration_impressions, exploration_engagements
    INTO v_impressions, v_engagements
    FROM new_content_pool
    WHERE content_id = p_content_id;

    -- Update counts
    IF p_is_engagement THEN
        v_engagements := v_engagements + 1;
    END IF;
    v_impressions := v_impressions + 1;

    -- Get total impressions across pool
    SELECT COALESCE(SUM(exploration_impressions), 1)
    INTO v_total_impressions
    FROM new_content_pool
    WHERE is_active = TRUE;

    -- Calculate UCB score
    IF v_impressions > 0 THEN
        v_exploit := v_engagements::REAL / v_impressions;
        v_explore := v_exploration_constant * SQRT(2.0 * LN(v_total_impressions::REAL) / v_impressions);
        v_ucb := v_exploit + v_explore;
    ELSE
        v_ucb := 1000.0; -- High score for unexplored content
    END IF;

    -- Update record
    UPDATE new_content_pool
    SET exploration_impressions = v_impressions,
        exploration_engagements = v_engagements,
        exploration_score = CASE WHEN v_impressions > 0 THEN v_engagements::REAL / v_impressions ELSE 0.5 END,
        ucb_score = v_ucb,
        updated_at = NOW()
    WHERE content_id = p_content_id;

    -- Check for graduation
    IF v_impressions >= (SELECT graduation_threshold FROM new_content_pool WHERE content_id = p_content_id) THEN
        UPDATE new_content_pool
        SET is_active = FALSE,
            graduated_at = NOW(),
            graduation_reason = 'threshold_reached'
        WHERE content_id = p_content_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to decay user interest weights daily
CREATE OR REPLACE FUNCTION decay_user_interests()
RETURNS INTEGER AS $$
DECLARE
    v_affected INTEGER;
BEGIN
    UPDATE user_interest_tags
    SET weight = weight * decay_rate,
        updated_at = NOW()
    WHERE weight > 0.01;

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    -- Remove very low weight tags
    DELETE FROM user_interest_tags WHERE weight < 0.01;

    RETURN v_affected;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Comments for documentation
-- ============================================

COMMENT ON TABLE user_demographic_profiles IS 'User demographics inferred from device/IP for personalization';
COMMENT ON TABLE user_behavior_patterns IS 'Computed daily user behavior patterns for ranking';
COMMENT ON TABLE user_interest_tags IS 'Auto-generated interest tags with time decay for content matching';
COMMENT ON TABLE user_social_features IS 'Social graph derived features for ranking';
COMMENT ON TABLE watch_events IS 'Critical watch time signal - partitioned by month';
COMMENT ON TABLE author_quality_scores IS 'Author quality metrics for ranking boost';
COMMENT ON TABLE content_quality_scores IS 'Per-content quality scores for ranking';
COMMENT ON TABLE new_content_pool IS 'UCB-based exploration pool for new content discovery';
COMMENT ON TABLE user_content_interactions IS 'User interaction history for dedup and features';
COMMENT ON TABLE ranking_feature_cache IS 'Materialized feature cache for fast ranking lookups';
