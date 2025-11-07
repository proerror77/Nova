-- Seed data for nova_content database (actual structure)
-- Creates test users with correct schema
-- DO NOT RUN IN PRODUCTION

-- Insert test users into nova_content.users table
INSERT INTO users (id, email, username, password_hash, email_verified, is_active, follower_count, created_at, updated_at)
VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, 'alice@test.nova.com', 'alice_test', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', true, true, 2, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.nova.com', 'bob_test', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', true, true, 2, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000003'::uuid, 'charlie@test.nova.com', 'charlie_test', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', false, true, 0, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000004'::uuid, 'diana@test.nova.com', 'diana_test', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', true, true, 0, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000005'::uuid, 'eve@test.nova.com', 'eve_test', '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', false, true, 1, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    username = EXCLUDED.username,
    follower_count = EXCLUDED.follower_count,
    updated_at = NOW();

-- Create follow relationships
INSERT INTO follows (follower_id, following_id, created_at)
VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000003'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000005'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000005'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW())
ON CONFLICT (follower_id, following_id) DO NOTHING;

-- Create test posts (with placeholder image keys)
INSERT INTO posts (id, user_id, caption, image_key, status, content_type, created_at, updated_at)
VALUES
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000001'::uuid, 'Just deployed our new microservices architecture! 🚀', 'test/alice/post1.jpg', 'published', 'image', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000002'::uuid, 'Loving the new gRPC migration. Performance is incredible!', 'test/bob/post1.jpg', 'published', 'image', NOW() - INTERVAL '5 hours', NOW() - INTERVAL '5 hours'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000001'::uuid, 'Working on distributed tracing problems today', 'test/alice/post2.jpg', 'published', 'image', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000003'::uuid, 'Kubernetes is not that complicated once you understand the fundamentals', 'test/charlie/post1.jpg', 'published', 'image', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000005'::uuid, 'Blog post about building scalable APIs with Rust', 'test/eve/post1.jpg', 'published', 'image', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours')
ON CONFLICT DO NOTHING;

-- Add likes to posts
WITH posts_to_like AS (
    SELECT id, user_id FROM posts WHERE user_id IN (
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid
    ) AND image_key LIKE 'test/%'
    LIMIT 3
)
INSERT INTO likes (id, post_id, user_id, created_at)
SELECT
    gen_random_uuid(),
    p.id,
    CASE
        WHEN p.user_id = '00000000-0000-0000-0000-000000000001'::uuid THEN '00000000-0000-0000-0000-000000000002'::uuid
        WHEN p.user_id = '00000000-0000-0000-0000-000000000002'::uuid THEN '00000000-0000-0000-0000-000000000001'::uuid
        ELSE '00000000-0000-0000-0000-000000000005'::uuid
    END,
    NOW()
FROM posts_to_like p
ON CONFLICT (post_id, user_id) DO NOTHING;

-- Create conversations (direct type)
INSERT INTO conversations (id, conversation_type, created_by, created_at, updated_at)
VALUES
    ('10000000-0000-0000-0000-000000000001'::uuid, 'direct', '00000000-0000-0000-0000-000000000001'::uuid, NOW() - INTERVAL '2 days', NOW() - INTERVAL '5 minutes'),
    ('10000000-0000-0000-0000-000000000002'::uuid, 'direct', '00000000-0000-0000-0000-000000000002'::uuid, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 hour')
ON CONFLICT (id) DO NOTHING;

-- Add conversation members
INSERT INTO conversation_members (conversation_id, user_id, joined_at, last_read_at)
VALUES
    -- Conversation 1: Alice <-> Bob
    ('10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW() - INTERVAL '2 days', NOW() - INTERVAL '5 minutes'),
    ('10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW() - INTERVAL '2 days', NOW() - INTERVAL '10 minutes'),

    -- Conversation 2: Bob <-> Charlie
    ('10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 hour'),
    ('10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000003'::uuid, NOW() - INTERVAL '1 day', NOW() - INTERVAL '2 hours')
ON CONFLICT (conversation_id, user_id) DO NOTHING;

-- Note: Messages table requires encrypted_content and nonce
-- For E2E testing, you'll need to create messages through the API
-- which will handle encryption properly
