-- Social graph query optimizations
-- Adds composite indexes to speed up common relationship lookups

-- Ensure fast existence checks and unfollow
CREATE INDEX IF NOT EXISTS idx_follows_pair ON follows(follower_id, following_id);

-- Speed up timelines and list pagination
CREATE INDEX IF NOT EXISTS idx_follows_follower_created ON follows(follower_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_follows_following_created ON follows(following_id, created_at DESC);

