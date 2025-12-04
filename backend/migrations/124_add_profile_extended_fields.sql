-- ============================================
-- Migration: 124_add_profile_extended_fields
-- Description: Add extended profile fields (first_name, last_name, date_of_birth, gender)
-- Author: Nova Team
-- Date: 2025-12-03
-- ============================================

-- Create gender enum type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gender_type') THEN
        CREATE TYPE gender_type AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');
    END IF;
END $$;

-- Add extended profile fields to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS date_of_birth DATE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS gender gender_type;

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_users_first_name ON users(first_name) WHERE is_active = TRUE AND first_name IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_last_name ON users(last_name) WHERE is_active = TRUE AND last_name IS NOT NULL;

-- Comment on columns
COMMENT ON COLUMN users.first_name IS 'User first name (optional)';
COMMENT ON COLUMN users.last_name IS 'User last name (optional)';
COMMENT ON COLUMN users.date_of_birth IS 'User date of birth (optional, for age verification)';
COMMENT ON COLUMN users.gender IS 'User gender preference (optional)';
