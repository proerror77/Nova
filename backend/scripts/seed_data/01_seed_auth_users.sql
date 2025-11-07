-- Seed data for auth-service (nova_auth database)
-- Creates test users for staging/development environments
-- DO NOT RUN IN PRODUCTION

-- Insert test users with known credentials
-- Password for all test users: "TestPass123!"
-- Hashed with bcrypt (cost factor 10)

INSERT INTO users (id, email, password_hash, email_verified, created_at, updated_at)
VALUES
    ('00000000-0000-0000-0000-000000000001'::uuid, 'alice@test.nova.com', '$2b$10$YourBcryptHashHere1', true, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000002'::uuid, 'bob@test.nova.com', '$2b$10$YourBcryptHashHere2', true, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000003'::uuid, 'charlie@test.nova.com', '$2b$10$YourBcryptHashHere3', true, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000004'::uuid, 'diana@test.nova.com', '$2b$10$YourBcryptHashHere4', true, NOW(), NOW()),
    ('00000000-0000-0000-0000-000000000005'::uuid, 'eve@test.nova.com', '$2b$10$YourBcryptHashHere5', true, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert refresh tokens for persistent sessions
INSERT INTO refresh_tokens (id, user_id, token_hash, device_info, expires_at, created_at)
SELECT
    gen_random_uuid(),
    id,
    encode(sha256(('refresh_' || id::text)::bytea), 'hex'),
    'E2E Test Client',
    NOW() + INTERVAL '30 days',
    NOW()
FROM users
WHERE email LIKE '%@test.nova.com'
ON CONFLICT DO NOTHING;
