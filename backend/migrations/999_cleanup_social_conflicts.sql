-- ============================================================================
-- Migration: Cleanup Social Schema Conflicts (Phase B) - SAFE VERSION
-- Purpose: Mark old social tables as deprecated before applying social-service schema
-- Safety: Uses expand-contract pattern to avoid data loss
-- ============================================================================

-- ⚠️ EXPAND PHASE: Mark tables as deprecated without dropping
-- Tables will be dropped in a future migration after migration is confirmed

-- Add deprecation notices via comments
COMMENT ON TABLE post_shares IS '⚠️ DEPRECATED: Use social-service schema (shares table). Will be dropped after migration.';
COMMENT ON TABLE social_metadata IS '⚠️ DEPRECATED: Use social-service schema (post_counters table). Will be dropped after migration.';
COMMENT ON TABLE bookmarks IS '⚠️ DEPRECATED: Feature removed. Will be dropped after confirmation.';
COMMENT ON TABLE bookmark_collections IS '⚠️ DEPRECATED: Feature removed. Will be dropped after confirmation.';

-- Disable triggers to prevent accidental writes
ALTER TABLE post_shares DISABLE TRIGGER ALL;
ALTER TABLE social_metadata DISABLE TRIGGER ALL;
ALTER TABLE bookmarks DISABLE TRIGGER ALL;
ALTER TABLE bookmark_collections DISABLE TRIGGER ALL;

-- Mark columns as deprecated (do not drop yet)
COMMENT ON COLUMN posts.share_count IS '⚠️ DEPRECATED: Use social-service post_counters table';
COMMENT ON COLUMN posts.bookmark_count IS '⚠️ DEPRECATED: Feature removed';

-- ============================================================================
-- Next steps:
-- 1. Verify social-service schema is deployed (migration 100)
-- 2. Migrate data from old tables to new schema
-- 3. Confirm no services are using deprecated tables/columns
-- 4. Apply migration 999_down.sql to actually drop tables
-- ============================================================================
