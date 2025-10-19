-- Migration: Add Deep Learning Model Versioning Tables
-- Purpose: Track TensorFlow model deployments and performance metrics
-- Version: 1.0
-- Date: 2025-10-19

-- Create deep learning models table
CREATE TABLE IF NOT EXISTS deep_recall_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_version VARCHAR(255) NOT NULL UNIQUE,
    deployed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT FALSE,
    performance_metrics JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create index on model_version for quick lookups
CREATE INDEX IF NOT EXISTS idx_deep_recall_models_version ON deep_recall_models(model_version);

-- Create index on is_active to find current active model
CREATE INDEX IF NOT EXISTS idx_deep_recall_models_active ON deep_recall_models(is_active)
WHERE is_active = TRUE;

-- Create index on deployed_at for sorting by deployment time
CREATE INDEX IF NOT EXISTS idx_deep_recall_models_deployed ON deep_recall_models(deployed_at DESC);

-- Create feed cache stats table for monitoring
CREATE TABLE IF NOT EXISTS feed_cache_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    cache_hit_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cache_size INT NOT NULL DEFAULT 0,
    cache_ttl_seconds INT NOT NULL DEFAULT 3600,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create composite index on user_id and cache_hit_at for efficient queries
CREATE INDEX IF NOT EXISTS idx_feed_cache_stats_user_time
ON feed_cache_stats(user_id, cache_hit_at DESC);

-- Create index on cache_hit_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_feed_cache_stats_time
ON feed_cache_stats(cache_hit_at DESC);

-- Add column to track model usage statistics (optional enhancement)
ALTER TABLE deep_recall_models
ADD COLUMN IF NOT EXISTS inference_count BIGINT DEFAULT 0,
ADD COLUMN IF NOT EXISTS avg_latency_ms FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS accuracy_score FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS f1_score FLOAT DEFAULT 0.0;

-- Create function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_deep_recall_models_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic timestamp updates
DROP TRIGGER IF EXISTS trigger_update_deep_recall_models_timestamp ON deep_recall_models;
CREATE TRIGGER trigger_update_deep_recall_models_timestamp
BEFORE UPDATE ON deep_recall_models
FOR EACH ROW
EXECUTE FUNCTION update_deep_recall_models_timestamp();

-- Create comments for documentation
COMMENT ON TABLE deep_recall_models IS 'Tracks TensorFlow model deployments and performance metrics for video ranking';
COMMENT ON COLUMN deep_recall_models.model_version IS 'Semantic version of the model (e.g., 1.0.0, 1.0.1)';
COMMENT ON COLUMN deep_recall_models.performance_metrics IS 'JSON object containing {accuracy, f1_score, latency_ms, inference_count}';
COMMENT ON COLUMN deep_recall_models.is_active IS 'Whether this model is currently being used for inference';

COMMENT ON TABLE feed_cache_stats IS 'Monitors feed cache performance and hit rates';
COMMENT ON COLUMN feed_cache_stats.cache_size IS 'Size of cached feed data in bytes';
COMMENT ON COLUMN feed_cache_stats.cache_ttl_seconds IS 'Time-to-live for the cache entry in seconds';
