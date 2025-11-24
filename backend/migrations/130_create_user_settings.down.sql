-- ============================================================================
-- Rollback: 130_create_user_settings
-- ============================================================================

-- Drop trigger
DROP TRIGGER IF EXISTS trigger_create_user_settings ON users;

-- Drop function
DROP FUNCTION IF EXISTS create_default_user_settings();

-- Drop table trigger
DROP TRIGGER IF EXISTS update_user_settings_updated_at ON user_settings;

-- Drop table
DROP TABLE IF EXISTS user_settings CASCADE;
