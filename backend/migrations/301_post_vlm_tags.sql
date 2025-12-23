-- ============================================
-- Migration: 301_post_vlm_tags
-- Description: Add VLM-generated tags for posts and enhance channels for auto-classification
-- Author: Nova Team
-- Date: 2025-12-23
-- ============================================

-- ============================================
-- 1. Table: post_tags
-- Description: VLM-generated and user-provided tags for posts
-- ============================================
CREATE TABLE IF NOT EXISTS post_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag VARCHAR(100) NOT NULL,

    -- VLM confidence score (0.0 - 1.0)
    confidence FLOAT NOT NULL DEFAULT 1.0 CHECK (confidence >= 0.0 AND confidence <= 1.0),

    -- Source of the tag: 'vlm' (auto), 'user' (manual), 'alice' (Alice AI)
    source VARCHAR(30) NOT NULL DEFAULT 'vlm',

    -- VLM provider info for debugging/analytics
    vlm_provider VARCHAR(30),  -- 'google_vision', 'openai_gpt4o', etc.

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Prevent duplicate tags per post
    CONSTRAINT unique_post_tag UNIQUE (post_id, tag),
    CONSTRAINT source_valid CHECK (source IN ('vlm', 'user', 'alice'))
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_post_tags_post_id ON post_tags(post_id);
CREATE INDEX IF NOT EXISTS idx_post_tags_tag ON post_tags(tag);
CREATE INDEX IF NOT EXISTS idx_post_tags_confidence ON post_tags(confidence DESC) WHERE confidence >= 0.7;
CREATE INDEX IF NOT EXISTS idx_post_tags_source ON post_tags(source);

-- Composite index for finding posts with specific tags
CREATE INDEX IF NOT EXISTS idx_post_tags_tag_confidence ON post_tags(tag, confidence DESC);

-- ============================================
-- 2. Add VLM processing status fields to posts table
-- ============================================
ALTER TABLE posts ADD COLUMN IF NOT EXISTS vlm_status VARCHAR(30) DEFAULT 'pending';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS vlm_processed_at TIMESTAMPTZ;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS vlm_error_message TEXT;

-- Add constraint for vlm_status values
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'vlm_status_valid'
    ) THEN
        ALTER TABLE posts ADD CONSTRAINT vlm_status_valid
            CHECK (vlm_status IN ('pending', 'processing', 'completed', 'failed', 'skipped'));
    END IF;
END $$;

-- Index for finding posts pending VLM processing
CREATE INDEX IF NOT EXISTS idx_posts_vlm_status ON posts(vlm_status)
    WHERE vlm_status IN ('pending', 'processing');

-- Index for finding recently processed posts
CREATE INDEX IF NOT EXISTS idx_posts_vlm_processed_at ON posts(vlm_processed_at DESC)
    WHERE vlm_processed_at IS NOT NULL;

-- ============================================
-- 3. Enhance channels table with VLM keywords
-- Description: Weighted keywords for matching VLM-generated tags to channels
-- Format: [{"keyword": "fashion", "weight": 1.0}, {"keyword": "style", "weight": 0.8}]
-- ============================================
ALTER TABLE channels ADD COLUMN IF NOT EXISTS vlm_keywords JSONB DEFAULT '[]';

-- GIN index for efficient JSONB containment queries
CREATE INDEX IF NOT EXISTS idx_channels_vlm_keywords ON channels USING GIN (vlm_keywords);

-- ============================================
-- 4. Populate vlm_keywords from existing topic_keywords
-- This is a one-time migration to bootstrap the keywords
-- ============================================
UPDATE channels
SET vlm_keywords = (
    SELECT COALESCE(
        jsonb_agg(jsonb_build_object('keyword', LOWER(kw), 'weight', 1.0)),
        '[]'::jsonb
    )
    FROM jsonb_array_elements_text(
        CASE
            WHEN topic_keywords IS NOT NULL AND topic_keywords != ''
            THEN topic_keywords::jsonb
            ELSE '[]'::jsonb
        END
    ) AS kw
)
WHERE vlm_keywords = '[]' OR vlm_keywords IS NULL;

-- ============================================
-- 5. Seed VLM keywords for existing channels
-- Based on the seed channels from 20251122_add_channels.sql
-- ============================================

-- Fashion channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "fashion", "weight": 1.0},
    {"keyword": "style", "weight": 1.0},
    {"keyword": "outfit", "weight": 0.9},
    {"keyword": "clothing", "weight": 0.9},
    {"keyword": "dress", "weight": 0.8},
    {"keyword": "streetwear", "weight": 0.8},
    {"keyword": "accessories", "weight": 0.7},
    {"keyword": "model", "weight": 0.6}
]'::jsonb
WHERE id = '66666666-6666-6666-6666-666666666666' OR slug = 'fashion';

-- Travel channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "travel", "weight": 1.0},
    {"keyword": "vacation", "weight": 1.0},
    {"keyword": "beach", "weight": 0.9},
    {"keyword": "mountain", "weight": 0.9},
    {"keyword": "landscape", "weight": 0.8},
    {"keyword": "hotel", "weight": 0.8},
    {"keyword": "city", "weight": 0.6},
    {"keyword": "nature", "weight": 0.7}
]'::jsonb
WHERE id = '77777777-7777-7777-7777-777777777777' OR slug = 'travel';

-- Fitness channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "fitness", "weight": 1.0},
    {"keyword": "gym", "weight": 1.0},
    {"keyword": "workout", "weight": 1.0},
    {"keyword": "exercise", "weight": 0.9},
    {"keyword": "muscle", "weight": 0.8},
    {"keyword": "yoga", "weight": 0.8},
    {"keyword": "running", "weight": 0.8},
    {"keyword": "sports", "weight": 0.7}
]'::jsonb
WHERE id = '88888888-8888-8888-8888-888888888888' OR slug = 'fitness';

-- Pets channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "pet", "weight": 1.0},
    {"keyword": "dog", "weight": 1.0},
    {"keyword": "cat", "weight": 1.0},
    {"keyword": "puppy", "weight": 0.9},
    {"keyword": "kitten", "weight": 0.9},
    {"keyword": "animal", "weight": 0.8},
    {"keyword": "cute", "weight": 0.5}
]'::jsonb
WHERE id = '99999999-9999-9999-9999-999999999999' OR slug = 'pets';

-- Study channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "study", "weight": 1.0},
    {"keyword": "book", "weight": 0.9},
    {"keyword": "education", "weight": 0.9},
    {"keyword": "school", "weight": 0.8},
    {"keyword": "university", "weight": 0.8},
    {"keyword": "learning", "weight": 0.8},
    {"keyword": "desk", "weight": 0.6}
]'::jsonb
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' OR slug = 'study';

-- Career channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "career", "weight": 1.0},
    {"keyword": "office", "weight": 0.9},
    {"keyword": "work", "weight": 0.8},
    {"keyword": "business", "weight": 0.8},
    {"keyword": "meeting", "weight": 0.7},
    {"keyword": "professional", "weight": 0.7},
    {"keyword": "laptop", "weight": 0.5}
]'::jsonb
WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' OR slug = 'career';

-- Tech channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "technology", "weight": 1.0},
    {"keyword": "tech", "weight": 1.0},
    {"keyword": "computer", "weight": 0.9},
    {"keyword": "phone", "weight": 0.8},
    {"keyword": "gadget", "weight": 0.8},
    {"keyword": "software", "weight": 0.8},
    {"keyword": "electronic", "weight": 0.7}
]'::jsonb
WHERE id = '11111111-1111-1111-1111-111111111111' OR slug = 'tech';

-- Gaming channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "gaming", "weight": 1.0},
    {"keyword": "game", "weight": 1.0},
    {"keyword": "esports", "weight": 0.9},
    {"keyword": "controller", "weight": 0.8},
    {"keyword": "console", "weight": 0.8},
    {"keyword": "video game", "weight": 0.9},
    {"keyword": "stream", "weight": 0.6}
]'::jsonb
WHERE id = '44444444-4444-4444-4444-444444444444' OR slug = 'gaming';

-- Music channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "music", "weight": 1.0},
    {"keyword": "concert", "weight": 0.9},
    {"keyword": "musician", "weight": 0.9},
    {"keyword": "guitar", "weight": 0.8},
    {"keyword": "piano", "weight": 0.8},
    {"keyword": "singer", "weight": 0.8},
    {"keyword": "band", "weight": 0.8},
    {"keyword": "instrument", "weight": 0.7}
]'::jsonb
WHERE id = '55555555-5555-5555-5555-555555555555' OR slug = 'music';

-- Design channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "design", "weight": 1.0},
    {"keyword": "ui", "weight": 0.9},
    {"keyword": "ux", "weight": 0.9},
    {"keyword": "illustration", "weight": 0.8},
    {"keyword": "art", "weight": 0.7},
    {"keyword": "creative", "weight": 0.7},
    {"keyword": "graphic", "weight": 0.8}
]'::jsonb
WHERE id = '33333333-3333-3333-3333-333333333333' OR slug = 'design';

-- Startups channel keywords
UPDATE channels SET vlm_keywords = '[
    {"keyword": "startup", "weight": 1.0},
    {"keyword": "entrepreneur", "weight": 0.9},
    {"keyword": "founder", "weight": 0.9},
    {"keyword": "pitch", "weight": 0.8},
    {"keyword": "investor", "weight": 0.8},
    {"keyword": "product", "weight": 0.6}
]'::jsonb
WHERE id = '22222222-2222-2222-2222-222222222222' OR slug = 'startups';

-- ============================================
-- 6. Trigger: Update updated_at timestamp on post_tags
-- ============================================
CREATE OR REPLACE FUNCTION update_post_tags_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_post_tags_updated_at ON post_tags;
CREATE TRIGGER update_post_tags_updated_at
    BEFORE UPDATE ON post_tags
    FOR EACH ROW
    EXECUTE FUNCTION update_post_tags_updated_at();

-- ============================================
-- 7. Comments for documentation
-- ============================================
COMMENT ON TABLE post_tags IS 'VLM-generated and user-provided tags for posts, used for search and channel matching';
COMMENT ON COLUMN post_tags.source IS 'Tag source: vlm (auto-generated by VLM), user (manually added), alice (Alice AI suggestions)';
COMMENT ON COLUMN post_tags.confidence IS 'VLM confidence score (0.0-1.0), higher means more confident';
COMMENT ON COLUMN post_tags.vlm_provider IS 'VLM provider used: google_vision, openai_gpt4o, etc.';

COMMENT ON COLUMN posts.vlm_status IS 'VLM processing status: pending (not processed), processing (in progress), completed (done), failed (error), skipped (no images)';
COMMENT ON COLUMN posts.vlm_processed_at IS 'Timestamp when VLM processing completed';
COMMENT ON COLUMN posts.vlm_error_message IS 'Error message if VLM processing failed';

COMMENT ON COLUMN channels.vlm_keywords IS 'Weighted keywords for VLM-based channel matching. Format: [{"keyword": "fashion", "weight": 1.0}]';
