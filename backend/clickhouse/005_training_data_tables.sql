-- ============================================
-- ClickHouse Training Data Tables
-- P1-3: 訓練數據管道 (Training Data Pipeline)
-- ============================================

-- ============================================
-- 1. Training Interactions (訓練樣本表)
-- ============================================
-- 正樣本: 用戶點擊/完播的內容 (label=1)
-- 負樣本: 用戶曝光但未點擊的內容 (label=0)

CREATE TABLE IF NOT EXISTS training_interactions (
    user_id String,
    post_id String,
    author_id String DEFAULT '',
    label UInt8,                         -- 1=正樣本(點擊/完播), 0=負樣本(曝光未點擊)
    label_type LowCardinality(String),   -- 'click', 'complete', 'like', 'impression_no_click'
    -- Impression context
    impression_time DateTime,
    click_time Nullable(DateTime),
    -- Watch metrics
    watch_duration_ms UInt32 DEFAULT 0,
    content_duration_ms UInt32 DEFAULT 0,
    completion_rate Float32 DEFAULT 0.0,
    -- Recall source (for feature analysis)
    recall_source LowCardinality(String) DEFAULT '', -- 'graph', 'trending', 'personalized', 'item_cf', 'user_cf'
    -- Context features
    position_in_feed UInt16 DEFAULT 0,   -- Position in feed when shown
    session_id String DEFAULT '',
    device_type LowCardinality(String) DEFAULT '',
    hour_of_day UInt8 DEFAULT 0,
    day_of_week UInt8 DEFAULT 0,
    -- Date for partitioning
    event_date Date DEFAULT toDate(impression_time),
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, impression_time, post_id)
TTL event_date + INTERVAL 180 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 2. Training Features Snapshot (特徵快照表)
-- ============================================
-- 記錄訓練樣本產生時的特徵值，用於模型訓練

CREATE TABLE IF NOT EXISTS training_features (
    user_id String,
    post_id String,
    snapshot_time DateTime,
    -- User features
    user_follower_count UInt32 DEFAULT 0,
    user_following_count UInt32 DEFAULT 0,
    user_post_count UInt32 DEFAULT 0,
    user_avg_session_length Float32 DEFAULT 0.0,
    user_active_days_30d UInt16 DEFAULT 0,
    -- Content features
    post_age_hours Float32 DEFAULT 0.0,
    post_like_count UInt32 DEFAULT 0,
    post_comment_count UInt32 DEFAULT 0,
    post_view_count UInt32 DEFAULT 0,
    post_completion_rate Float32 DEFAULT 0.0,
    post_engagement_rate Float32 DEFAULT 0.0,
    content_duration_ms UInt32 DEFAULT 0,
    has_music UInt8 DEFAULT 0,
    is_original UInt8 DEFAULT 1,
    -- Author features
    author_follower_count UInt32 DEFAULT 0,
    author_avg_engagement Float32 DEFAULT 0.0,
    author_post_frequency Float32 DEFAULT 0.0, -- posts per day
    -- Interaction features (user-author)
    user_author_affinity Float32 DEFAULT 0.0,
    user_author_interaction_count UInt32 DEFAULT 0,
    -- Context features
    hour_of_day UInt8 DEFAULT 0,
    day_of_week UInt8 DEFAULT 0,
    is_weekend UInt8 DEFAULT 0,
    -- Recall features
    recall_source LowCardinality(String) DEFAULT '',
    recall_weight Float32 DEFAULT 0.0,
    -- JSON for additional features (flexible expansion)
    extra_features String DEFAULT '{}',
    -- Date for partitioning
    event_date Date DEFAULT toDate(snapshot_time),
    created_at DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (snapshot_time, user_id, post_id)
TTL event_date + INTERVAL 180 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 3. Item Similarity Table (物品相似度表)
-- ============================================
-- 用於 Item-CF 召回策略的相似度矩陣

CREATE TABLE IF NOT EXISTS item_similarity (
    item_id String,                      -- 源物品 (post_id)
    similar_item_id String,              -- 相似物品
    similarity_score Float64,            -- 相似度分數 (0-1)
    similarity_type LowCardinality(String) DEFAULT 'co_interaction', -- 'co_interaction', 'content', 'hybrid'
    co_interaction_count UInt32 DEFAULT 0,  -- 共同互動用戶數
    jaccard_score Float64 DEFAULT 0.0,      -- Jaccard 相似度
    cosine_score Float64 DEFAULT 0.0,       -- Cosine 相似度
    computed_at DateTime DEFAULT now(),
    version UInt64 DEFAULT 1
) ENGINE = ReplacingMergeTree(version)
ORDER BY (item_id, similarity_score DESC, similar_item_id)
TTL computed_at + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 4. User Similarity Table (用戶相似度表)
-- ============================================
-- 用於 User-CF 召回策略的相似度矩陣

CREATE TABLE IF NOT EXISTS user_similarity (
    user_id String,                      -- 源用戶
    similar_user_id String,              -- 相似用戶
    similarity_score Float64,            -- 相似度分數 (0-1)
    similarity_type LowCardinality(String) DEFAULT 'behavior', -- 'behavior', 'interest', 'hybrid'
    common_items_count UInt32 DEFAULT 0, -- 共同互動物品數
    common_authors_count UInt32 DEFAULT 0, -- 共同關注作者數
    jaccard_score Float64 DEFAULT 0.0,
    cosine_score Float64 DEFAULT 0.0,
    computed_at DateTime DEFAULT now(),
    version UInt64 DEFAULT 1
) ENGINE = ReplacingMergeTree(version)
ORDER BY (user_id, similarity_score DESC, similar_user_id)
TTL computed_at + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 5. User Recent Items Table (用戶近期互動物品)
-- ============================================
-- 支持 Item-CF 召回的種子物品查詢

CREATE TABLE IF NOT EXISTS user_recent_items (
    user_id String,
    post_id String,
    interaction_type LowCardinality(String), -- 'like', 'complete', 'comment', 'share'
    interaction_time DateTime,
    interaction_weight Float32 DEFAULT 1.0,
    version UInt64 DEFAULT 1
) ENGINE = ReplacingMergeTree(version)
ORDER BY (user_id, interaction_time DESC, post_id)
TTL interaction_time + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

-- ============================================
-- 6. Materialized Views for Training Data
-- ============================================

-- 6.1 自動從 likes_cdc 生成正樣本
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_training_likes
TO training_interactions AS
SELECT
    user_id,
    post_id,
    '' AS author_id,
    1 AS label,
    'like' AS label_type,
    created_at AS impression_time,
    created_at AS click_time,
    0 AS watch_duration_ms,
    0 AS content_duration_ms,
    0.0 AS completion_rate,
    '' AS recall_source,
    0 AS position_in_feed,
    '' AS session_id,
    '' AS device_type,
    toHour(created_at) AS hour_of_day,
    toDayOfWeek(created_at) AS day_of_week,
    toDate(created_at) AS event_date,
    now() AS created_at
FROM likes_cdc
WHERE is_deleted = 0;

-- 6.2 自動從 watch_events 生成正/負樣本（基於完播率）
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_training_watch
TO training_interactions AS
SELECT
    user_id,
    content_id AS post_id,
    '' AS author_id,
    if(completion_rate >= 0.7, 1, 0) AS label,
    if(completion_rate >= 0.7, 'complete', 'impression_no_click') AS label_type,
    event_time AS impression_time,
    if(completion_rate >= 0.7, event_time, NULL) AS click_time,
    watch_duration_ms,
    content_duration_ms,
    completion_rate,
    '' AS recall_source,
    0 AS position_in_feed,
    session_id,
    device_type,
    toHour(event_time) AS hour_of_day,
    toDayOfWeek(event_time) AS day_of_week,
    event_date,
    now() AS created_at
FROM watch_events
WHERE content_duration_ms > 0;

-- 6.3 自動更新 user_recent_items
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_recent_likes
TO user_recent_items AS
SELECT
    user_id,
    post_id,
    'like' AS interaction_type,
    created_at AS interaction_time,
    1.0 AS interaction_weight,
    toUnixTimestamp(created_at) AS version
FROM likes_cdc
WHERE is_deleted = 0;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_recent_watch
TO user_recent_items AS
SELECT
    user_id,
    content_id AS post_id,
    if(completion_rate >= 0.9, 'complete', 'view') AS interaction_type,
    event_time AS interaction_time,
    completion_rate AS interaction_weight,
    toUnixTimestamp(event_time) AS version
FROM watch_events
WHERE completion_rate >= 0.5;

-- ============================================
-- 7. Query Views for Training Data Export
-- ============================================

-- 7.1 訓練數據匯出視圖（含特徵）
CREATE VIEW IF NOT EXISTS v_training_data_export AS
SELECT
    ti.user_id,
    ti.post_id,
    ti.label,
    ti.label_type,
    ti.impression_time,
    ti.watch_duration_ms,
    ti.completion_rate,
    ti.recall_source,
    ti.position_in_feed,
    ti.hour_of_day,
    ti.day_of_week,
    -- Features from snapshot
    tf.user_follower_count,
    tf.user_following_count,
    tf.post_age_hours,
    tf.post_like_count,
    tf.post_comment_count,
    tf.post_completion_rate,
    tf.post_engagement_rate,
    tf.author_follower_count,
    tf.author_avg_engagement,
    tf.user_author_affinity,
    tf.recall_weight
FROM training_interactions ti
LEFT JOIN training_features tf
    ON ti.user_id = tf.user_id
    AND ti.post_id = tf.post_id
    AND abs(toUnixTimestamp(ti.impression_time) - toUnixTimestamp(tf.snapshot_time)) < 3600;

-- 7.2 每日訓練樣本統計
CREATE VIEW IF NOT EXISTS v_training_stats_daily AS
SELECT
    event_date,
    label,
    label_type,
    count() AS sample_count,
    uniq(user_id) AS unique_users,
    uniq(post_id) AS unique_posts,
    avg(completion_rate) AS avg_completion
FROM training_interactions
GROUP BY event_date, label, label_type
ORDER BY event_date DESC, label, label_type;

-- 7.3 物品相似度查詢視圖（Top-K）
CREATE VIEW IF NOT EXISTS v_item_similar_topk AS
SELECT
    item_id,
    groupArray(10)(similar_item_id) AS top_similar_items,
    groupArray(10)(similarity_score) AS similarity_scores
FROM (
    SELECT
        item_id,
        similar_item_id,
        similarity_score,
        row_number() OVER (PARTITION BY item_id ORDER BY similarity_score DESC) AS rn
    FROM item_similarity FINAL
)
WHERE rn <= 10
GROUP BY item_id;

-- 7.4 用戶相似度查詢視圖（Top-K）
CREATE VIEW IF NOT EXISTS v_user_similar_topk AS
SELECT
    user_id,
    groupArray(20)(similar_user_id) AS top_similar_users,
    groupArray(20)(similarity_score) AS similarity_scores
FROM (
    SELECT
        user_id,
        similar_user_id,
        similarity_score,
        row_number() OVER (PARTITION BY user_id ORDER BY similarity_score DESC) AS rn
    FROM user_similarity FINAL
)
WHERE rn <= 20
GROUP BY user_id;

-- ============================================
-- 8. Indexes
-- ============================================

ALTER TABLE training_interactions ADD INDEX idx_label label TYPE minmax GRANULARITY 4;
ALTER TABLE training_interactions ADD INDEX idx_recall_source recall_source TYPE bloom_filter GRANULARITY 4;
ALTER TABLE item_similarity ADD INDEX idx_similar_item similar_item_id TYPE bloom_filter GRANULARITY 4;
ALTER TABLE user_similarity ADD INDEX idx_similar_user similar_user_id TYPE bloom_filter GRANULARITY 4;
