-- ============================================================================
-- Graph Service PostgreSQL Schema
-- ============================================================================
-- Purpose: Create PostgreSQL schema for graph-service (social graph)
-- Database: nova_graph
-- Source of Truth: PostgreSQL (Neo4j is read optimization layer)
-- ============================================================================

-- Users table (lightweight, just for graph relationships)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE NULL
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NULL;

-- Follows table (follower_id follows following_id)
CREATE TABLE IF NOT EXISTS follows (
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT no_self_follow CHECK (follower_id != following_id)
);

CREATE INDEX idx_follows_follower ON follows(follower_id);
CREATE INDEX idx_follows_following ON follows(following_id);
CREATE INDEX idx_follows_created_at ON follows(created_at);

-- Mutes table (muter_id mutes muted_id)
CREATE TABLE IF NOT EXISTS mutes (
    muter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    muted_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (muter_id, muted_id),
    CONSTRAINT no_self_mute CHECK (muter_id != muted_id)
);

CREATE INDEX idx_mutes_muter ON mutes(muter_id);
CREATE INDEX idx_mutes_muted ON mutes(muted_id);

-- Blocks table (blocker_id blocks blocked_id)
CREATE TABLE IF NOT EXISTS blocks (
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (blocker_id, blocked_id),
    CONSTRAINT no_self_block CHECK (blocker_id != blocked_id)
);

CREATE INDEX idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_id);

-- Comments
COMMENT ON TABLE users IS 'User nodes for social graph (lightweight, synchronized from identity-service)';
COMMENT ON TABLE follows IS 'Follow relationships (follower -> following)';
COMMENT ON TABLE mutes IS 'Mute relationships (user mutes another user''s content)';
COMMENT ON TABLE blocks IS 'Block relationships (user blocks another user completely)';
