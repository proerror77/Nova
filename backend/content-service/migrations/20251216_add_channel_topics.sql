-- Add topic_keywords column for AI-powered post classification
-- This enables semantic matching between post content and channel topics

-- Add topic_keywords as a JSONB array to store keywords/themes for each channel
ALTER TABLE channels ADD COLUMN IF NOT EXISTS topic_keywords JSONB DEFAULT '[]'::jsonb;

-- Add embedding vector column for semantic similarity (optional, for future use)
-- Uncomment when pgvector is available:
-- ALTER TABLE channels ADD COLUMN IF NOT EXISTS topic_embedding vector(1536);

-- Create index for topic_keywords GIN queries (contains, overlap operations)
CREATE INDEX IF NOT EXISTS idx_channels_topic_keywords ON channels USING GIN (topic_keywords);

-- Seed topic keywords for existing channels
-- These keywords will be used to match post content for auto-classification

UPDATE channels SET topic_keywords = '["technology", "tech", "software", "hardware", "gadgets", "apps", "programming", "coding", "AI", "artificial intelligence", "machine learning", "startup", "innovation", "digital", "computer", "smartphone", "devices"]'::jsonb
WHERE slug = 'tech' OR name = 'Tech News';

UPDATE channels SET topic_keywords = '["startup", "business", "entrepreneur", "funding", "venture capital", "VC", "founder", "company", "investment", "pitch", "scale", "growth", "unicorn", "IPO", "acquisition", "Series A", "seed round"]'::jsonb
WHERE slug = 'startups' OR name = 'Startups';

UPDATE channels SET topic_keywords = '["design", "UI", "UX", "user interface", "user experience", "graphic design", "typography", "branding", "logo", "illustration", "creative", "Figma", "Sketch", "Adobe", "visual", "layout", "color", "aesthetic"]'::jsonb
WHERE slug = 'design' OR name = 'Design';

UPDATE channels SET topic_keywords = '["gaming", "game", "video game", "esports", "PlayStation", "Xbox", "Nintendo", "PC gaming", "Steam", "RPG", "FPS", "MMO", "streamer", "Twitch", "gameplay", "controller", "console"]'::jsonb
WHERE slug = 'gaming' OR name = 'Gaming';

UPDATE channels SET topic_keywords = '["music", "song", "album", "artist", "concert", "band", "singer", "musician", "playlist", "Spotify", "streaming", "genre", "rock", "pop", "hip hop", "jazz", "classical", "DJ", "producer"]'::jsonb
WHERE slug = 'music' OR name = 'Music';

UPDATE channels SET topic_keywords = '["fashion", "style", "outfit", "clothes", "clothing", "wear", "trend", "designer", "brand", "runway", "model", "accessory", "shoes", "dress", "streetwear", "luxury", "vintage", "shopping"]'::jsonb
WHERE slug = 'fashion' OR name = 'Fashion';

UPDATE channels SET topic_keywords = '["travel", "trip", "vacation", "destination", "explore", "adventure", "tourism", "hotel", "flight", "beach", "mountain", "city", "country", "backpacking", "passport", "journey", "wanderlust"]'::jsonb
WHERE slug = 'travel' OR name = 'Travel';

UPDATE channels SET topic_keywords = '["fitness", "workout", "exercise", "gym", "health", "wellness", "training", "muscle", "cardio", "yoga", "running", "weight", "nutrition", "diet", "protein", "bodybuilding", "CrossFit"]'::jsonb
WHERE slug = 'fitness' OR name = 'Fitness';

UPDATE channels SET topic_keywords = '["pets", "pet", "dog", "cat", "puppy", "kitten", "animal", "fur baby", "cute", "adorable", "rescue", "adoption", "veterinary", "vet", "breed", "walk", "play"]'::jsonb
WHERE slug = 'pets' OR name = 'Pets';

UPDATE channels SET topic_keywords = '["study", "education", "learning", "school", "university", "college", "student", "exam", "homework", "lecture", "course", "degree", "academic", "research", "knowledge", "tutorial", "lesson"]'::jsonb
WHERE slug = 'study' OR name = 'Study';

UPDATE channels SET topic_keywords = '["career", "job", "work", "professional", "employment", "resume", "interview", "salary", "promotion", "office", "workplace", "networking", "LinkedIn", "hire", "remote work", "skills", "mentor"]'::jsonb
WHERE slug = 'career' OR name = 'Career';

-- Log migration completion
DO $$
BEGIN
    RAISE NOTICE 'Channel topic_keywords migration completed. Updated % channels.',
        (SELECT COUNT(*) FROM channels WHERE topic_keywords != '[]'::jsonb);
END $$;
