-- Migration: Align schema with technical specification document
-- Date: 2026-01-05

-- 1. Rename admins table to admin_users (per spec section 3.3)
ALTER TABLE admins RENAME TO admin_users;

-- 2. Add missing security fields (per spec section 3.3)
ALTER TABLE admin_users
    ADD COLUMN IF NOT EXISTS login_attempts INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS permissions JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 3. Replace is_active with status field (per spec: 'active', 'suspended', 'deleted')
ALTER TABLE admin_users
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active';

-- Migrate existing is_active data to status
UPDATE admin_users SET status = CASE WHEN is_active THEN 'active' ELSE 'suspended' END;

-- Drop the old is_active column
ALTER TABLE admin_users DROP COLUMN IF EXISTS is_active;

-- 4. Update audit_logs foreign key constraint (references renamed table)
-- First drop the old constraint
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_admin_id_fkey;

-- Add new constraint with new table name
ALTER TABLE audit_logs
    ADD CONSTRAINT audit_logs_admin_id_fkey
    FOREIGN KEY (admin_id) REFERENCES admin_users(id);

-- 5. Add indexes for new fields
CREATE INDEX IF NOT EXISTS idx_admin_users_status ON admin_users(status);
CREATE INDEX IF NOT EXISTS idx_admin_users_locked_until ON admin_users(locked_until) WHERE locked_until IS NOT NULL;

-- 6. Rename trigger for updated_at (optional cleanup)
DROP TRIGGER IF EXISTS update_admins_updated_at ON admin_users;
CREATE TRIGGER update_admin_users_updated_at
    BEFORE UPDATE ON admin_users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
