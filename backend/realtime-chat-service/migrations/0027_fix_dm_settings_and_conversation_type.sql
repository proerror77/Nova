-- ============================================================================
-- 0027_fix_dm_settings_and_conversation_type
-- Purpose:
--   - Add generated column conversation_type derived from existing "kind"
--   - Provide user_settings table expected by code paths (DM permissions)
--   - Provide follows table so mutual-follow checks have a backing table
-- Notes:
--   - Idempotent: safe to run on existing databases
--   - Backfills user_settings from dm_permissions when present
-- ============================================================================

BEGIN;

-- Align schema with application queries: generated column from existing "kind"
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS conversation_type conversation_type
  GENERATED ALWAYS AS (kind) STORED;

-- DM settings table (used by RelationshipService)
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY,
    dm_permission VARCHAR(20) NOT NULL DEFAULT 'mutuals',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT dm_permission_check CHECK (dm_permission IN ('anyone','followers','mutuals','nobody'))
);

-- Backfill from legacy dm_permissions table if it exists
DO $$
BEGIN
    IF to_regclass('public.dm_permissions') IS NOT NULL THEN
        INSERT INTO user_settings (user_id, dm_permission, created_at, updated_at)
        SELECT
            user_id,
            dm_permission,
            COALESCE(created_at, NOW()),
            COALESCE(updated_at, NOW())
        FROM dm_permissions
        ON CONFLICT (user_id) DO NOTHING;
    END IF;
END$$;

-- Follows table for mutual-follow checks (lightweight local copy)
CREATE TABLE IF NOT EXISTS follows (
    follower_id UUID NOT NULL,
    following_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT no_self_follow CHECK (follower_id <> following_id)
);

COMMIT;
