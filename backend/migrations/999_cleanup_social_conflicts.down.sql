-- ============================================================================
-- Rollback: Re-enable deprecated social schema
-- ============================================================================

-- Re-enable triggers
ALTER TABLE post_shares ENABLE TRIGGER ALL;
ALTER TABLE social_metadata ENABLE TRIGGER ALL;
ALTER TABLE bookmarks ENABLE TRIGGER ALL;
ALTER TABLE bookmark_collections ENABLE TRIGGER ALL;

-- Remove deprecation warnings
COMMENT ON TABLE post_shares IS 'Post shares';
COMMENT ON TABLE social_metadata IS 'Social metadata counters';
COMMENT ON TABLE bookmarks IS 'User bookmarks';
COMMENT ON TABLE bookmark_collections IS 'Bookmark collections';

COMMENT ON COLUMN posts.share_count IS 'Number of shares';
COMMENT ON COLUMN posts.bookmark_count IS 'Number of bookmarks';
