-- User feed preferences table for personalization
CREATE TABLE user_feed_preferences (
    user_id UUID PRIMARY KEY,
    -- Visibility flags
    show_muted_keywords BOOLEAN NOT NULL DEFAULT FALSE,
    show_blocked_users BOOLEAN NOT NULL DEFAULT FALSE,

    -- Content filters
    preferred_language VARCHAR(10) NOT NULL DEFAULT 'all',
    age_filter VARCHAR(20) NOT NULL DEFAULT 'all',
    safety_filter_level INT NOT NULL DEFAULT 1 CHECK (safety_filter_level >= 0 AND safety_filter_level <= 2),
    enable_ads BOOLEAN NOT NULL DEFAULT TRUE,

    -- JSON arrays for lists
    prioritized_topics JSONB,                  -- Topics/hashtags to prioritize
    muted_topics JSONB,                        -- Topics/hashtags to hide
    blocked_user_ids JSONB,                    -- User IDs to block (array of UUIDs)
    muted_keywords JSONB,                      -- Keywords to mute (array of strings)

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT preferences_user_fk FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- Create index for preference lookups
CREATE INDEX idx_user_preferences_user_id ON user_feed_preferences(user_id);

-- Add comment documenting the preference system
COMMENT ON TABLE user_feed_preferences IS 'User feed personalization preferences: language, age filter, safety level, muted/prioritized content.';
COMMENT ON COLUMN user_feed_preferences.safety_filter_level IS '0=off, 1=moderate (default), 2=strict';
COMMENT ON COLUMN user_feed_preferences.preferred_language IS 'Language code (e.g., "en", "zh", "all")';
COMMENT ON COLUMN user_feed_preferences.prioritized_topics IS 'JSON array of topic/hashtag strings to prioritize';
COMMENT ON COLUMN user_feed_preferences.blocked_user_ids IS 'JSON array of UUID strings of blocked users';
