-- ============================================
-- ClickHouse Watch Events Analytics Schema
-- TikTok-style recommendation enhancement
-- ============================================

-- ============================================
-- 1. Watch Events Stream (高吞吐量观看事件)
-- ============================================
-- Primary table for watch time tracking
-- Partitioned by month, TTL 90 days

CREATE TABLE IF NOT EXISTS watch_events (
    event_time DateTime DEFAULT now(),
    user_id String,
    content_id String,
    content_type LowCardinality(String) DEFAULT 'video',
    -- Duration metrics
    watch_duration_ms UInt32,
    content_duration_ms UInt32,
    completion_rate Float32,
    -- Replay tracking
    is_replay UInt8 DEFAULT 0,
    replay_count UInt8 DEFAULT 0,
    -- Session context
    session_id String DEFAULT '',
    -- Scroll behavior
    scroll_away_at_ms Nullable(UInt32),
    -- Device context
    device_type LowCardinality(String) DEFAULT '',
    country_code LowCardinality(String) DEFAULT '',
    -- Date for partitioning
    event_date Date DEFAULT toDate(event_time)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, content_id, event_time)
TTL event_date + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 2. Session Events (会话事件)
-- ============================================
-- Track user session behavior for real-time personalization

CREATE TABLE IF NOT EXISTS session_events (
    event_time DateTime DEFAULT now(),
    user_id String,
    session_id String,
    event_type LowCardinality(String), -- 'session_start', 'session_end', 'scroll', 'pause', 'resume', 'background', 'foreground'
    content_id Nullable(String),
    -- Scroll tracking
    scroll_position UInt32 DEFAULT 0,
    scroll_velocity Float32 DEFAULT 0.0, -- pixels per second
    -- Additional context
    metadata String DEFAULT '', -- JSON for flexible data
    -- Date for partitioning
    event_date Date DEFAULT toDate(event_time)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, session_id, event_time)
TTL event_date + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 3. Session Interests (会话兴趣 - 实时)
-- ============================================
-- Real-time session interests for within-session personalization
-- Uses SummingMergeTree for efficient aggregation

CREATE TABLE IF NOT EXISTS session_interests (
    session_id String,
    user_id String,
    interest_tag LowCardinality(String),
    weight Float32,
    interaction_count UInt32 DEFAULT 1,
    last_updated DateTime DEFAULT now()
) ENGINE = SummingMergeTree((weight, interaction_count))
ORDER BY (session_id, user_id, interest_tag)
TTL last_updated + INTERVAL 24 HOUR
SETTINGS index_granularity = 8192;

-- ============================================
-- 4. User Content Interactions CDC (用户内容交互 CDC)
-- ============================================
-- Extended from existing schema for recommendation features

CREATE TABLE IF NOT EXISTS user_content_interactions_v2 (
    event_time DateTime DEFAULT now(),
    user_id String,
    content_id String,
    author_id String DEFAULT '',
    interaction_type LowCardinality(String), -- 'view', 'like', 'comment', 'share', 'save', 'skip', 'not_interested'
    interaction_weight Float32 DEFAULT 1.0,
    -- Watch metrics (for view type)
    watch_duration_ms Nullable(UInt32),
    completion_rate Nullable(Float32),
    -- Content tags for interest inference
    content_tags Array(LowCardinality(String)) DEFAULT [],
    -- Context
    session_id String DEFAULT '',
    source LowCardinality(String) DEFAULT 'feed', -- 'feed', 'search', 'profile', 'share', 'explore'
    -- Date for partitioning
    event_date Date DEFAULT toDate(event_time)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_time, content_id)
TTL event_date + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 5. Materialized Views for Aggregations
-- ============================================

-- 5.1 User-Content Watch Stats (用户-内容观看统计)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_content_watch_stats
ENGINE = AggregatingMergeTree()
ORDER BY (user_id, content_id)
AS SELECT
    user_id,
    content_id,
    avgState(completion_rate) AS avg_completion_state,
    maxState(completion_rate) AS max_completion_state,
    sumState(watch_duration_ms) AS total_watch_ms_state,
    countState() AS view_count_state,
    maxState(event_time) AS last_watched_state
FROM watch_events
GROUP BY user_id, content_id;

-- 5.2 Content Engagement Stats (内容互动统计)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_content_engagement_stats
ENGINE = AggregatingMergeTree()
ORDER BY (content_id, event_date)
AS SELECT
    content_id,
    event_date,
    avgState(completion_rate) AS avg_completion_state,
    countState() AS view_count_state,
    sumStateIf(toUInt64(1), is_replay = 1) AS replay_count_state,
    avgState(watch_duration_ms) AS avg_watch_duration_state
FROM watch_events
GROUP BY content_id, event_date;

-- 5.3 Daily User Behavior Aggregates (每日用户行为聚合)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_user_behavior
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_date)
AS SELECT
    user_id,
    event_date,
    countState() AS event_count_state,
    avgState(completion_rate) AS avg_completion_state,
    sumState(watch_duration_ms) AS total_watch_ms_state,
    uniqState(content_id) AS unique_content_state,
    uniqState(session_id) AS session_count_state,
    groupArrayState(toHour(event_time)) AS active_hours_state
FROM watch_events
GROUP BY user_id, event_date;

-- 5.4 Hourly User Activity (每小时用户活跃度)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_hourly_user_activity
ENGINE = SummingMergeTree()
ORDER BY (user_id, event_hour)
AS SELECT
    user_id,
    toStartOfHour(event_time) AS event_hour,
    count() AS activity_count,
    sum(watch_duration_ms) AS total_watch_ms
FROM watch_events
GROUP BY user_id, event_hour;

-- 5.5 User Interest Aggregation (用户兴趣聚合)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_interest_aggregate
ENGINE = SummingMergeTree()
ORDER BY (user_id, interest_tag)
AS SELECT
    user_id,
    arrayJoin(content_tags) AS interest_tag,
    sumIf(interaction_weight, interaction_type = 'like') AS like_weight,
    sumIf(interaction_weight, interaction_type = 'comment') AS comment_weight,
    sumIf(interaction_weight, interaction_type = 'share') AS share_weight,
    sumIf(toFloat32(completion_rate), interaction_type = 'view' AND completion_rate >= 0.8) AS complete_watch_weight,
    count() AS interaction_count,
    max(event_time) AS last_interaction
FROM user_content_interactions_v2
WHERE length(content_tags) > 0
GROUP BY user_id, interest_tag;

-- 5.6 Author Performance Stats (作者表现统计)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_author_performance_stats
ENGINE = AggregatingMergeTree()
ORDER BY (author_id, event_date)
AS SELECT
    author_id,
    event_date,
    uniqState(content_id) AS unique_content_state,
    countState() AS total_views_state,
    avgState(completion_rate) AS avg_completion_state,
    sumStateIf(toUInt64(1), completion_rate >= 0.9) AS high_completion_count_state
FROM user_content_interactions_v2
WHERE author_id != '' AND interaction_type = 'view'
GROUP BY author_id, event_date;

-- ============================================
-- 6. Real-time Feature Tables
-- ============================================

-- 6.1 User Recent Interests (用户近期兴趣 - 实时特征)
CREATE TABLE IF NOT EXISTS user_recent_interests (
    user_id String,
    interest_tag LowCardinality(String),
    weight Float32,
    last_updated DateTime DEFAULT now(),
    version UInt64 DEFAULT 1
) ENGINE = ReplacingMergeTree(version)
ORDER BY (user_id, interest_tag)
TTL last_updated + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- 6.2 Content Recent Stats (内容近期统计 - 实时特征)
CREATE TABLE IF NOT EXISTS content_recent_stats (
    content_id String,
    stat_hour DateTime,
    impressions UInt32 DEFAULT 0,
    engagements UInt32 DEFAULT 0,
    completions UInt32 DEFAULT 0,
    avg_completion_rate Float32 DEFAULT 0.0,
    engagement_rate Float32 DEFAULT 0.0,
    version UInt64 DEFAULT 1
) ENGINE = ReplacingMergeTree(version)
ORDER BY (content_id, stat_hour)
TTL stat_hour + INTERVAL 24 HOUR
SETTINGS index_granularity = 8192;

-- 6.3 User-Author Affinity (用户-作者亲和度)
CREATE TABLE IF NOT EXISTS user_author_affinity_v2 (
    user_id String,
    author_id String,
    affinity_score Float32 DEFAULT 0.0,
    interaction_count UInt32 DEFAULT 0,
    avg_completion_rate Float32 DEFAULT 0.0,
    last_interaction DateTime DEFAULT now(),
    version UInt64 DEFAULT 1
) ENGINE = ReplacingMergeTree(version)
ORDER BY (user_id, author_id)
TTL last_interaction + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 7. Exploration Pool Stats (探索池统计)
-- ============================================

CREATE TABLE IF NOT EXISTS exploration_pool_stats (
    content_id String,
    author_id String,
    upload_time DateTime,
    impressions UInt32 DEFAULT 0,
    engagements UInt32 DEFAULT 0,
    completions UInt32 DEFAULT 0,
    avg_completion_rate Float32 DEFAULT 0.0,
    ucb_score Float32 DEFAULT 1000.0,
    is_active UInt8 DEFAULT 1,
    last_updated DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(last_updated)
ORDER BY (content_id)
TTL upload_time + INTERVAL 7 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 8. Query Helper Views
-- ============================================

-- 8.1 User Watch Summary (用户观看摘要)
CREATE VIEW IF NOT EXISTS v_user_watch_summary AS
SELECT
    user_id,
    count() AS total_views,
    avg(completion_rate) AS avg_completion,
    sum(watch_duration_ms) / 1000 / 60 AS total_watch_minutes,
    uniq(content_id) AS unique_videos,
    max(event_time) AS last_watch
FROM watch_events
WHERE event_date >= today() - 30
GROUP BY user_id;

-- 8.2 Content Performance Summary (内容表现摘要)
CREATE VIEW IF NOT EXISTS v_content_performance_summary AS
SELECT
    content_id,
    count() AS total_views,
    avg(completion_rate) AS avg_completion,
    countIf(completion_rate >= 0.9) AS high_completion_count,
    countIf(is_replay = 1) AS replay_count,
    uniq(user_id) AS unique_viewers,
    min(event_time) AS first_view,
    max(event_time) AS last_view
FROM watch_events
WHERE event_date >= today() - 7
GROUP BY content_id;

-- 8.3 User Active Hours Distribution (用户活跃时间分布)
CREATE VIEW IF NOT EXISTS v_user_active_hours AS
SELECT
    user_id,
    toHour(event_time) AS hour,
    count() AS activity_count
FROM watch_events
WHERE event_date >= today() - 30
GROUP BY user_id, hour
ORDER BY user_id, activity_count DESC;

-- 8.4 Session Analysis (会话分析)
CREATE VIEW IF NOT EXISTS v_session_analysis AS
SELECT
    user_id,
    session_id,
    min(event_time) AS session_start,
    max(event_time) AS session_end,
    dateDiff('second', min(event_time), max(event_time)) AS session_duration_seconds,
    count() AS events_count,
    uniq(content_id) AS unique_content,
    avg(completion_rate) AS avg_completion
FROM watch_events
WHERE session_id != '' AND event_date >= today() - 7
GROUP BY user_id, session_id
HAVING session_duration_seconds > 0;

-- ============================================
-- 9. Indexes for Common Query Patterns
-- ============================================

-- Note: MergeTree tables already have primary key index
-- Add bloom filter indexes for high-cardinality columns

ALTER TABLE watch_events ADD INDEX idx_content_bloom content_id TYPE bloom_filter GRANULARITY 4;
ALTER TABLE watch_events ADD INDEX idx_session_bloom session_id TYPE bloom_filter GRANULARITY 4;

ALTER TABLE user_content_interactions_v2 ADD INDEX idx_author_bloom author_id TYPE bloom_filter GRANULARITY 4;
ALTER TABLE user_content_interactions_v2 ADD INDEX idx_session_bloom session_id TYPE bloom_filter GRANULARITY 4;

-- ============================================
-- 10. Data Retention Management
-- ============================================

-- System table for TTL monitoring (optional)
-- SELECT table, rows, bytes_on_disk FROM system.parts WHERE database = 'nova_feed' AND active;

-- Query to check partition sizes
-- SELECT partition, count() as parts, sum(rows) as rows, formatReadableSize(sum(bytes_on_disk)) as size
-- FROM system.parts WHERE database = 'nova_feed' AND active GROUP BY partition ORDER BY partition;
