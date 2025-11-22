-- Add channels catalog for interest-based subscriptions
CREATE TABLE IF NOT EXISTS channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    subscriber_count BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_channels_category ON channels (category);
CREATE INDEX IF NOT EXISTS idx_channels_name_trgm ON channels USING gin (name gin_trgm_ops);

-- Seed a minimal set of default channels (idempotent)
INSERT INTO channels (id, name, description, category)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'Tech News', 'Latest updates in technology', 'tech'),
    ('22222222-2222-2222-2222-222222222222', 'Startups', 'Founder stories and product launches', 'business'),
    ('33333333-3333-3333-3333-333333333333', 'Design', 'UI/UX and product design inspiration', 'design'),
    ('44444444-4444-4444-4444-444444444444', 'Gaming', 'Games, esports, and livestreams', 'entertainment'),
    ('55555555-5555-5555-5555-555555555555', 'Music', 'New releases and playlists', 'entertainment')
ON CONFLICT (id) DO NOTHING;
