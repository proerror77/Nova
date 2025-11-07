-- Seed data for messaging-service (nova_messaging database)
-- Creates test conversations and messages for E2E testing
-- DO NOT RUN IN PRODUCTION

-- Insert test conversations
INSERT INTO conversations (id, created_by, created_at, updated_at)
VALUES
    ('10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW() - INTERVAL '2 days', NOW() - INTERVAL '5 minutes'),
    ('10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 hour'),
    ('10000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW() - INTERVAL '3 hours', NOW() - INTERVAL '10 minutes')
ON CONFLICT (id) DO NOTHING;

-- Insert conversation participants
INSERT INTO conversation_participants (conversation_id, user_id, joined_at, last_read_at)
VALUES
    -- Conversation 1: Alice <-> Bob
    ('10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW() - INTERVAL '2 days', NOW() - INTERVAL '5 minutes'),
    ('10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW() - INTERVAL '2 days', NOW() - INTERVAL '10 minutes'),

    -- Conversation 2: Bob <-> Charlie
    ('10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 hour'),
    ('10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000003'::uuid, NOW() - INTERVAL '1 day', NOW() - INTERVAL '2 hours'),

    -- Conversation 3: Alice <-> Eve
    ('10000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, NOW() - INTERVAL '3 hours', NOW() - INTERVAL '10 minutes'),
    ('10000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000005'::uuid, NOW() - INTERVAL '3 hours', NOW() - INTERVAL '15 minutes')
ON CONFLICT (conversation_id, user_id) DO NOTHING;

-- Insert test messages
INSERT INTO messages (id, conversation_id, sender_id, content, message_type, created_at, updated_at, deleted_at)
VALUES
    -- Conversation 1: Alice <-> Bob
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 'Hey Bob! How''s the new gRPC migration going?', 'text', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 'It''s going great! The performance improvements are amazing.', 'text', NOW() - INTERVAL '2 days' + INTERVAL '5 minutes', NOW() - INTERVAL '2 days' + INTERVAL '5 minutes', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 'That''s awesome! Can you share some metrics?', 'text', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 'Sure! Latency dropped from 45ms to 8ms on average.', 'text', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 'Wow! That''s impressive 🚀', 'text', NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '5 minutes', NULL),

    -- Conversation 2: Bob <-> Charlie
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 'Charlie, need your help with the K8s deployment', 'text', NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000003'::uuid, 'Sure, what''s the issue?', 'text', NOW() - INTERVAL '1 day' + INTERVAL '10 minutes', NOW() - INTERVAL '1 day' + INTERVAL '10 minutes', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000002'::uuid, '00000000-0000-0000-0000-000000000002'::uuid, 'Pods are in CrashLoopBackOff. Can you take a look?', 'text', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', NULL),

    -- Conversation 3: Alice <-> Eve
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 'Eve, your blog post about Rust APIs was fantastic!', 'text', NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000005'::uuid, 'Thanks Alice! Glad you found it helpful.', 'text', NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours', NULL),
    (gen_random_uuid(), '10000000-0000-0000-0000-000000000003'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, 'Do you have any tips for optimizing connection pooling?', 'text', NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '10 minutes', NULL)
ON CONFLICT DO NOTHING;

-- Update conversation updated_at timestamps to reflect latest messages
UPDATE conversations c
SET updated_at = (
    SELECT MAX(created_at)
    FROM messages m
    WHERE m.conversation_id = c.id
)
WHERE c.id IN (
    '10000000-0000-0000-0000-000000000001'::uuid,
    '10000000-0000-0000-0000-000000000002'::uuid,
    '10000000-0000-0000-0000-000000000003'::uuid
);
