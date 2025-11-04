-- ============================================
-- Migration: 069_support_text_posts
-- Description: Support text-only posts by adding 'text' to content_type constraint
-- Author: Nova Team
-- Date: 2025-11-03
-- ============================================

-- Step 1: Drop existing constraint
ALTER TABLE posts
DROP CONSTRAINT IF EXISTS posts_content_type_check;

-- Step 2: Add updated constraint with 'text' support
ALTER TABLE posts
ADD CONSTRAINT posts_content_type_check
CHECK (content_type IN ('image', 'video', 'mixed', 'text'));

-- Step 3: Update comment for documentation
COMMENT ON COLUMN posts.content_type IS 'Type of content: image (legacy images), video, mixed (both images and videos), or text (text-only posts)';

-- ============================================
-- Verification query (optional)
-- ============================================
-- SELECT constraint_name, check_clause
-- FROM information_schema.check_constraints
-- WHERE constraint_name = 'posts_content_type_check';
