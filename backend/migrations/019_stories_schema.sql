-- ============================================
-- Stories Schema (Ephemeral 24h content)
-- ============================================

-- Enable UUID if not present
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1) Stories table
-- - privacy_level: public | followers | close_friends
-- - content_type: image | video
CREATE TABLE IF NOT EXISTS stories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content_url TEXT NOT NULL,
    thumbnail_url TEXT,
    caption TEXT,
    content_type VARCHAR(16) NOT NULL CHECK (content_type IN ('image','video')),
    privacy_level VARCHAR(16) NOT NULL DEFAULT 'public' CHECK (privacy_level IN ('public','followers','close_friends')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id);
CREATE INDEX IF NOT EXISTS idx_stories_created_at ON stories(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stories_expires_at ON stories(expires_at DESC);

-- 2) Story views (dedupe by user_id + story_id)
CREATE TABLE IF NOT EXISTS story_views (
    story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (story_id, viewer_id)
);

-- 3) Close friends list (owner → friend)
CREATE TABLE IF NOT EXISTS story_close_friends (
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (owner_id, friend_id)
);

