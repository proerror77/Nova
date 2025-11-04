-- ============================================
-- Migration: 073_users_email_citext
-- Description: Make users.email case-insensitive using CITEXT
-- ============================================

-- Enable citext extension (idempotent)
CREATE EXTENSION IF NOT EXISTS citext;

-- Alter column type to CITEXT for case-insensitive comparisons and uniqueness
ALTER TABLE users
    ALTER COLUMN email TYPE CITEXT;

-- Recreate index if needed (existing UNIQUE constraint will apply on citext semantics)
CREATE INDEX IF NOT EXISTS idx_users_email_citext ON users(email);

COMMENT ON COLUMN users.email IS 'User email (CITEXT, case-insensitive unique)';

