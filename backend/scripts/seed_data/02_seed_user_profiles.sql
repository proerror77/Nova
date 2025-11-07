-- Seed data for user-service (nova_user database)
-- Creates user profiles matching auth-service test users
-- DO NOT RUN IN PRODUCTION

-- Insert user profiles
INSERT INTO users (id, username, display_name, bio, avatar_url, is_verified, is_private, created_at, updated_at)
VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, 'alice_test', 'Alice Smith', 'Software engineer passionate about distributed systems', 'https://avatar.test.nova.com/alice.jpg', true, false, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, 'bob_test', 'Bob Johnson', 'Full-stack developer and coffee enthusiast', 'https://avatar.test.nova.com/bob.jpg', true, false, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000003'::uuid, 'charlie_test', 'Charlie Brown', 'DevOps engineer | Kubernetes expert', 'https://avatar.test.nova.com/charlie.jpg', false, false, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000004'::uuid, 'diana_test', 'Diana Prince', 'Product designer with a love for UX', 'https://avatar.test.nova.com/diana.jpg', true, true, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000005'::uuid, 'eve_test', 'Eve Anderson', 'Backend architect | gRPC enthusiast', 'https://avatar.test.nova.com/eve.jpg', false, false, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    display_name = EXCLUDED.display_name,
    bio = EXCLUDED.bio,
    updated_at = NOW();

-- Create follow relationships (social graph)
INSERT INTO follows (follower_id, following_id, created_at)
VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000003'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000005'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW()),
    ('00000000-0000-0000-0000-000000000005'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW())
ON CONFLICT (follower_id, following_id) DO NOTHING;

-- Insert user stats
INSERT INTO user_stats (user_id, follower_count, following_count, post_count, created_at, updated_at)
VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, 1, 2, 0, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, 2, 2, 0, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000003'::uuid, 1, 0, 0, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000004'::uuid, 0, 0, 0, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000005'::uuid, 1, 1, 0, NOW(), NOW())
ON CONFLICT (user_id) DO UPDATE SET
    follower_count = EXCLUDED.follower_count,
    following_count = EXCLUDED.following_count,
    updated_at = NOW();
