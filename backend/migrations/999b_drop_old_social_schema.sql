-- ============================================================================
-- Migration: FINAL DROP of Old Social Schema (Phase B-Final)
-- Purpose: Actually drop deprecated social tables after migration
-- Context: Run ONLY after confirming migration to social-service schema
-- Safety: This is the CONTRACT phase - data will be permanently deleted
-- ============================================================================

-- ⚠️⚠️⚠️ WARNING ⚠️⚠️⚠️
-- This migration PERMANENTLY DELETES DATA
-- DO NOT RUN unless:
-- 1. Data has been migrated to social-service schema (migration 100)
-- 2. All services have been updated to use new schema
-- 3. Production backup has been verified
-- ============================================================================

-- ============ Drop old social tables ============
DROP TABLE IF EXISTS post_shares CASCADE;
DROP TABLE IF EXISTS social_metadata CASCADE;
DROP TABLE IF EXISTS bookmarks CASCADE;
DROP TABLE IF EXISTS bookmark_collections CASCADE;

-- ============ Drop related triggers ============
DROP TRIGGER IF EXISTS trg_update_post_share_count ON post_shares;
DROP TRIGGER IF EXISTS trg_update_post_bookmark_count ON bookmarks;
DROP TRIGGER IF EXISTS trg_update_bookmark_collections_updated_at ON bookmark_collections;

-- ============ Drop related functions ============
DROP FUNCTION IF EXISTS update_post_share_count() CASCADE;
DROP FUNCTION IF EXISTS update_post_bookmark_count() CASCADE;
DROP FUNCTION IF EXISTS update_bookmark_collections_updated_at() CASCADE;

-- ============ Remove orphaned columns in posts table ============
ALTER TABLE posts DROP COLUMN IF EXISTS share_count;
ALTER TABLE posts DROP COLUMN IF EXISTS bookmark_count;
