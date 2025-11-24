-- ============================================================================
-- Rollback: 131_add_missing_user_fields
-- ============================================================================

-- Drop triggers
DROP TRIGGER IF EXISTS trigger_update_following_count ON follows;
DROP TRIGGER IF EXISTS trigger_update_post_count ON posts;

-- Drop functions
DROP FUNCTION IF EXISTS update_user_following_count();
DROP FUNCTION IF EXISTS update_user_post_count();

-- Drop constraints
ALTER TABLE users DROP CONSTRAINT IF EXISTS website_format;
ALTER TABLE users DROP CONSTRAINT IF EXISTS following_count_positive;
ALTER TABLE users DROP CONSTRAINT IF EXISTS post_count_positive;

-- Drop indexes
DROP INDEX IF EXISTS idx_users_is_verified;
DROP INDEX IF EXISTS idx_users_post_count;
DROP INDEX IF EXISTS idx_users_follower_count;
DROP INDEX IF EXISTS idx_users_following_count;

-- Drop columns
ALTER TABLE users DROP COLUMN IF EXISTS website;
ALTER TABLE users DROP COLUMN IF EXISTS is_verified;
ALTER TABLE users DROP COLUMN IF EXISTS following_count;
ALTER TABLE users DROP COLUMN IF EXISTS post_count;
