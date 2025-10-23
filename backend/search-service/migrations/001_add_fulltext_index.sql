-- Migration: Add full-text search index for posts.caption
-- This significantly improves search performance by avoiding
-- to_tsvector() computation on every query.

-- Create GIN index for full-text search on posts.caption
CREATE INDEX IF NOT EXISTS idx_posts_caption_fts
ON posts USING GIN(to_tsvector('english', COALESCE(caption, '')));

-- Optional: Create index for posts filtering conditions
-- (improves performance when combined with full-text search)
CREATE INDEX IF NOT EXISTS idx_posts_search_filter
ON posts(soft_delete, status)
WHERE soft_delete IS NULL AND status = 'published';

-- Add comment for documentation
COMMENT ON INDEX idx_posts_caption_fts IS
'GIN index for full-text search on posts caption field (English)';

COMMENT ON INDEX idx_posts_search_filter IS
'Partial index for posts search filtering (active published posts only)';
