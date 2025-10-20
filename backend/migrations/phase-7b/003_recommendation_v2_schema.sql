-- ============================================
-- Phase 7B Feature 5: Recommendation v2.0 Schema
-- Migration: 003_recommendation_v2_schema.sql
-- Created: 2025-10-19
-- ============================================

BEGIN;

-- ============================================
-- PostgreSQL: Experiment Framework
-- ============================================

-- Experiments table: Configuration for A/B tests
CREATE TABLE IF NOT EXISTS experiments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP,
    variants JSONB NOT NULL,  -- [{"name": "control", "allocation": 50, "config": {...}}]
    status VARCHAR(50) DEFAULT 'draft',  -- draft, running, completed, cancelled
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by UUID,  -- Admin user who created the experiment

    CONSTRAINT valid_status CHECK (status IN ('draft', 'running', 'completed', 'cancelled')),
    CONSTRAINT end_after_start CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE INDEX idx_experiments_status ON experiments(status);
CREATE INDEX idx_experiments_name ON experiments(name);

COMMENT ON TABLE experiments IS 'A/B testing experiment configurations for recommendation algorithm variants';
COMMENT ON COLUMN experiments.variants IS 'JSON array of variant configs: [{"name": "control", "allocation": 50, "config": {"algorithm": "v1.0"}}]';

-- User experiment assignments: Track which variant each user is in
CREATE TABLE IF NOT EXISTS user_experiment_assignments (
    user_id UUID NOT NULL,
    experiment_id INTEGER NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    variant_name VARCHAR(100) NOT NULL,
    assigned_at TIMESTAMP DEFAULT NOW(),
    metadata JSONB,  -- Additional context (e.g., user segment)

    PRIMARY KEY (user_id, experiment_id)
);

CREATE INDEX idx_user_exp_user ON user_experiment_assignments(user_id);
CREATE INDEX idx_user_exp_experiment ON user_experiment_assignments(experiment_id);
CREATE INDEX idx_user_exp_variant ON user_experiment_assignments(experiment_id, variant_name);

COMMENT ON TABLE user_experiment_assignments IS 'Tracks which experiment variant each user is assigned to (consistent hashing)';

-- Model versioning: Track deployed models
CREATE TABLE IF NOT EXISTS ml_models (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,  -- e.g., "collaborative_filtering", "content_based"
    version VARCHAR(50) NOT NULL,  -- e.g., "v1.0", "v1.1"
    model_path TEXT NOT NULL,  -- Path to ONNX file: "/models/collaborative_v1.0.onnx"
    model_type VARCHAR(50) NOT NULL,  -- knn, matrix_factorization, neural_network
    training_date TIMESTAMP NOT NULL,
    deployed_date TIMESTAMP,
    status VARCHAR(50) DEFAULT 'training',  -- training, deployed, deprecated
    metrics JSONB,  -- Offline evaluation: {"ndcg@10": 0.32, "precision@10": 0.18}
    hyperparameters JSONB,  -- Model config: {"k": 50, "metric": "cosine"}
    created_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT valid_model_status CHECK (status IN ('training', 'deployed', 'deprecated')),
    UNIQUE (name, version)
);

CREATE INDEX idx_models_name_version ON ml_models(name, version);
CREATE INDEX idx_models_status ON ml_models(status);

COMMENT ON TABLE ml_models IS 'Version history and metadata for deployed ML models';

-- Seed initial experiment: v1.0 vs v2.0 rollout
INSERT INTO experiments (name, description, start_date, variants, status)
VALUES (
    'recommendation_v2_rollout',
    'Phase 7B: Hybrid recommendation v2.0 gradual rollout',
    NOW(),
    '[
        {
            "name": "control",
            "allocation": 50,
            "config": {
                "algorithm": "v1.0",
                "description": "Rule-based ranking with fixed weights"
            }
        },
        {
            "name": "variant_a",
            "allocation": 30,
            "config": {
                "algorithm": "v2.0",
                "weights": {"collaborative": 0.4, "content_based": 0.3, "v1_fallback": 0.3},
                "description": "Hybrid model with balanced weights"
            }
        },
        {
            "name": "variant_b",
            "allocation": 20,
            "config": {
                "algorithm": "v2.0",
                "weights": {"collaborative": 0.5, "content_based": 0.4, "v1_fallback": 0.1},
                "description": "Hybrid model with high personalization weights"
            }
        }
    ]'::jsonb,
    'running'
)
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ============================================
-- ClickHouse: Experiment Events and ML Data
-- ============================================
-- NOTE: ClickHouse migrations are executed separately (different database)

-- Execute on ClickHouse cluster:

-- Experiment events: Track user interactions per experiment variant
-- CREATE TABLE IF NOT EXISTS nova_feed.experiment_events (
--     event_time DateTime DEFAULT now(),
--     experiment_id UInt32,
--     variant_name String,
--     user_id UUID,
--     post_id Nullable(UUID),  -- Null for non-post events (e.g., feed_request)
--     action String,  -- impression, click, like, share, dwell, feed_request
--     dwell_ms UInt32 DEFAULT 0,
--     session_id UUID,
--     event_date Date DEFAULT toDate(event_time),
--     metadata String DEFAULT ''  -- JSON metadata
-- ) ENGINE = MergeTree()
-- PARTITION BY toYYYYMM(event_date)
-- ORDER BY (experiment_id, variant_name, user_id, event_time)
-- SETTINGS index_granularity = 8192;

-- COMMENT ON COLUMN nova_feed.experiment_events.action IS 'Event type: impression, click, like, share, dwell, feed_request';

-- User-Item Interaction Matrix (offline computation for collaborative filtering)
-- CREATE TABLE IF NOT EXISTS nova_feed.user_item_interactions (
--     user_id UUID,
--     post_id UUID,
--     interaction_score Float64,  -- Weighted score: view=1, like=5, comment=10, share=15
--     last_interaction DateTime,
--     window_start Date,
--     event_count UInt32 DEFAULT 1
-- ) ENGINE = SummingMergeTree(interaction_score, event_count)
-- PARTITION BY toYYYYMM(window_start)
-- ORDER BY (user_id, post_id)
-- SETTINGS index_granularity = 8192;

-- COMMENT ON TABLE nova_feed.user_item_interactions IS 'Aggregated user-post interactions for collaborative filtering (90-day rolling window)';

-- Model Performance Metrics (daily evaluation)
-- CREATE TABLE IF NOT EXISTS nova_feed.model_metrics (
--     metric_time DateTime DEFAULT now(),
--     model_name String,
--     model_version String,
--     metric_name String,  -- ndcg@10, precision@10, recall@10, coverage, diversity
--     metric_value Float64,
--     metadata String DEFAULT '',  -- JSON metadata (e.g., user segment)
--     metric_date Date DEFAULT toDate(metric_time)
-- ) ENGINE = MergeTree()
-- PARTITION BY toYYYYMM(metric_date)
-- ORDER BY (model_name, model_version, metric_name, metric_time)
-- SETTINGS index_granularity = 8192;

-- COMMENT ON TABLE nova_feed.model_metrics IS 'Daily offline evaluation metrics for deployed ML models';

-- Post features (for content-based filtering)
-- CREATE TABLE IF NOT EXISTS nova_feed.post_features (
--     post_id UUID,
--     feature_name String,  -- tfidf_rust, tfidf_machine_learning, hashtag_technology
--     feature_value Float32,
--     extracted_at DateTime DEFAULT now()
-- ) ENGINE = ReplacingMergeTree(extracted_at)
-- PARTITION BY toYYYYMM(toDate(extracted_at))
-- ORDER BY (post_id, feature_name)
-- SETTINGS index_granularity = 8192;

-- COMMENT ON TABLE nova_feed.post_features IS 'Extracted post features for content-based filtering (TF-IDF vectors)';

-- User interest profiles (aggregated post features)
-- CREATE TABLE IF NOT EXISTS nova_feed.user_interest_profiles (
--     user_id UUID,
--     feature_name String,
--     feature_value Float32,
--     last_updated DateTime DEFAULT now()
-- ) ENGINE = ReplacingMergeTree(last_updated)
-- PARTITION BY toYYYYMM(toDate(last_updated))
-- ORDER BY (user_id, feature_name)
-- SETTINGS index_granularity = 8192;

-- COMMENT ON TABLE nova_feed.user_interest_profiles IS 'User interest profiles (aggregated TF-IDF vectors from engaged posts)';

-- Materialized view: Aggregate user-item interactions from events
-- CREATE MATERIALIZED VIEW IF NOT EXISTS nova_feed.user_item_interactions_mv
-- TO nova_feed.user_item_interactions
-- AS
-- SELECT
--     user_id,
--     post_id,
--     sum(
--         CASE action
--             WHEN 'view' THEN 1
--             WHEN 'like' THEN 5
--             WHEN 'comment' THEN 10
--             WHEN 'share' THEN 15
--             ELSE 0
--         END
--     ) AS interaction_score,
--     max(event_time) AS last_interaction,
--     toDate(event_time) AS window_start,
--     count() AS event_count
-- FROM nova_feed.events
-- WHERE event_time >= now() - INTERVAL 90 DAY
--   AND post_id IS NOT NULL
--   AND action IN ('view', 'like', 'comment', 'share')
-- GROUP BY user_id, post_id, window_start;

-- ============================================
-- ClickHouse SQL file for manual execution
-- ============================================
-- Save the above ClickHouse DDL to:
-- infra/clickhouse/migrations/003_recommendation_v2_schema.sql
-- Execute: clickhouse-client --queries-file 003_recommendation_v2_schema.sql
