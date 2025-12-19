-- Migration: 018_standardize_user_field_names.sql
-- Purpose: Standardize field names to match unified proto schema
-- Changes:
--   - users: private_account → is_private (add alias column)
--   - user_settings: allow_messages → dm_permission (enum), privacy_level (enum)
--
-- Strategy: Add new columns, keep old ones for backward compatibility
-- After all services migrated, remove old columns in future migration

-- ============================================================================
-- 1. Add is_private column to users (alias for private_account)
-- ============================================================================
DO $$
BEGIN
    -- Add is_private if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'is_private'
    ) THEN
        ALTER TABLE users ADD COLUMN is_private BOOLEAN;

        -- Copy existing data
        UPDATE users SET is_private = COALESCE(private_account, FALSE);

        -- Set default and not null
        ALTER TABLE users ALTER COLUMN is_private SET DEFAULT FALSE;
        ALTER TABLE users ALTER COLUMN is_private SET NOT NULL;

        -- Create trigger to keep columns in sync during transition
        CREATE OR REPLACE FUNCTION sync_private_account_fields()
        RETURNS TRIGGER AS $func$
        BEGIN
            IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
                -- Sync: prefer is_private if explicitly set, otherwise use private_account
                IF NEW.is_private IS DISTINCT FROM OLD.is_private THEN
                    NEW.private_account := NEW.is_private;
                ELSIF NEW.private_account IS DISTINCT FROM OLD.private_account THEN
                    NEW.is_private := NEW.private_account;
                END IF;
            END IF;
            RETURN NEW;
        END;
        $func$ LANGUAGE plpgsql;

        DROP TRIGGER IF EXISTS trg_sync_private_account ON users;
        CREATE TRIGGER trg_sync_private_account
            BEFORE INSERT OR UPDATE ON users
            FOR EACH ROW EXECUTE FUNCTION sync_private_account_fields();
    END IF;
END $$;

-- ============================================================================
-- 2. Add dm_permission enum and column to user_settings
-- ============================================================================

-- Create dm_permission enum type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dm_permission_type') THEN
        CREATE TYPE dm_permission_type AS ENUM (
            'anyone',
            'followers',
            'mutuals',
            'nobody'
        );
    END IF;
END $$;

-- Add dm_permission column
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_settings' AND column_name = 'dm_permission'
    ) THEN
        ALTER TABLE user_settings ADD COLUMN dm_permission dm_permission_type;

        -- Migrate from allow_messages boolean to dm_permission enum
        UPDATE user_settings
        SET dm_permission = CASE
            WHEN allow_messages = TRUE THEN 'anyone'::dm_permission_type
            WHEN allow_messages = FALSE THEN 'nobody'::dm_permission_type
            ELSE 'followers'::dm_permission_type  -- default
        END;

        -- Set default
        ALTER TABLE user_settings ALTER COLUMN dm_permission SET DEFAULT 'followers'::dm_permission_type;
        ALTER TABLE user_settings ALTER COLUMN dm_permission SET NOT NULL;
    END IF;
END $$;

-- ============================================================================
-- 3. Add privacy_level enum and column to user_settings
-- ============================================================================

-- Create privacy_level enum type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'privacy_level_type') THEN
        CREATE TYPE privacy_level_type AS ENUM (
            'public',
            'friends_only',
            'private'
        );
    END IF;
END $$;

-- Add privacy_level column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_settings' AND column_name = 'privacy_level'
    ) THEN
        ALTER TABLE user_settings ADD COLUMN privacy_level privacy_level_type DEFAULT 'public'::privacy_level_type NOT NULL;
    END IF;
END $$;

-- ============================================================================
-- 4. Rename cover_url to cover_photo_url in users table (if exists)
-- ============================================================================
DO $$
BEGIN
    -- Check if cover_url exists and cover_photo_url doesn't
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'cover_url'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'cover_photo_url'
    ) THEN
        -- Rename cover_url to cover_photo_url
        ALTER TABLE users RENAME COLUMN cover_url TO cover_photo_url;
    END IF;

    -- Ensure cover_photo_url exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'cover_photo_url'
    ) THEN
        ALTER TABLE users ADD COLUMN cover_photo_url TEXT DEFAULT '';
    END IF;
END $$;

-- ============================================================================
-- 5. Create index on new columns for performance
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_users_is_private ON users(is_private);
CREATE INDEX IF NOT EXISTS idx_user_settings_dm_permission ON user_settings(dm_permission);
CREATE INDEX IF NOT EXISTS idx_user_settings_privacy_level ON user_settings(privacy_level);

-- ============================================================================
-- 6. Add comments for documentation
-- ============================================================================
COMMENT ON COLUMN users.is_private IS 'Standardized: Whether account is private (replaces private_account)';
COMMENT ON COLUMN user_settings.dm_permission IS 'Standardized: Who can send DMs (replaces allow_messages boolean)';
COMMENT ON COLUMN user_settings.privacy_level IS 'Standardized: Account privacy level enum';

-- ============================================================================
-- Notes for future cleanup migration (019_remove_deprecated_columns.sql):
-- ============================================================================
-- After all services migrated:
-- ALTER TABLE users DROP COLUMN private_account;
-- ALTER TABLE user_settings DROP COLUMN allow_messages;
-- DROP TRIGGER trg_sync_private_account ON users;
-- DROP FUNCTION sync_private_account_fields();
