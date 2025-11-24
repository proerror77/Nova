-- ============================================================================
-- Migration: 131_add_missing_user_fields
-- Description: Add missing user fields for iOS UserProfile model compatibility
-- Author: Nova Team
-- Date: 2025-11-24
-- iOS Model: ios/NovaSocial/Shared/Models/User/UserModels.swift:UserProfile
-- ============================================================================

-- ============ ADD NEW COLUMNS ============

-- Website field
ALTER TABLE users ADD COLUMN IF NOT EXISTS website VARCHAR(200);

-- Verification badge
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- Denormalized counters (for fast reads)
ALTER TABLE users ADD COLUMN IF NOT EXISTS following_count INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS post_count INT NOT NULL DEFAULT 0;

-- ============ INDEXES ============
CREATE INDEX IF NOT EXISTS idx_users_is_verified ON users(is_verified) WHERE is_verified = TRUE AND is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_users_post_count ON users(post_count DESC) WHERE is_active = TRUE AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_follower_count ON users(follower_count DESC) WHERE is_active = TRUE AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_following_count ON users(following_count DESC) WHERE is_active = TRUE AND deleted_at IS NULL;

-- ============ BACKFILL COUNTERS ============

-- Backfill following_count from follows table
UPDATE users u
SET following_count = COALESCE(
    (SELECT COUNT(*)::int FROM follows WHERE follower_id = u.id),
    0
)
WHERE following_count = 0;

-- Backfill post_count from posts table
UPDATE users u
SET post_count = COALESCE(
    (SELECT COUNT(*)::int FROM posts WHERE user_id = u.id AND soft_delete IS NULL),
    0
)
WHERE post_count = 0;

-- ============ TRIGGERS FOR COUNTER MAINTENANCE ============

-- Trigger: Maintain following_count
CREATE OR REPLACE FUNCTION update_user_following_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_following_count ON follows;
CREATE TRIGGER trigger_update_following_count
AFTER INSERT OR DELETE ON follows
FOR EACH ROW EXECUTE FUNCTION update_user_following_count();

-- Trigger: Maintain post_count
CREATE OR REPLACE FUNCTION update_user_post_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.soft_delete IS NULL THEN
        -- New post created
        UPDATE users SET post_count = post_count + 1 WHERE id = NEW.user_id;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Soft delete/restore
        IF NEW.soft_delete IS NOT NULL AND OLD.soft_delete IS NULL THEN
            -- Post soft-deleted
            UPDATE users SET post_count = GREATEST(post_count - 1, 0) WHERE id = NEW.user_id;
        ELSIF NEW.soft_delete IS NULL AND OLD.soft_delete IS NOT NULL THEN
            -- Post restored
            UPDATE users SET post_count = post_count + 1 WHERE id = NEW.user_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_post_count ON posts;
CREATE TRIGGER trigger_update_post_count
AFTER INSERT OR UPDATE ON posts
FOR EACH ROW EXECUTE FUNCTION update_user_post_count();

-- ============ CONSTRAINTS ============

-- Website URL validation
ALTER TABLE users ADD CONSTRAINT IF NOT EXISTS website_format
CHECK (website IS NULL OR website ~* '^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$');

-- Counter sanity checks
ALTER TABLE users ADD CONSTRAINT IF NOT EXISTS following_count_positive CHECK (following_count >= 0);
ALTER TABLE users ADD CONSTRAINT IF NOT EXISTS post_count_positive CHECK (post_count >= 0);

-- ============ COMMENTS FOR DOCUMENTATION ============
COMMENT ON COLUMN users.website IS 'User website URL (optional, must be valid HTTP/HTTPS URL)';
COMMENT ON COLUMN users.is_verified IS 'Verified badge (blue checkmark) - manually granted by admins';
COMMENT ON COLUMN users.following_count IS 'Number of users this user follows (denormalized, maintained by triggers)';
COMMENT ON COLUMN users.post_count IS 'Number of non-deleted posts by this user (denormalized, maintained by triggers)';

-- ============ LOG COMPLETION ============
DO $$
BEGIN
    RAISE NOTICE 'Migration 131 completed successfully';
    RAISE NOTICE 'Added fields: website, is_verified, following_count, post_count';
    RAISE NOTICE 'Backfilled counters for % users', (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL);
END $$;
