-- ============================================
-- ClickHouse Test Data Generator
-- Version: 1.0.0
-- Date: 2025-10-18
-- Purpose: Sample data for local testing
-- ============================================

USE nova_analytics;

-- ============================================
-- Test Data: Users
-- ============================================
-- Create sample user IDs for testing
-- In production, these come from PostgreSQL CDC

-- User 1: Alice (active creator)
SET @alice_id = '11111111-1111-1111-1111-111111111111';

-- User 2: Bob (casual user)
SET @bob_id = '22222222-2222-2222-2222-222222222222';

-- User 3: Charlie (influencer)
SET @charlie_id = '33333333-3333-3333-3333-333333333333';

-- User 4: Diana (new user)
SET @diana_id = '44444444-4444-4444-4444-444444444444';

-- ============================================
-- Test Data: Posts
-- ============================================
INSERT INTO posts (id, user_id, caption, image_key, status, created_at, updated_at, soft_delete, __op, __deleted, __version) VALUES
-- Alice's posts (3 posts)
('aaaaaaaa-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Beautiful sunset in San Francisco! #sunset #photography', 'posts/alice/sunset.jpg', 'published', now() - INTERVAL 2 HOUR, now() - INTERVAL 2 HOUR, NULL, 'c', 0, 1697625600),
('aaaaaaaa-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Coffee and coding ☕️ #devlife #work', 'posts/alice/coffee.jpg', 'published', now() - INTERVAL 12 HOUR, now() - INTERVAL 12 HOUR, NULL, 'c', 0, 1697625600),
('aaaaaaaa-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Weekend vibes 🌊 #travel #beach', 'posts/alice/beach.jpg', 'published', now() - INTERVAL 36 HOUR, now() - INTERVAL 36 HOUR, NULL, 'c', 0, 1697625600),

-- Bob's posts (2 posts)
('bbbbbbbb-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Just finished my first marathon! 🏃‍♂️ #fitness #achievement', 'posts/bob/marathon.jpg', 'published', now() - INTERVAL 6 HOUR, now() - INTERVAL 6 HOUR, NULL, 'c', 0, 1697625600),
('bbbbbbbb-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Homemade pizza 🍕 #cooking #foodie', 'posts/bob/pizza.jpg', 'published', now() - INTERVAL 24 HOUR, now() - INTERVAL 24 HOUR, NULL, 'c', 0, 1697625600),

-- Charlie's posts (5 posts - influencer)
('cccccccc-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'New product launch! Check out my bio for details 🚀 #sponsored #tech', 'posts/charlie/product.jpg', 'published', now() - INTERVAL 1 HOUR, now() - INTERVAL 1 HOUR, NULL, 'c', 0, 1697625600),
('cccccccc-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', 'Behind the scenes of my photoshoot 📸 #bts #photography', 'posts/charlie/bts.jpg', 'published', now() - INTERVAL 8 HOUR, now() - INTERVAL 8 HOUR, NULL, 'c', 0, 1697625600),
('cccccccc-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'Travel tips for Japan 🇯🇵 #travel #tips', 'posts/charlie/japan.jpg', 'published', now() - INTERVAL 18 HOUR, now() - INTERVAL 18 HOUR, NULL, 'c', 0, 1697625600),
('cccccccc-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Q&A session tonight at 8pm! #liveQA', 'posts/charlie/qa.jpg', 'published', now() - INTERVAL 30 HOUR, now() - INTERVAL 30 HOUR, NULL, 'c', 0, 1697625600),
('cccccccc-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333', 'Thank you for 100K followers! ❤️ #milestone', 'posts/charlie/100k.jpg', 'published', now() - INTERVAL 48 HOUR, now() - INTERVAL 48 HOUR, NULL, 'c', 0, 1697625600);

-- ============================================
-- Test Data: Follows
-- ============================================
INSERT INTO follows (id, follower_id, following_id, created_at, __op, __deleted, __version) VALUES
-- Bob follows Alice and Charlie
('f0000000-0001-0001-0001-000000000001', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', now() - INTERVAL 30 DAY, 'c', 0, 1697625600),
('f0000000-0002-0002-0002-000000000002', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', now() - INTERVAL 60 DAY, 'c', 0, 1697625600),

-- Diana follows Charlie
('f0000000-0003-0003-0003-000000000003', '44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', now() - INTERVAL 7 DAY, 'c', 0, 1697625600),

-- Alice follows Bob
('f0000000-0004-0004-0004-000000000004', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() - INTERVAL 20 DAY, 'c', 0, 1697625600);

-- ============================================
-- Test Data: Events (User Interactions)
-- ============================================
INSERT INTO events (event_id, user_id, post_id, event_type, author_id, dwell_ms, created_at) VALUES
-- Bob's interactions (last 24 hours)
(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-1111-1111-1111-111111111111', 'impression', '11111111-1111-1111-1111-111111111111', NULL, now() - INTERVAL 2 HOUR),
(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-1111-1111-1111-111111111111', 'view', '11111111-1111-1111-1111-111111111111', 8500, now() - INTERVAL 2 HOUR),
(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-1111-1111-1111-111111111111', 'like', '11111111-1111-1111-1111-111111111111', NULL, now() - INTERVAL 2 HOUR),

(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'cccccccc-1111-1111-1111-111111111111', 'impression', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'cccccccc-1111-1111-1111-111111111111', 'view', '33333333-3333-3333-3333-333333333333', 12000, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'cccccccc-1111-1111-1111-111111111111', 'like', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), '22222222-2222-2222-2222-222222222222', 'cccccccc-1111-1111-1111-111111111111', 'comment', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 1 HOUR),

-- Diana's interactions
(generateUUIDv4(), '44444444-4444-4444-4444-444444444444', 'cccccccc-1111-1111-1111-111111111111', 'impression', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 30 MINUTE),
(generateUUIDv4(), '44444444-4444-4444-4444-444444444444', 'cccccccc-1111-1111-1111-111111111111', 'view', '33333333-3333-3333-3333-333333333333', 5000, now() - INTERVAL 30 MINUTE),

(generateUUIDv4(), '44444444-4444-4444-4444-444444444444', 'cccccccc-2222-2222-2222-222222222222', 'impression', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 8 HOUR),
(generateUUIDv4(), '44444444-4444-4444-4444-444444444444', 'cccccccc-2222-2222-2222-222222222222', 'view', '33333333-3333-3333-3333-333333333333', 15000, now() - INTERVAL 8 HOUR),
(generateUUIDv4(), '44444444-4444-4444-4444-444444444444', 'cccccccc-2222-2222-2222-222222222222', 'like', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 8 HOUR),

-- Alice's interactions
(generateUUIDv4(), '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-1111-1111-1111-111111111111', 'impression', '22222222-2222-2222-2222-222222222222', NULL, now() - INTERVAL 6 HOUR),
(generateUUIDv4(), '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-1111-1111-1111-111111111111', 'view', '22222222-2222-2222-2222-222222222222', 6000, now() - INTERVAL 6 HOUR),
(generateUUIDv4(), '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-1111-1111-1111-111111111111', 'like', '22222222-2222-2222-2222-222222222222', NULL, now() - INTERVAL 6 HOUR),

-- Bulk impressions for Charlie's viral post
(generateUUIDv4(), generateUUIDv4(), 'cccccccc-1111-1111-1111-111111111111', 'impression', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), generateUUIDv4(), 'cccccccc-1111-1111-1111-111111111111', 'impression', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), generateUUIDv4(), 'cccccccc-1111-1111-1111-111111111111', 'view', '33333333-3333-3333-3333-333333333333', 3000, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), generateUUIDv4(), 'cccccccc-1111-1111-1111-111111111111', 'view', '33333333-3333-3333-3333-333333333333', 7500, now() - INTERVAL 1 HOUR),
(generateUUIDv4(), generateUUIDv4(), 'cccccccc-1111-1111-1111-111111111111', 'like', '33333333-3333-3333-3333-333333333333', NULL, now() - INTERVAL 1 HOUR);

-- ============================================
-- Verification Queries
-- ============================================

-- Check post count
SELECT 'Total posts:', count(*) FROM posts FINAL WHERE __deleted = 0;

-- Check follow relationships
SELECT 'Total follows:', count(*) FROM follows FINAL WHERE __deleted = 0;

-- Check event count
SELECT 'Total events:', count(*) FROM events;

-- Check events by type
SELECT
  event_type,
  count(*) AS event_count
FROM events
GROUP BY event_type
ORDER BY event_count DESC;

-- Check post metrics (should be populated by materialized view)
SELECT
  post_id,
  sum(likes_count) AS likes,
  sum(comments_count) AS comments,
  sum(views_count) AS views,
  sum(impressions_count) AS impressions
FROM post_metrics_1h
GROUP BY post_id
ORDER BY likes DESC;

-- Check user affinity (should be populated by materialized view)
SELECT
  user_id,
  author_id,
  interaction_count,
  like_count,
  comment_count,
  view_count
FROM user_author_affinity FINAL
ORDER BY interaction_count DESC
LIMIT 10;

-- Test feed ranking query (Bob's personalized feed)
SELECT
  p.id AS post_id,
  p.caption,
  p.user_id AS author_id,
  sum(pm.likes_count) AS likes,
  sum(pm.comments_count) AS comments,
  round(
    0.30 * exp(-0.10 * dateDiff('hour', p.created_at, now())) +
    0.40 * log1p(sum(pm.likes_count) + 2*sum(pm.comments_count)),
    4
  ) AS score
FROM posts AS p FINAL
INNER JOIN follows AS f FINAL
  ON f.following_id = p.user_id
  AND f.follower_id = '22222222-2222-2222-2222-222222222222'
  AND f.__deleted = 0
LEFT JOIN post_metrics_1h AS pm
  ON pm.post_id = p.id
  AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 24 HOUR
WHERE p.status = 'published'
  AND p.__deleted = 0
  AND p.created_at >= now() - INTERVAL 72 HOUR
GROUP BY p.id, p.caption, p.user_id, p.created_at
ORDER BY score DESC
LIMIT 10;

-- ============================================
-- Success Message
-- ============================================
SELECT '✅ Test data loaded successfully!' AS status;
SELECT 'Run queries in feed-ranking.sql to test feed generation' AS next_step;
