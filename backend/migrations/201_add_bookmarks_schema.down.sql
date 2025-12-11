-- ============================================
-- Rollback Migration: 201_add_bookmarks_schema
-- Description: Remove bookmarks and bookmark collections tables
-- ============================================

-- Drop triggers first
DROP TRIGGER IF EXISTS trg_update_post_bookmark_count ON bookmarks;
DROP TRIGGER IF EXISTS trg_update_bookmark_collections_updated_at ON bookmark_collections;

-- Drop trigger functions
DROP FUNCTION IF EXISTS update_post_bookmark_count();
DROP FUNCTION IF EXISTS update_bookmark_collections_updated_at();

-- Drop indexes
DROP INDEX IF EXISTS idx_bookmarks_user;
DROP INDEX IF EXISTS idx_bookmarks_post;
DROP INDEX IF EXISTS idx_bookmarks_created_at;
DROP INDEX IF EXISTS idx_bookmarks_collection;
DROP INDEX IF EXISTS idx_bookmarks_user_time;
DROP INDEX IF EXISTS idx_bookmark_collections_user;
DROP INDEX IF EXISTS idx_bookmark_collections_created_at;

-- Drop tables (bookmarks first due to FK dependency)
DROP TABLE IF EXISTS bookmarks;
DROP TABLE IF EXISTS bookmark_collections;

-- Remove bookmark_count column from posts
ALTER TABLE posts DROP COLUMN IF EXISTS bookmark_count;
