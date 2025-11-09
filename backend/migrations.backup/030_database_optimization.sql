-- Database Performance Optimization and Missing Indexes
-- Improves query performance for common access patterns

-- User table optimization
-- Full-text search index for user discovery (username, display_name, bio)
CREATE INDEX IF NOT EXISTS idx_users_username_trgm
    ON users USING GIN (username gin_trgm_ops)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_users_display_name_trgm
    ON users USING GIN (display_name gin_trgm_ops)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_users_bio_trgm
    ON users USING GIN (bio gin_trgm_ops)
    WHERE deleted_at IS NULL;

-- Composite index for profile access pattern (private_account + id)
CREATE INDEX IF NOT EXISTS idx_users_private_account_id
    ON users (private_account, id)
    WHERE deleted_at IS NULL;

-- Index for blocking queries (bidirectional)
CREATE INDEX IF NOT EXISTS idx_users_email_verified
    ON users (email_verified)
    WHERE deleted_at IS NULL;

-- Follows table optimization
-- Indexes for relationship queries
CREATE INDEX IF NOT EXISTS idx_follows_follower_id
    ON follows (follower_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_follows_following_id
    ON follows (following_id, created_at DESC);

-- Composite index for follower/following checks
CREATE INDEX IF NOT EXISTS idx_follows_bidirectional
    ON follows (follower_id, following_id);

-- Blocks table optimization (if exists)
CREATE INDEX IF NOT EXISTS idx_blocks_blocker_id
    ON blocks (blocker_id);

CREATE INDEX IF NOT EXISTS idx_blocks_blocked_id
    ON blocks (blocked_id);

-- Composite index for bidirectional block checks
CREATE INDEX IF NOT EXISTS idx_blocks_bidirectional
    ON blocks (blocker_id, blocked_id);

-- Conversations table optimization
-- Index for user's conversations
CREATE INDEX IF NOT EXISTS idx_conversations_type
    ON conversations (conversation_type);

-- Messages table optimization
-- Index for conversation message retrieval with pagination
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
    ON messages (conversation_id, created_at DESC);

-- Index for message search by content
CREATE INDEX IF NOT EXISTS idx_messages_content_trgm
    ON messages USING GIN (content gin_trgm_ops);

-- Index for deleted messages soft delete pattern
CREATE INDEX IF NOT EXISTS idx_messages_deleted_at
    ON messages (deleted_at)
    WHERE deleted_at IS NOT NULL;

-- Conversation members table optimization
-- Index for role-based queries and member lists
CREATE INDEX IF NOT EXISTS idx_conversation_members_user_id
    ON conversation_members (user_id);

CREATE INDEX IF NOT EXISTS idx_conversation_members_role
    ON conversation_members (conversation_id, role);

-- Composite index for checking membership
CREATE INDEX IF NOT EXISTS idx_conversation_members_check
    ON conversation_members (conversation_id, user_id);

-- Message reactions optimization (already has some, add missing ones)
CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id
    ON message_reactions (user_id);

CREATE INDEX IF NOT EXISTS idx_message_reactions_emoji
    ON message_reactions (message_id, emoji);

-- Message attachments optimization
-- Index for attachment listing
CREATE INDEX IF NOT EXISTS idx_message_attachments_created_at
    ON message_attachments (created_at DESC);

-- Videos table optimization (for streaming and video features)
CREATE INDEX IF NOT EXISTS idx_videos_created_at
    ON videos (created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_videos_user_created
    ON videos (user_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Posts table optimization (if exists)
CREATE INDEX IF NOT EXISTS idx_posts_user_id
    ON posts (user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_posts_created_at
    ON posts (created_at DESC)
    WHERE deleted_at IS NULL;

-- Post interactions optimization
CREATE INDEX IF NOT EXISTS idx_likes_post_user
    ON likes (post_id, user_id);

CREATE INDEX IF NOT EXISTS idx_comments_post_id
    ON comments (post_id)
    WHERE deleted_at IS NULL;

-- Statistics and monitoring indexes
-- Created timestamp indexes for time-based queries
CREATE INDEX IF NOT EXISTS idx_users_created_at
    ON users (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_created_at
    ON messages (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_follows_created_at
    ON follows (created_at DESC);

-- Notifications table optimization (if exists)
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_read
    ON notifications (user_id, read_at)
    WHERE read_at IS NULL;

-- JWT tokens table optimization
CREATE INDEX IF NOT EXISTS idx_jwt_signing_keys_expired
    ON jwt_signing_keys (expired_at);

-- Streaming table optimizations
CREATE INDEX IF NOT EXISTS idx_streams_user_id_status
    ON streams (user_id, stream_status);

CREATE INDEX IF NOT EXISTS idx_stream_metrics_stream_id
    ON stream_metrics (stream_id, created_at DESC);

-- Viewer sessions for stream analytics
CREATE INDEX IF NOT EXISTS idx_viewer_sessions_stream_id
    ON viewer_sessions (stream_id);

-- Videos table - streaming specific
CREATE INDEX IF NOT EXISTS idx_videos_stream_id
    ON videos (stream_id)
    WHERE stream_id IS NOT NULL;

-- Explicitly enable GIN full-text search extension if not already enabled
-- This is needed for trigram (trgm) indexes used above
CREATE EXTENSION IF NOT EXISTS pg_trgm;
