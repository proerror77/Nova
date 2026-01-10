-- Rollback migration for 20260109_remove_unused_social_tables.sql
-- This recreates the tables that were removed
-- Use this ONLY if you need to rollback the migration

-- Recreate likes table
CREATE TABLE IF NOT EXISTS likes (
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX idx_likes_user_id ON likes(user_id);

COMMENT ON TABLE likes IS 'DEPRECATED: Use nova_social.likes instead. This table is kept for rollback purposes only.';

-- Recreate bookmarks table
CREATE TABLE IF NOT EXISTS bookmarks (
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX idx_bookmarks_user_id ON bookmarks(user_id);

COMMENT ON TABLE bookmarks IS 'DEPRECATED: Use nova_social.saved_posts instead. This table is kept for rollback purposes only.';

-- Note: Data will NOT be restored by this rollback
-- You must restore from backup if data recovery is needed
