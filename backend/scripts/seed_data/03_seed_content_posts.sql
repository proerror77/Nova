-- Seed data for content-service (nova_content database)
-- Creates test posts for E2E testing
-- DO NOT RUN IN PRODUCTION

-- Insert test posts
INSERT INTO posts (id, author_id, content, media_urls, visibility, created_at, updated_at)
VALUES
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000001'::uuid, 'Just deployed our new microservices architecture to production! 🚀 #DevOps #Kubernetes', '{}', 'public', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000002'::uuid, 'Loving the new gRPC migration. Performance is incredible!', '{}', 'public', NOW() - INTERVAL '5 hours', NOW() - INTERVAL '5 hours'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000001'::uuid, 'Working on some interesting distributed tracing problems today. Any recommendations for observability tools?', '{}', 'public', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000003'::uuid, 'Hot take: Kubernetes is not that complicated once you understand the fundamentals.', '{}', 'public', NOW() - INTERVAL '12 hours', NOW() - INTERVAL '12 hours'),
    (gen_random_uuid(), '00000000-0000-0000-0000-000000000005'::uuid, 'Just wrote a blog post about building scalable APIs with Rust and Tonic. Link in bio!', '{}', 'public', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours')
ON CONFLICT DO NOTHING;

-- Insert likes
WITH posts_to_like AS (
    SELECT id, author_id FROM posts WHERE author_id IN (
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000002'::uuid,
        '00000000-0000-0000-0000-000000000003'::uuid
    )
    LIMIT 3
)
INSERT INTO likes (post_id, user_id, created_at)
SELECT
    p.id,
    CASE
        WHEN p.author_id = '00000000-0000-0000-0000-000000000001'::uuid THEN '00000000-0000-0000-0000-000000000002'::uuid
        WHEN p.author_id = '00000000-0000-0000-0000-000000000002'::uuid THEN '00000000-0000-0000-0000-000000000001'::uuid
        ELSE '00000000-0000-0000-0000-000000000005'::uuid
    END,
    NOW()
FROM posts_to_like p
ON CONFLICT (post_id, user_id) DO NOTHING;

-- Insert comments
WITH first_post AS (
    SELECT id FROM posts WHERE author_id = '00000000-0000-0000-0000-000000000001'::uuid
    ORDER BY created_at DESC LIMIT 1
)
INSERT INTO comments (id, post_id, author_id, content, created_at, updated_at)
SELECT
    gen_random_uuid(),
    fp.id,
    '00000000-0000-0000-0000-000000000002'::uuid,
    'Great work! Looking forward to seeing the results.',
    NOW() - INTERVAL '1 hour',
    NOW() - INTERVAL '1 hour'
FROM first_post fp
ON CONFLICT DO NOTHING;
