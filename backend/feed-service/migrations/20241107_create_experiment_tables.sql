-- Migration: Create experiment tables for A/B testing framework
-- Phase 3: Spec 007 - Feed Service Users Consolidation

-- Create experiment_status enum
CREATE TYPE experiment_status AS ENUM ('draft', 'active', 'paused', 'completed', 'cancelled');

-- Create experiments table
CREATE TABLE experiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    status experiment_status NOT NULL DEFAULT 'draft',
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    stratification_key TEXT NOT NULL DEFAULT 'user_id',
    sample_size INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID -- nullable, references auth-service users (no FK constraint)
);

CREATE INDEX idx_experiments_status ON experiments(status);
CREATE INDEX idx_experiments_created_by ON experiments(created_by) WHERE created_by IS NOT NULL;

-- Create experiment_assignments table
CREATE TABLE experiment_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL, -- references auth-service users (no FK constraint)
    variant_id UUID NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(experiment_id, user_id)
);

CREATE INDEX idx_experiment_assignments_user_id ON experiment_assignments(user_id);
CREATE INDEX idx_experiment_assignments_experiment_id ON experiment_assignments(experiment_id);

-- Create experiment_metrics table
CREATE TABLE experiment_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL, -- references auth-service users (no FK constraint)
    variant_id UUID,
    metric_name TEXT NOT NULL,
    metric_value NUMERIC NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_experiment_metrics_user_id ON experiment_metrics(user_id);
CREATE INDEX idx_experiment_metrics_experiment_id ON experiment_metrics(experiment_id);
CREATE INDEX idx_experiment_metrics_metric_name ON experiment_metrics(metric_name);
