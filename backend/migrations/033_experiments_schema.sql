-- A/B Testing Framework Schema
-- Migration: 033_experiments_schema.sql (重新编号从031)
-- Purpose: Support controlled experiments with user stratification and metric collection
-- Note: 此迁移已从031_experiments_schema.sql重新编号以解决编号冲突

-- Experiment status enum
CREATE TYPE experiment_status AS ENUM ('draft', 'running', 'completed', 'cancelled');

-- Main experiments table
CREATE TABLE experiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    status experiment_status NOT NULL DEFAULT 'draft',
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    stratification_key VARCHAR(50) NOT NULL DEFAULT 'user_id', -- 'user_id', 'session_id'
    sample_size INT NOT NULL CHECK (sample_size >= 0 AND sample_size <= 100), -- percentage
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Ensure dates are valid
    CONSTRAINT valid_date_range CHECK (end_date IS NULL OR end_date > start_date)
);

-- Experiment variants (control, treatment groups)
CREATE TABLE experiment_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    variant_name VARCHAR(100) NOT NULL, -- 'control', 'treatment_a', etc.
    variant_config JSONB NOT NULL DEFAULT '{}', -- feature flags/parameters
    traffic_allocation INT NOT NULL CHECK (traffic_allocation >= 0 AND traffic_allocation <= 100), -- percentage
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Unique variant names per experiment
    CONSTRAINT unique_variant_per_experiment UNIQUE (experiment_id, variant_name)
);

-- User variant assignments (deterministic, cached)
CREATE TABLE experiment_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES experiment_variants(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One assignment per user per experiment
    CONSTRAINT unique_user_experiment UNIQUE (experiment_id, user_id)
);

-- Metric events (high-volume, append-only)
CREATE TABLE experiment_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES experiment_variants(id) ON DELETE SET NULL,
    metric_name VARCHAR(100) NOT NULL, -- 'click', 'conversion', 'watch_time'
    metric_value NUMERIC NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Aggregated results cache (materialized for performance)
CREATE TABLE experiment_results_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES experiment_variants(id) ON DELETE CASCADE,
    metric_name VARCHAR(100) NOT NULL,
    sample_size BIGINT NOT NULL,
    metric_sum NUMERIC NOT NULL,
    metric_mean NUMERIC NOT NULL,
    metric_variance NUMERIC,
    metric_std_dev NUMERIC,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_cache_entry UNIQUE (experiment_id, variant_id, metric_name)
);

-- Indexes for query performance
CREATE INDEX idx_experiments_status ON experiments(status);
CREATE INDEX idx_experiments_dates ON experiments(start_date, end_date) WHERE status = 'running';

CREATE INDEX idx_variants_experiment ON experiment_variants(experiment_id);

CREATE INDEX idx_assignments_experiment ON experiment_assignments(experiment_id);
CREATE INDEX idx_assignments_user ON experiment_assignments(user_id);
CREATE INDEX idx_assignments_variant ON experiment_assignments(variant_id);

-- Metrics partitioning by time (PostgreSQL 10+)
CREATE INDEX idx_metrics_experiment_time ON experiment_metrics(experiment_id, recorded_at DESC);
CREATE INDEX idx_metrics_user ON experiment_metrics(user_id);
CREATE INDEX idx_metrics_variant ON experiment_metrics(variant_id);
CREATE INDEX idx_metrics_name_time ON experiment_metrics(metric_name, recorded_at DESC);

CREATE INDEX idx_results_cache_experiment ON experiment_results_cache(experiment_id);

-- Trigger to update experiments.updated_at
CREATE OR REPLACE FUNCTION update_experiments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER experiments_updated_at_trigger
BEFORE UPDATE ON experiments
FOR EACH ROW
EXECUTE FUNCTION update_experiments_updated_at();

-- Function to validate traffic allocation sums to 100%
CREATE OR REPLACE FUNCTION validate_traffic_allocation()
RETURNS TRIGGER AS $$
DECLARE
    total_allocation INT;
BEGIN
    SELECT COALESCE(SUM(traffic_allocation), 0) INTO total_allocation
    FROM experiment_variants
    WHERE experiment_id = NEW.experiment_id AND id != COALESCE(NEW.id, gen_random_uuid());

    IF (total_allocation + NEW.traffic_allocation) > 100 THEN
        RAISE EXCEPTION 'Total traffic allocation exceeds 100%% for experiment %', NEW.experiment_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_variant_allocation_trigger
BEFORE INSERT OR UPDATE ON experiment_variants
FOR EACH ROW
EXECUTE FUNCTION validate_traffic_allocation();

-- Function to prevent assignment changes for running experiments
CREATE OR REPLACE FUNCTION prevent_running_experiment_changes()
RETURNS TRIGGER AS $$
DECLARE
    exp_status experiment_status;
BEGIN
    SELECT status INTO exp_status FROM experiments WHERE id = NEW.experiment_id;

    IF exp_status = 'running' AND TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Cannot modify variants for running experiment %', NEW.experiment_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_variant_changes_trigger
BEFORE UPDATE ON experiment_variants
FOR EACH ROW
EXECUTE FUNCTION prevent_running_experiment_changes();

-- Grant permissions (adjust as needed)
GRANT SELECT, INSERT, UPDATE ON experiments TO nova_app;
GRANT SELECT, INSERT, UPDATE ON experiment_variants TO nova_app;
GRANT SELECT, INSERT ON experiment_assignments TO nova_app;
GRANT SELECT, INSERT ON experiment_metrics TO nova_app;
GRANT SELECT, INSERT, UPDATE ON experiment_results_cache TO nova_app;

-- Comments for documentation
COMMENT ON TABLE experiments IS 'A/B test experiment definitions with lifecycle management';
COMMENT ON TABLE experiment_variants IS 'Variant groups (control, treatment) with configuration';
COMMENT ON TABLE experiment_assignments IS 'User-to-variant mappings (deterministic, cached)';
COMMENT ON TABLE experiment_metrics IS 'High-volume metric events (append-only, time-series)';
COMMENT ON TABLE experiment_results_cache IS 'Pre-aggregated statistics for fast result retrieval';

COMMENT ON COLUMN experiments.sample_size IS 'Percentage of users enrolled (0-100)';
COMMENT ON COLUMN experiment_variants.traffic_allocation IS 'Percentage of sampled users assigned to this variant';
COMMENT ON COLUMN experiment_variants.variant_config IS 'Feature flags and parameters as JSON';
