-- ============================================================================
-- Social Service Complete Schema Migration
-- Version: 2.0
-- Purpose: Full social interaction schema with counters, triggers, and constraints
-- ============================================================================

-- ============ MIGRATION: Drop old schema if exists ============
-- WARNING: This is a complete rebuild. Use with caution in production.
DROP TABLE IF EXISTS comment_likes CASCADE;
DROP TABLE IF EXISTS processed_events CASCADE;
DROP TABLE IF EXISTS post_counters CASCADE;
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS shares CASCADE;
DROP TABLE IF EXISTS likes CASCADE;

-- Drop old triggers and functions
DROP TRIGGER IF EXISTS update_comments_updated_at ON comments;
-- Note: update_updated_at_column() function is shared across multiple tables, not dropping

-- ============ LIKES TABLE ============
CREATE TABLE IF NOT EXISTS likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT unique_like_per_user_per_post UNIQUE (post_id, user_id)
);

-- Indexes for likes
CREATE INDEX idx_likes_post_id ON likes(post_id);
CREATE INDEX idx_likes_user_id ON likes(user_id);
CREATE INDEX idx_likes_created_at ON likes(created_at DESC);

COMMENT ON TABLE likes IS 'User likes on posts';
COMMENT ON COLUMN likes.post_id IS 'Reference to post in content-service';
COMMENT ON COLUMN likes.user_id IS 'Reference to user in user-service';

-- ============ SHARES TABLE ============
CREATE TABLE IF NOT EXISTS shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    share_type VARCHAR(20) NOT NULL, -- REPOST, STORY, DM, EXTERNAL
    target_user_id UUID,              -- For DM shares only
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CHECK (share_type IN ('REPOST', 'STORY', 'DM', 'EXTERNAL')),
    CHECK (
        (share_type = 'DM' AND target_user_id IS NOT NULL) OR
        (share_type != 'DM' AND target_user_id IS NULL)
    )
);

-- Indexes for shares
CREATE INDEX idx_shares_post_id ON shares(post_id);
CREATE INDEX idx_shares_user_id ON shares(user_id);
CREATE INDEX idx_shares_created_at ON shares(created_at DESC);
CREATE INDEX idx_shares_share_type ON shares(share_type);
CREATE INDEX idx_shares_target_user_id ON shares(target_user_id) WHERE target_user_id IS NOT NULL;

COMMENT ON TABLE shares IS 'Post shares (repost/story/DM/external)';
COMMENT ON COLUMN shares.share_type IS 'Share type: REPOST (public repost), STORY (24h story), DM (direct message), EXTERNAL (off-platform)';
COMMENT ON COLUMN shares.target_user_id IS 'Target user for DM shares (NULL for other types)';

-- ============ COMMENTS TABLE ============
CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    parent_comment_id UUID,           -- NULL for top-level comments
    content TEXT NOT NULL,
    like_count BIGINT NOT NULL DEFAULT 0,
    reply_count BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

    -- Constraints
    CHECK (LENGTH(content) > 0 AND LENGTH(content) <= 2000),
    CHECK (like_count >= 0),
    CHECK (reply_count >= 0),
    CONSTRAINT fk_parent_comment FOREIGN KEY (parent_comment_id)
        REFERENCES comments(id) ON DELETE CASCADE
);

-- Indexes for comments
CREATE INDEX idx_comments_post_id ON comments(post_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_parent_id ON comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);
CREATE INDEX idx_comments_like_count ON comments(like_count DESC); -- For popular sort

COMMENT ON TABLE comments IS 'Post comments with threading support (max 2000 chars)';
COMMENT ON COLUMN comments.parent_comment_id IS 'NULL for top-level comments, points to parent for replies';
COMMENT ON COLUMN comments.like_count IS 'Denormalized count maintained by triggers';
COMMENT ON COLUMN comments.reply_count IS 'Denormalized count maintained by triggers';
COMMENT ON COLUMN comments.is_deleted IS 'Soft delete flag (preserves comment tree structure)';

-- ============ POST COUNTERS CACHE TABLE ============
CREATE TABLE IF NOT EXISTS post_counters (
    post_id UUID PRIMARY KEY,
    like_count BIGINT NOT NULL DEFAULT 0,
    comment_count BIGINT NOT NULL DEFAULT 0,
    share_count BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CHECK (like_count >= 0),
    CHECK (comment_count >= 0),
    CHECK (share_count >= 0)
);

-- Index for counter updates
CREATE INDEX idx_post_counters_updated_at ON post_counters(updated_at);

COMMENT ON TABLE post_counters IS 'Denormalized counters for fast reads (synced with Redis cache)';
COMMENT ON COLUMN post_counters.updated_at IS 'Last counter update timestamp (for cache invalidation)';

-- ============ COMMENT LIKES TABLE ============
CREATE TABLE IF NOT EXISTS comment_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT unique_comment_like_per_user UNIQUE (comment_id, user_id)
);

-- Indexes for comment likes
CREATE INDEX idx_comment_likes_comment_id ON comment_likes(comment_id);
CREATE INDEX idx_comment_likes_user_id ON comment_likes(user_id);

COMMENT ON TABLE comment_likes IS 'Likes on comments (separate from post likes)';

-- ============ IDEMPOTENT CONSUMER TABLE ============
CREATE TABLE IF NOT EXISTS processed_events (
    event_id VARCHAR(255) PRIMARY KEY,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processor_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_processed_events_created_at ON processed_events(created_at);
CREATE INDEX idx_processed_events_processor_name ON processed_events(processor_name);

COMMENT ON TABLE processed_events IS 'Idempotent event processing tracking (7 day retention)';
COMMENT ON COLUMN processed_events.event_id IS 'Unique event identifier (e.g., Kafka offset or message ID)';
COMMENT ON COLUMN processed_events.processor_name IS 'Name of the event processor (e.g., "LikeEventConsumer")';

-- ============================================================================
-- TRIGGERS FOR COUNTER MAINTENANCE
-- ============================================================================

-- ============ LIKE COUNT TRIGGERS ============

-- Trigger: Increment like_count when like is created
CREATE OR REPLACE FUNCTION increment_like_count() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO post_counters (post_id, like_count, updated_at)
    VALUES (NEW.post_id, 1, NOW())
    ON CONFLICT (post_id) DO UPDATE
    SET like_count = post_counters.like_count + 1,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_like_count
AFTER INSERT ON likes
FOR EACH ROW EXECUTE FUNCTION increment_like_count();

-- Trigger: Decrement like_count when like is deleted
CREATE OR REPLACE FUNCTION decrement_like_count() RETURNS TRIGGER AS $$
BEGIN
    UPDATE post_counters
    SET like_count = GREATEST(like_count - 1, 0),
        updated_at = NOW()
    WHERE post_id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_decrement_like_count
AFTER DELETE ON likes
FOR EACH ROW EXECUTE FUNCTION decrement_like_count();

-- ============ SHARE COUNT TRIGGERS ============

-- Trigger: Increment share_count
CREATE OR REPLACE FUNCTION increment_share_count() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO post_counters (post_id, share_count, updated_at)
    VALUES (NEW.post_id, 1, NOW())
    ON CONFLICT (post_id) DO UPDATE
    SET share_count = post_counters.share_count + 1,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_share_count
AFTER INSERT ON shares
FOR EACH ROW EXECUTE FUNCTION increment_share_count();

-- No decrement trigger for shares (shares are never deleted)

-- ============ COMMENT COUNT TRIGGERS ============

-- Trigger: Increment comment_count and parent reply_count
CREATE OR REPLACE FUNCTION increment_comment_count() RETURNS TRIGGER AS $$
BEGIN
    -- Only increment if not soft-deleted on creation
    IF NEW.is_deleted = FALSE THEN
        -- Increment post counter
        INSERT INTO post_counters (post_id, comment_count, updated_at)
        VALUES (NEW.post_id, 1, NOW())
        ON CONFLICT (post_id) DO UPDATE
        SET comment_count = post_counters.comment_count + 1,
            updated_at = NOW();

        -- If reply, increment parent comment reply_count
        IF NEW.parent_comment_id IS NOT NULL THEN
            UPDATE comments
            SET reply_count = reply_count + 1
            WHERE id = NEW.parent_comment_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_comment_count
AFTER INSERT ON comments
FOR EACH ROW EXECUTE FUNCTION increment_comment_count();

-- Trigger: Decrement comment_count when soft-deleted
CREATE OR REPLACE FUNCTION decrement_comment_count() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_deleted = TRUE AND OLD.is_deleted = FALSE THEN
        -- Decrement post counter
        UPDATE post_counters
        SET comment_count = GREATEST(comment_count - 1, 0),
            updated_at = NOW()
        WHERE post_id = NEW.post_id;

        -- If reply, decrement parent comment reply_count
        IF NEW.parent_comment_id IS NOT NULL THEN
            UPDATE comments
            SET reply_count = GREATEST(reply_count - 1, 0)
            WHERE id = NEW.parent_comment_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_decrement_comment_count
AFTER UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION decrement_comment_count();

-- ============ COMMENT LIKE COUNT TRIGGERS ============

-- Trigger: Increment comment like_count
CREATE OR REPLACE FUNCTION increment_comment_like_count() RETURNS TRIGGER AS $$
BEGIN
    UPDATE comments
    SET like_count = like_count + 1
    WHERE id = NEW.comment_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_comment_like_count
AFTER INSERT ON comment_likes
FOR EACH ROW EXECUTE FUNCTION increment_comment_like_count();

-- Trigger: Decrement comment like_count
CREATE OR REPLACE FUNCTION decrement_comment_like_count() RETURNS TRIGGER AS $$
BEGIN
    UPDATE comments
    SET like_count = GREATEST(like_count - 1, 0)
    WHERE id = OLD.comment_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_decrement_comment_like_count
AFTER DELETE ON comment_likes
FOR EACH ROW EXECUTE FUNCTION decrement_comment_like_count();

-- ============ COMMENT UPDATE TIMESTAMP TRIGGER ============

-- Trigger: Update comments.updated_at on content change
CREATE OR REPLACE FUNCTION update_comment_updated_at() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.content IS DISTINCT FROM OLD.content THEN
        NEW.updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_comment_updated_at
BEFORE UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION update_comment_updated_at();

-- ============================================================================
-- DATA RETENTION POLICY (Optional: Clean old events)
-- ============================================================================

-- Function to clean up old processed events (run via cron job)
CREATE OR REPLACE FUNCTION cleanup_old_processed_events(retention_days INT DEFAULT 7)
RETURNS INT AS $$
DECLARE
    deleted_count INT;
BEGIN
    DELETE FROM processed_events
    WHERE created_at < NOW() - (retention_days || ' days')::INTERVAL;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_processed_events IS 'Delete processed events older than retention_days (default 7)';

-- ============================================================================
-- VERIFICATION QUERIES (For testing)
-- ============================================================================

-- Example: Check trigger setup
-- SELECT tgname, tgtype, tgenabled FROM pg_trigger WHERE tgrelid = 'likes'::regclass;

-- Example: Verify indexes
-- SELECT indexname, indexdef FROM pg_indexes WHERE tablename IN ('likes', 'shares', 'comments', 'post_counters', 'comment_likes', 'processed_events');

-- Example: Test counter increment
-- INSERT INTO likes (post_id, user_id) VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');
-- SELECT * FROM post_counters WHERE post_id = '00000000-0000-0000-0000-000000000001';
