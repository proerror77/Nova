-- ============================================
-- Migration: 085_schema_reconciliation
-- Description:
--   - Ensure tables/views required by services exist in canonical database
--   - Provide user_profiles updatable view backed by users table
--   - Create user_permissions table for auth-service authorization RPCs
--   - Create blocked_users table used by social graph APIs
--   - Ensure users.public_key column exists for E2EE key storage
-- ============================================

-- 1. Ensure public_key column exists on users
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS public_key VARCHAR(128);

COMMENT ON COLUMN users.public_key IS 'Base64-encoded public key for end-to-end encryption flows';

-- 2. Create user_permissions table if missing
CREATE TABLE IF NOT EXISTS user_permissions (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    permission TEXT NOT NULL,
    granted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    granted_by UUID NULL,
    notes TEXT,
    CONSTRAINT pk_user_permissions PRIMARY KEY (user_id, permission)
);

COMMENT ON TABLE user_permissions IS 'Application-level permissions granted to users';
COMMENT ON COLUMN user_permissions.permission IS 'Permission/resource identifier (e.g. posts:create)';
COMMENT ON COLUMN user_permissions.granted_by IS 'Admin user who granted the permission (nullable)';

-- 3. Create blocked_users table for social graph enforcement
CREATE TABLE IF NOT EXISTS blocked_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT blocked_users_unique UNIQUE (blocker_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker_id ON blocked_users(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked_id ON blocked_users(blocked_user_id);

COMMENT ON TABLE blocked_users IS 'Tracks user blocks to enforce privacy & abuse prevention';

-- 4. Updatable user_profiles view for cross-service reads
CREATE OR REPLACE VIEW user_profiles AS
SELECT
    u.id,
    u.username,
    u.email,
    u.display_name,
    u.bio,
    u.avatar_url,
    u.cover_photo_url AS cover_url,
    NULL::TEXT AS website,
    u.location,
    u.email_verified AS is_verified,
    COALESCE(u.private_account, FALSE) AS is_private,
    0::BIGINT AS follower_count,
    0::BIGINT AS following_count,
    0::BIGINT AS post_count,
    u.created_at,
    u.updated_at,
    u.deleted_at
FROM users u;

COMMENT ON VIEW user_profiles IS 'Updatable projection of users table consumed by legacy user-service RPCs';

-- 5. INSTEAD OF UPDATE trigger so legacy services update underlying users table
CREATE OR REPLACE FUNCTION user_profiles_update()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users
    SET
        display_name = NEW.display_name,
        bio = NEW.bio,
        avatar_url = NEW.avatar_url,
        cover_photo_url = NEW.cover_url,
        location = NEW.location,
        private_account = COALESCE(NEW.is_private, private_account),
        updated_at = COALESCE(NEW.updated_at, NOW())
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_profiles_update ON user_profiles;
CREATE TRIGGER trg_user_profiles_update
INSTEAD OF UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION user_profiles_update();
