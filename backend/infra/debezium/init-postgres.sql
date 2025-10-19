-- Enable logical replication for Debezium CDC
ALTER SYSTEM SET wal_level = 'logical';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;

-- Create heartbeat table for Debezium health monitoring
CREATE TABLE IF NOT EXISTS public.debezium_heartbeat (
  id INT PRIMARY KEY,
  ts TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO public.debezium_heartbeat (id, ts) VALUES (1, NOW())
ON CONFLICT (id) DO NOTHING;

-- Grant replication permissions (required for CDC)
ALTER USER postgres WITH REPLICATION;

-- Create publication for Debezium (will be auto-created by connector, but explicit is better)
-- This will be created by Debezium with publication.autocreate.mode=filtered
-- But we can pre-create it for clarity:
-- CREATE PUBLICATION debezium_publication FOR TABLE public.users, public.posts, public.follows, public.comments, public.likes;

-- Create indexes for common CDC query patterns (optional optimization)
-- These would be in your main schema migration, but listing here for reference:
-- CREATE INDEX IF NOT EXISTS idx_posts_created_at ON public.posts(created_at);
-- CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);
-- CREATE INDEX IF NOT EXISTS idx_follows_follower_id ON public.follows(follower_id);
-- CREATE INDEX IF NOT EXISTS idx_follows_followed_id ON public.follows(followed_id);
-- CREATE INDEX IF NOT EXISTS idx_comments_post_id ON public.comments(post_id);
-- CREATE INDEX IF NOT EXISTS idx_likes_post_id ON public.likes(post_id);

COMMENT ON TABLE public.debezium_heartbeat IS 'Heartbeat table for Debezium connector health monitoring';
