-- Feature Store Metadata Tables
-- Migration: 001_feature_metadata
-- Description: Create tables for feature definitions and entity types

-- Entity types table
CREATE TABLE IF NOT EXISTS entity_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Feature definitions table
CREATE TABLE IF NOT EXISTS feature_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    entity_type VARCHAR(255) NOT NULL REFERENCES entity_types(name) ON DELETE RESTRICT,
    feature_type INTEGER NOT NULL, -- 1=Double, 2=Int, 3=String, 4=Bool, 5=DoubleList, 6=Timestamp
    description TEXT,
    default_ttl_seconds BIGINT NOT NULL DEFAULT 3600, -- Default 1 hour
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE(entity_type, name)
);

-- Indexes
CREATE INDEX idx_feature_definitions_entity_type ON feature_definitions(entity_type);
CREATE INDEX idx_feature_definitions_name ON feature_definitions(name);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_entity_types_updated_at
    BEFORE UPDATE ON entity_types
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_feature_definitions_updated_at
    BEFORE UPDATE ON feature_definitions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert default entity types
INSERT INTO entity_types (name, description) VALUES
    ('user', 'User entity type for user-level features'),
    ('post', 'Post entity type for post-level features'),
    ('comment', 'Comment entity type for comment-level features')
ON CONFLICT (name) DO NOTHING;

-- Sample feature definitions
INSERT INTO feature_definitions (name, entity_type, feature_type, description, default_ttl_seconds) VALUES
    ('engagement_score', 'user', 1, 'User engagement score (0.0-1.0)', 3600),
    ('last_active_timestamp', 'user', 6, 'Last active timestamp (Unix epoch)', 300),
    ('content_embedding', 'post', 5, 'Post content embedding vector (768 dimensions)', 86400),
    ('view_count', 'post', 2, 'Post view count', 1800),
    ('is_verified', 'user', 4, 'Whether user is verified', 86400)
ON CONFLICT (entity_type, name) DO NOTHING;
