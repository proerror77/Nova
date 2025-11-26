-- Add media_urls support for posts so feed/content services can return image URLs.
-- This migration is backwards-compatible and backfills existing rows using media_key
-- when media_urls is empty (best-effort for legacy data).

-- Up
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS media_urls JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Backfill: for rows with a non-placeholder media_key, seed media_urls with that key.
UPDATE posts
SET media_urls = jsonb_build_array(media_key)
WHERE (media_urls IS NULL OR jsonb_array_length(media_urls) = 0)
  AND media_key IS NOT NULL
  AND media_key <> 'text-only';

-- Optional: add a GIN index for queries filtering on media URLs (idempotent).
CREATE INDEX IF NOT EXISTS idx_posts_media_urls_gin ON posts USING gin (media_urls);

-- Down
DROP INDEX IF EXISTS idx_posts_media_urls_gin;
ALTER TABLE posts DROP COLUMN IF EXISTS media_urls;
