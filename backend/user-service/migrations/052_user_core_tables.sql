-- Migration: Core user profiles & relationships tables
-- Purpose: Provide backing tables for user-service gRPC APIs
-- Created: 2025-11-01

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Remove legacy view so the real tables can be created safely
DROP VIEW IF EXISTS user_profiles CASCADE;
DROP FUNCTION IF EXISTS user_profiles_update();

-- User profile projection (owned by auth-service as single writer)
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    bio TEXT,
    avatar_url TEXT,
    cover_url TEXT,
    website TEXT,
    location TEXT,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    is_private BOOLEAN NOT NULL DEFAULT false,
    follower_count INTEGER NOT NULL DEFAULT 0,
    following_count INTEGER NOT NULL DEFAULT 0,
    post_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT fk_user_profiles_user FOREIGN KEY (id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(username);
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON user_profiles(email);
CREATE INDEX IF NOT EXISTS idx_user_profiles_created_at ON user_profiles(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_profiles_deleted_at ON user_profiles(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE OR REPLACE FUNCTION touch_user_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_profiles_updated_at ON user_profiles;
CREATE TRIGGER trg_user_profiles_updated_at
BEFORE UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION touch_user_profiles_updated_at();

-- User settings (per-user preferences)
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    email_notifications BOOLEAN NOT NULL DEFAULT true,
    push_notifications BOOLEAN NOT NULL DEFAULT true,
    marketing_emails BOOLEAN NOT NULL DEFAULT false,
    timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
    language VARCHAR(16) NOT NULL DEFAULT 'en',
    dark_mode BOOLEAN NOT NULL DEFAULT false,
    privacy_level VARCHAR(32) NOT NULL DEFAULT 'public',
    allow_messages BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION touch_user_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_settings_updated_at ON user_settings;
CREATE TRIGGER trg_user_settings_updated_at
BEFORE UPDATE ON user_settings
FOR EACH ROW
EXECUTE FUNCTION touch_user_settings_updated_at();

-- Social graph relationships (follow/block)
CREATE TABLE IF NOT EXISTS user_relationships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    relationship_type VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_relationship UNIQUE (follower_id, followee_id)
);

CREATE INDEX IF NOT EXISTS idx_user_relationships_followee ON user_relationships(followee_id, relationship_type, status);
CREATE INDEX IF NOT EXISTS idx_user_relationships_follower ON user_relationships(follower_id, relationship_type, status);
CREATE INDEX IF NOT EXISTS idx_user_relationships_created_at ON user_relationships(created_at DESC);

CREATE OR REPLACE FUNCTION touch_user_relationships_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_relationships_updated_at ON user_relationships;
CREATE TRIGGER trg_user_relationships_updated_at
BEFORE UPDATE ON user_relationships
FOR EACH ROW
EXECUTE FUNCTION touch_user_relationships_updated_at();
