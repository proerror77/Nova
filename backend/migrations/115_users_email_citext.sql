-- ============================================
-- Migration: 073_users_email_citext
-- Description: Make users.email case-insensitive using CITEXT
-- ============================================

-- Enable citext extension (idempotent)
CREATE EXTENSION IF NOT EXISTS citext;

-- Step 1: Drop dependent views
DROP VIEW IF EXISTS recent_suspicious_activities CASCADE;

-- Step 2: Alter column type to CITEXT for case-insensitive comparisons and uniqueness
ALTER TABLE users
    ALTER COLUMN email TYPE CITEXT USING email::CITEXT;

-- Step 3: Recreate index if needed (existing UNIQUE constraint will apply on citext semantics)
CREATE INDEX IF NOT EXISTS idx_users_email_citext ON users(email);

-- Step 4: Recreate dropped views
CREATE OR REPLACE VIEW recent_suspicious_activities AS
SELECT
    al.id,
    al.user_id,
    u.email,
    u.username,
    al.event_type,
    al.ip_address,
    al.user_agent,
    al.created_at,
    COUNT(*) OVER (PARTITION BY al.ip_address) AS attempts_from_ip
FROM auth_logs al
LEFT JOIN users u ON al.user_id = u.id
WHERE al.created_at > (NOW() - INTERVAL '24 hours')
  AND al.status = 'failed'
ORDER BY al.created_at DESC;

COMMENT ON COLUMN users.email IS 'User email (CITEXT, case-insensitive unique)';

