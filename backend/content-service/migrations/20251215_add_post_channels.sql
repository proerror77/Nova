-- Migration: Add post-channel many-to-many relationship and enhance channels table
-- This enables content filtering by channel in feed

-- 1. Enhance channels table with UI/config fields
ALTER TABLE channels ADD COLUMN IF NOT EXISTS slug VARCHAR(50);
ALTER TABLE channels ADD COLUMN IF NOT EXISTS icon_url TEXT;
ALTER TABLE channels ADD COLUMN IF NOT EXISTS display_order INT DEFAULT 100;
ALTER TABLE channels ADD COLUMN IF NOT EXISTS is_enabled BOOLEAN DEFAULT TRUE;

-- Create unique index on slug for URL-friendly lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_channels_slug ON channels (slug) WHERE slug IS NOT NULL;

-- Index for listing enabled channels in order
CREATE INDEX IF NOT EXISTS idx_channels_enabled_order ON channels (is_enabled, display_order) WHERE is_enabled = TRUE;

-- 2. Create post_channels junction table (many-to-many)
CREATE TABLE IF NOT EXISTS post_channels (
    post_id UUID NOT NULL,
    channel_id UUID NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    confidence FLOAT DEFAULT 1.0,           -- Tagging confidence (1.0 = manual, <1.0 = AI)
    tagged_by VARCHAR(50) DEFAULT 'system', -- 'system', 'author', 'moderator', 'migration'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, channel_id)
);

-- Index for feed filtering by channel (most important query)
CREATE INDEX IF NOT EXISTS idx_post_channels_channel_id ON post_channels (channel_id);

-- Composite index for channel feed with ordering
CREATE INDEX IF NOT EXISTS idx_post_channels_channel_created ON post_channels (channel_id, created_at DESC);

-- Index for finding all channels a post belongs to
CREATE INDEX IF NOT EXISTS idx_post_channels_post_id ON post_channels (post_id);

-- 3. Update existing seed channels with slugs and display order
UPDATE channels SET
    slug = 'tech',
    display_order = 10,
    is_enabled = TRUE
WHERE id = '11111111-1111-1111-1111-111111111111' AND slug IS NULL;

UPDATE channels SET
    slug = 'startups',
    display_order = 20,
    is_enabled = TRUE
WHERE id = '22222222-2222-2222-2222-222222222222' AND slug IS NULL;

UPDATE channels SET
    slug = 'design',
    display_order = 30,
    is_enabled = TRUE
WHERE id = '33333333-3333-3333-3333-333333333333' AND slug IS NULL;

UPDATE channels SET
    slug = 'gaming',
    display_order = 40,
    is_enabled = TRUE
WHERE id = '44444444-4444-4444-4444-444444444444' AND slug IS NULL;

UPDATE channels SET
    slug = 'music',
    display_order = 50,
    is_enabled = TRUE
WHERE id = '55555555-5555-5555-5555-555555555555' AND slug IS NULL;

-- 4. Add more channels for the app (Fashion, Travel, Fitness, Pets, Study, Career)
INSERT INTO channels (id, name, description, category, slug, display_order, is_enabled)
VALUES
    ('66666666-6666-6666-6666-666666666666', 'Fashion', 'Style, trends, and outfit inspiration', 'lifestyle', 'fashion', 1, TRUE),
    ('77777777-7777-7777-7777-777777777777', 'Travel', 'Destinations, tips, and adventures', 'lifestyle', 'travel', 2, TRUE),
    ('88888888-8888-8888-8888-888888888888', 'Fitness', 'Workouts, health, and wellness', 'lifestyle', 'fitness', 3, TRUE),
    ('99999999-9999-9999-9999-999999999999', 'Pets', 'Cute animals and pet care', 'lifestyle', 'pets', 4, TRUE),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Study', 'Learning, education, and productivity', 'education', 'study', 5, TRUE),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Career', 'Jobs, career advice, and professional growth', 'business', 'career', 6, TRUE)
ON CONFLICT (id) DO UPDATE SET
    slug = EXCLUDED.slug,
    display_order = EXCLUDED.display_order,
    is_enabled = EXCLUDED.is_enabled;
