-- ============================================
-- Migration: 087_auth_schema_alignment
-- Description:
--   Align shared schema with auth-service expectations by normalizing
--   token revocations, user profile columns, and session metadata.
-- ============================================

-- 1. Normalize token revocation table / columns
DO $$
BEGIN
    IF to_regclass('public.token_revocation') IS NOT NULL
       AND to_regclass('public.token_revocations') IS NULL THEN
        ALTER TABLE token_revocation RENAME TO token_revocations;
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS token_revocations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    token_type VARCHAR(20),
    jti VARCHAR(255),
    revocation_reason VARCHAR(255),
    revoked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Rename legacy column if still present
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'token_revocations' AND column_name = 'reason'
    ) THEN
        ALTER TABLE token_revocations RENAME COLUMN reason TO revocation_reason;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_token_revocations_user_id ON token_revocations(user_id);
CREATE INDEX IF NOT EXISTS idx_token_revocations_token_hash ON token_revocations(token_hash);
CREATE INDEX IF NOT EXISTS idx_token_revocations_expires_at ON token_revocations(expires_at);
CREATE INDEX IF NOT EXISTS idx_token_revocations_jti ON token_revocations(jti);

-- 2. Ensure users table has auth-service columns
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number VARCHAR(32);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_password_change_at TIMESTAMP WITH TIME ZONE;

-- 3. Ensure sessions table has rich metadata columns used by auth-service
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS device_id VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS device_name VARCHAR(255);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS device_type VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS os_name VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS os_version VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS browser_name VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS browser_version VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS location_country VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS location_city VARCHAR(100);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS access_token_jti VARCHAR(255);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS refresh_token_jti VARCHAR(255);
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();

-- Maintain updated_at automatically
CREATE OR REPLACE FUNCTION update_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sessions_updated_at ON sessions;
CREATE TRIGGER trg_sessions_updated_at
BEFORE UPDATE ON sessions
FOR EACH ROW
EXECUTE FUNCTION update_sessions_updated_at();
