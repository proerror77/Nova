-- ============================================================================
-- 0029_deprecate_local_user_settings
-- Purpose:
--   - Mark local user_settings table as deprecated
--   - dm_permission is now read from identity-service (single source of truth)
--   - This migration adds deprecation notices but does NOT delete data
--   - A future migration will remove this table entirely once all code paths
--     have been migrated to use identity-service
--
-- P0 Migration: dm_permission Single Source of Truth
-- ============================================================================

BEGIN;

-- Add deprecation comment to user_settings table
COMMENT ON TABLE user_settings IS
    'DEPRECATED: This table is deprecated as of P0 migration. '
    'dm_permission and other user settings are now managed by identity-service. '
    'Read settings via identity-service gRPC API: GET /api/v2/auth/users/{user_id}/settings. '
    'This table will be removed in a future migration.';

-- Add deprecation comment to dm_permission column
COMMENT ON COLUMN user_settings.dm_permission IS
    'DEPRECATED: Use identity-service GetUserSettings API instead. '
    'This column is no longer the source of truth.';

-- Create a view that indicates the migration status
-- This can be used by operators to track migration progress
CREATE OR REPLACE VIEW user_settings_migration_status AS
SELECT
    'realtime-chat-service' AS service,
    'user_settings' AS table_name,
    'deprecated' AS status,
    'identity-service' AS source_of_truth,
    COUNT(*) AS local_records_count,
    NOW() AS checked_at
FROM user_settings;

COMMENT ON VIEW user_settings_migration_status IS
    'Migration status view for P0 user settings consolidation. '
    'Shows the current state of the deprecated local user_settings table.';

COMMIT;
