-- Migration: Remove unused social interaction tables from content-service
-- Date: 2026-01-09
-- Reason: Likes and bookmarks have been consolidated to social-service
--
-- Background:
-- - nova_social.likes is the single source of truth for likes
-- - nova_social.saved_posts is the single source of truth for bookmarks
-- - nova_content.likes and nova_content.bookmarks are no longer used
--
-- Related commits:
-- - fix(ios): fix likes read/write inconsistency by using social-service (2e70ace6)
-- - fix(ios): fix bookmark read/write inconsistency (previous commit)
--
-- IMPORTANT: Run this migration AFTER confirming:
-- 1. iOS app is using social-service for all reads/writes
-- 2. No other services are reading from these tables
-- 3. Backup has been taken

-- Drop unused likes table
DROP TABLE IF EXISTS likes CASCADE;

-- Drop unused bookmarks table
DROP TABLE IF EXISTS bookmarks CASCADE;

-- Drop unused shares table (if social-service is the source of truth)
-- Uncomment after verifying shares are also consolidated
-- DROP TABLE IF EXISTS shares CASCADE;

-- Add comment to migration history
COMMENT ON SCHEMA public IS 'Removed unused social interaction tables (likes, bookmarks) - consolidated to social-service';
