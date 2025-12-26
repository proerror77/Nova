-- OAuth Connections Migration
-- This table stores OAuth provider connections for each user
-- Allows users to link multiple OAuth providers (Google, Apple, etc.) to their account

-- Create oauth_connections table
CREATE TABLE IF NOT EXISTS oauth_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Provider information
    provider VARCHAR(50) NOT NULL,              -- 'google', 'apple', 'facebook', 'wechat'
    provider_user_id VARCHAR(255) NOT NULL,     -- Provider's unique user ID

    -- User info from provider
    email VARCHAR(255),
    name VARCHAR(255),
    picture_url VARCHAR(500),

    -- Token storage (encrypted)
    access_token_encrypted TEXT,
    refresh_token_encrypted TEXT,
    token_type VARCHAR(50),
    expires_at TIMESTAMPTZ,
    scopes TEXT,

    -- Raw provider response for debugging
    raw_data JSONB,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ensure one connection per provider per user
    UNIQUE(user_id, provider),
    -- Ensure provider_user_id is unique per provider
    UNIQUE(provider, provider_user_id)
);

-- Create indexes for performance
CREATE INDEX idx_oauth_connections_user_id ON oauth_connections(user_id);
CREATE INDEX idx_oauth_connections_provider ON oauth_connections(provider);
CREATE INDEX idx_oauth_connections_provider_user ON oauth_connections(provider, provider_user_id);
CREATE INDEX idx_oauth_connections_email ON oauth_connections(email) WHERE email IS NOT NULL;

-- Add trigger for updated_at
CREATE TRIGGER update_oauth_connections_updated_at
    BEFORE UPDATE ON oauth_connections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Add comments
COMMENT ON TABLE oauth_connections IS 'OAuth provider connections for users - supports Google, Apple, etc.';
COMMENT ON COLUMN oauth_connections.provider IS 'OAuth provider name: google, apple, facebook, wechat';
COMMENT ON COLUMN oauth_connections.provider_user_id IS 'Unique user identifier from the OAuth provider';
COMMENT ON COLUMN oauth_connections.access_token_encrypted IS 'AES encrypted OAuth access token';
COMMENT ON COLUMN oauth_connections.refresh_token_encrypted IS 'AES encrypted OAuth refresh token';
