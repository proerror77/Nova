-- ============================================
-- Migration: 201_add_bookmarks_schema
-- Description: Add bookmarks and bookmark collections tables for post saving
-- Author: Nova Team
-- Date: 2025-12-12
-- ============================================

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- Table: bookmark_collections
-- Description: Collections/folders for organizing bookmarks
-- Must be created BEFORE bookmarks table due to foreign key reference
-- ============================================
CREATE TABLE IF NOT EXISTS bookmark_collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_private BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bookmark_collections_user ON bookmark_collections(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmark_collections_created_at ON bookmark_collections(created_at DESC);

COMMENT ON TABLE bookmark_collections IS 'Collections for organizing saved/bookmarked posts';
COMMENT ON COLUMN bookmark_collections.is_private IS 'Whether the collection is visible only to the owner';

-- ============================================
-- Table: bookmarks
-- Description: User bookmarked/saved posts
-- ============================================
CREATE TABLE IF NOT EXISTS bookmarks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    bookmarked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    collection_id UUID REFERENCES bookmark_collections(id) ON DELETE SET NULL,
    UNIQUE(user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_post ON bookmarks(post_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_created_at ON bookmarks(bookmarked_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_collection ON bookmarks(collection_id);
-- Composite index for fetching user's bookmarks ordered by time
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_time ON bookmarks(user_id, bookmarked_at DESC);

COMMENT ON TABLE bookmarks IS 'User saved/bookmarked posts';
COMMENT ON COLUMN bookmarks.collection_id IS 'Optional collection to organize bookmarks into folders';

-- ============================================
-- Add bookmark_count column to posts if not exists
-- ============================================
ALTER TABLE posts ADD COLUMN IF NOT EXISTS bookmark_count INT DEFAULT 0;

-- ============================================
-- Trigger: Auto-update bookmark_count on posts
-- ============================================
CREATE OR REPLACE FUNCTION update_post_bookmark_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET bookmark_count = bookmark_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE posts SET bookmark_count = GREATEST(0, bookmark_count - 1) WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_post_bookmark_count ON bookmarks;

CREATE TRIGGER trg_update_post_bookmark_count
AFTER INSERT OR DELETE ON bookmarks
FOR EACH ROW
EXECUTE FUNCTION update_post_bookmark_count();

-- ============================================
-- Trigger: Auto-update updated_at for collections
-- ============================================
CREATE OR REPLACE FUNCTION update_bookmark_collections_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_bookmark_collections_updated_at ON bookmark_collections;

CREATE TRIGGER trg_update_bookmark_collections_updated_at
BEFORE UPDATE ON bookmark_collections
FOR EACH ROW
EXECUTE FUNCTION update_bookmark_collections_updated_at();

-- ============================================
-- Documentation
-- ============================================
COMMENT ON FUNCTION update_post_bookmark_count() IS 'Trigger function to maintain bookmark_count on posts table';
COMMENT ON FUNCTION update_bookmark_collections_updated_at() IS 'Trigger function to auto-update updated_at timestamp';
