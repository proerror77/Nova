-- Phase 7: Feature 5 - Recommendation Algorithm v2.0
-- ML model metadata, feature engineering, and inference tracking

CREATE TABLE IF NOT EXISTS ml_models (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_name VARCHAR(255) NOT NULL,
    version VARCHAR(20) NOT NULL,
    model_type VARCHAR(50) NOT NULL, -- 'collaborative_filtering', 'deep_learning', 'ensemble'
    status VARCHAR(20) DEFAULT 'training', -- 'training', 'validating', 'production', 'archived'
    file_path VARCHAR(500),
    model_hash VARCHAR(64),
    metrics JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deployed_at TIMESTAMP,
    archived_at TIMESTAMP,
    CONSTRAINT unique_model_version UNIQUE(model_name, version)
);

CREATE INDEX idx_models_status ON ml_models(status);
CREATE INDEX idx_models_deployed_at ON ml_models(deployed_at DESC);

-- Model performance tracking
CREATE TABLE IF NOT EXISTS model_performance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id UUID NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    metric_value FLOAT NOT NULL,
    metric_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dataset_split VARCHAR(20) DEFAULT 'validation', -- 'validation', 'test', 'production'
    CONSTRAINT fk_performance_model FOREIGN KEY (model_id) REFERENCES ml_models(id) ON DELETE CASCADE
);

CREATE INDEX idx_performance_model_id ON model_performance(model_id);
CREATE INDEX idx_performance_metric_name ON model_performance(metric_name);

-- User embeddings (256-dimensional vectors)
CREATE TABLE IF NOT EXISTS user_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE,
    model_id UUID NOT NULL,
    embedding VECTOR(256) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_embedding_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_embedding_model FOREIGN KEY (model_id) REFERENCES ml_models(id)
);

CREATE INDEX idx_user_embeddings_user_id ON user_embeddings(user_id);
CREATE INDEX idx_user_embeddings_created_at ON user_embeddings(created_at DESC);

-- Video embeddings (256-dimensional vectors)
CREATE TABLE IF NOT EXISTS video_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id UUID NOT NULL UNIQUE,
    model_id UUID NOT NULL,
    embedding VECTOR(256) NOT NULL,
    content_tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_video_embedding_video FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE,
    CONSTRAINT fk_video_embedding_model FOREIGN KEY (model_id) REFERENCES ml_models(id)
);

CREATE INDEX idx_video_embeddings_video_id ON video_embeddings(video_id);
CREATE INDEX idx_video_embeddings_created_at ON video_embeddings(created_at DESC);

-- User-item interaction history for training
CREATE TABLE IF NOT EXISTS user_item_interactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    video_id UUID NOT NULL,
    interaction_type VARCHAR(20) NOT NULL, -- 'view', 'like', 'comment', 'share', 'complete'
    interaction_value FLOAT NOT NULL, -- Weight: view=0.1, like=1.0, comment=2.0, share=3.0, complete=1.5
    interaction_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_interaction_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_interaction_video FOREIGN KEY (video_id) REFERENCES videos(id) ON DELETE CASCADE
) PARTITION BY RANGE (interaction_timestamp);

-- Create partitions for time-based data retention (90-day training window)
CREATE TABLE user_item_interactions_recent PARTITION OF user_item_interactions
    FOR VALUES FROM ('2025-07-22') TO ('2025-10-20');

CREATE INDEX idx_interactions_user_id ON user_item_interactions(user_id);
CREATE INDEX idx_interactions_video_id ON user_item_interactions(video_id);
CREATE INDEX idx_interactions_timestamp ON user_item_interactions(interaction_timestamp DESC);

-- Collaborative filtering similarity matrix (pre-computed)
CREATE TABLE IF NOT EXISTS cf_similarity_matrix (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id UUID NOT NULL,
    user_id_1 UUID NOT NULL,
    user_id_2 UUID NOT NULL,
    similarity_score FLOAT NOT NULL,
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_similarity_model FOREIGN KEY (model_id) REFERENCES ml_models(id),
    CONSTRAINT fk_similarity_user_1 FOREIGN KEY (user_id_1) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_similarity_user_2 FOREIGN KEY (user_id_2) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_cf_similarity_user_1 ON cf_similarity_matrix(user_id_1);
CREATE INDEX idx_cf_similarity_score ON cf_similarity_matrix(similarity_score DESC);

-- Model predictions/recommendations cache
CREATE TABLE IF NOT EXISTS recommendation_cache (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    model_id UUID NOT NULL,
    recommended_videos UUID[] NOT NULL, -- Array of video IDs ranked
    scores FLOAT[] NOT NULL, -- Corresponding confidence scores
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP + INTERVAL '6 hours',
    CONSTRAINT fk_cache_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_cache_model FOREIGN KEY (model_id) REFERENCES ml_models(id)
);

CREATE INDEX idx_cache_user_model ON recommendation_cache(user_id, model_id);
CREATE INDEX idx_cache_expires_at ON recommendation_cache(expires_at);

-- A/B test configuration
CREATE TABLE IF NOT EXISTS ab_tests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_name VARCHAR(255) NOT NULL UNIQUE,
    control_model_id UUID,
    treatment_model_id UUID,
    test_start_at TIMESTAMP,
    test_end_at TIMESTAMP,
    control_percentage INT DEFAULT 50,
    treatment_percentage INT DEFAULT 50,
    status VARCHAR(20) DEFAULT 'planned', -- 'planned', 'running', 'completed', 'archived'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ab_control_model FOREIGN KEY (control_model_id) REFERENCES ml_models(id),
    CONSTRAINT fk_ab_treatment_model FOREIGN KEY (treatment_model_id) REFERENCES ml_models(id)
);

CREATE INDEX idx_ab_tests_status ON ab_tests(status);

-- A/B test metrics
CREATE TABLE IF NOT EXISTS ab_test_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    test_id UUID NOT NULL,
    variant VARCHAR(20) NOT NULL, -- 'control' or 'treatment'
    metric_name VARCHAR(100) NOT NULL,
    metric_value FLOAT NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_metric_test FOREIGN KEY (test_id) REFERENCES ab_tests(id) ON DELETE CASCADE
);

CREATE INDEX idx_ab_metric_test_variant ON ab_test_metrics(test_id, variant);

-- Inference log for monitoring and debugging
CREATE TABLE IF NOT EXISTS inference_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id UUID NOT NULL,
    user_id UUID,
    request_id VARCHAR(255),
    inference_time_ms INT,
    batch_size INT DEFAULT 1,
    top_k INT DEFAULT 10,
    status VARCHAR(20) DEFAULT 'success', -- 'success', 'timeout', 'error'
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_inference_log_model FOREIGN KEY (model_id) REFERENCES ml_models(id)
);

CREATE INDEX idx_inference_logs_model_id ON inference_logs(model_id);
CREATE INDEX idx_inference_logs_created_at ON inference_logs(created_at DESC);
