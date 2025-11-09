-- ============================================
-- Migration: 028_add_user_profile_fields
-- Description: Add user profile fields for public profiles
-- Author: Nova Team
-- Date: 2025-10-24
-- ============================================

-- Add profile fields to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500);
ALTER TABLE users ADD COLUMN IF NOT EXISTS cover_photo_url VARCHAR(500);
ALTER TABLE users ADD COLUMN IF NOT EXISTS location VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS private_account BOOLEAN NOT NULL DEFAULT FALSE;

-- Create index for private_account for queries
CREATE INDEX IF NOT EXISTS idx_users_private_account ON users(private_account) WHERE is_active = TRUE;

-- Create index for display_name for search
CREATE INDEX IF NOT EXISTS idx_users_display_name ON users(display_name) WHERE is_active = TRUE AND private_account = FALSE;
