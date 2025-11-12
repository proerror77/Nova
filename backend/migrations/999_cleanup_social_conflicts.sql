-- ============================================================================
-- Migration: Cleanup Social Schema Conflicts (Phase B)
-- Purpose: Remove old social tables before applying social-service schema
-- Safety: Only run in development with no production data
-- ============================================================================

-- WARNING: This migration will DROP tables. Backup first if data exists.
-- To backup: pg_dump -U postgres nova > backup_$(date +%Y%m%d).sql

-- ============ Step 1: Drop old social tables ============
DROP TABLE IF EXISTS post_shares CASCADE;
DROP TABLE IF EXISTS social_metadata CASCADE;
DROP TABLE IF EXISTS bookmarks CASCADE;
DROP TABLE IF EXISTS bookmark_collections CASCADE;

-- ============ Step 2: Drop related triggers ============
DROP TRIGGER IF EXISTS trg_update_post_share_count ON post_shares;
DROP TRIGGER IF EXISTS trg_update_post_bookmark_count ON bookmarks;
DROP TRIGGER IF EXISTS trg_update_bookmark_collections_updated_at ON bookmark_collections;

-- ============ Step 3: Drop related functions ============
DROP FUNCTION IF EXISTS update_post_share_count() CASCADE;
DROP FUNCTION IF EXISTS update_post_bookmark_count() CASCADE;
DROP FUNCTION IF EXISTS update_bookmark_collections_updated_at() CASCADE;

-- ============ Step 4: Remove orphaned columns in posts table ============
ALTER TABLE posts DROP COLUMN IF EXISTS share_count;
ALTER TABLE posts DROP COLUMN IF EXISTS bookmark_count;

-- ============================================================================
-- Next steps:
-- 1. Run: sqlx migrate run (applies this cleanup)
-- 2. Copy social-service schema:
--    cp backend/social-service/migrations/002_create_social_tables.sql \
--       backend/migrations/100_social_service_schema.sql
-- 3. Run: sqlx migrate run (applies new social schema)
-- ============================================================================
