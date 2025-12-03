-- Add reusable invite codes support
-- Follows expand/contract pattern: only additive changes

-- Add reusable flag to invite_codes table
ALTER TABLE invite_codes
    ADD COLUMN IF NOT EXISTS reusable BOOLEAN NOT NULL DEFAULT FALSE;

-- Add index for reusable codes lookup
CREATE INDEX IF NOT EXISTS idx_invite_codes_reusable ON invite_codes (code) WHERE reusable = TRUE;

-- Create a system user for system-generated invite codes
-- Using a fixed UUID so it's deterministic across environments
INSERT INTO users (
    id,
    username,
    email,
    password_hash,
    display_name,
    email_verified,
    invite_quota,
    created_at
) VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'system',
    'system@nova.internal',
    '$argon2id$v=19$m=65536,t=3,p=4$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', -- Invalid hash, login impossible
    'Nova System',
    TRUE,
    999999,
    NOW()
) ON CONFLICT (id) DO NOTHING;

-- Create the NOVATEST reusable invite code
-- Expires in year 2099, effectively never
INSERT INTO invite_codes (
    id,
    code,
    issuer_user_id,
    expires_at,
    reusable,
    created_at
) VALUES (
    '00000000-0000-0000-0000-000000000002'::UUID,
    'NOVATEST',
    '00000000-0000-0000-0000-000000000001'::UUID,
    '2099-12-31 23:59:59+00'::TIMESTAMPTZ,
    TRUE,
    NOW()
) ON CONFLICT (code) DO UPDATE SET
    reusable = TRUE,
    expires_at = '2099-12-31 23:59:59+00'::TIMESTAMPTZ;

COMMENT ON COLUMN invite_codes.reusable IS 'If TRUE, this invite code can be used unlimited times';
