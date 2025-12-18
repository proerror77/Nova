-- Migration: Clean up text-content placeholder URLs from media_urls
-- For text-only posts (media_type='none'), media_urls should be empty []
-- Previously, "text-content-{uuid}" placeholders were incorrectly inserted

-- Update posts where media_type is 'none' but media_urls contains text-content placeholders
UPDATE posts
SET media_urls = '[]'::jsonb,
    updated_at = NOW()
WHERE media_type = 'none'
  AND media_urls IS NOT NULL
  AND media_urls != '[]'::jsonb
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(media_urls) AS url
    WHERE url LIKE 'text-content-%'
  );

-- Also clean up any posts where media_urls only contains text-content placeholders
-- (in case media_type wasn't set correctly)
UPDATE posts
SET media_urls = '[]'::jsonb,
    media_type = 'none',
    updated_at = NOW()
WHERE media_urls IS NOT NULL
  AND media_urls != '[]'::jsonb
  AND (
    SELECT COUNT(*) FROM jsonb_array_elements_text(media_urls) AS url
    WHERE url LIKE 'text-content-%'
  ) = jsonb_array_length(media_urls)
  AND jsonb_array_length(media_urls) > 0;

-- Log the cleanup (optional - for tracking)
DO $$
DECLARE
    affected_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO affected_count
    FROM posts
    WHERE media_type = 'none' AND media_urls = '[]'::jsonb;

    RAISE NOTICE 'Text-content cleanup complete. Posts with media_type=none: %', affected_count;
END $$;
