-- Phase 1: Spec 007 - Users Consolidation: Remove Shadow Users FK
-- ========================================================================
--
-- RATIONALE:
--   messaging-service.users is a shadow table (copy of auth-service.users)
--   All service calls now use gRPC to auth-service for user validation
--   Database FK constraint cannot span databases (auth-service DB != messaging-service DB)
--
--   SOLUTION: Implement application-level FK validation via gRPC
--   - conversation_members.user_id → auth-service.users.id (via gRPC)
--   - groups.rs::add_member() already validates via auth_client.user_exists()
--   - Deprecate local users table in favor of gRPC API calls
--
-- BREAKING CHANGE: None (application already uses gRPC validation)
-- MIGRATION SAFETY:
--   1. All writes to conversation_members validated via gRPC (verified)
--   2. Shadow users table still exists (for compatibility, can drop in Phase 2)
--   3. Foreign key removed to prevent constraints from blocking operations
--   4. Audit: All user_id references now go through auth_client

-- Step 1: Drop the FK constraint on conversation_members pointing to local users
--         This allows conversation_members to reference users via app-level validation only
ALTER TABLE conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;

-- Step 2: Add a comment documenting the application-level FK
COMMENT ON COLUMN conversation_members.user_id IS
  'Foreign key to auth-service.users.id (validated via gRPC in application layer)';

-- Step 3: Create an audit marker for when this FK was moved to application level
ALTER TABLE conversation_members
  ADD CONSTRAINT no_local_fk_user_validation CHECK (user_id IS NOT NULL);

-- Step 4: Document the deprecation of the local users table
COMMENT ON TABLE users IS
  'DEPRECATED: This is a shadow copy of auth-service.users. All new code MUST use auth_client gRPC API instead.
   Schema: id (UUID), username (TEXT), public_key (TEXT), created_at (TIMESTAMPTZ)
   This table will be removed in Phase 2 once all code migration is complete.
   See: backend/messaging-service/src/services/auth_client.rs';

-- Migration metadata
-- Phase: Phase 1 - Users Canonicalization
-- Task: T011 - Add foreign keys to canonical auth.users (or service API if cross-db not allowed)
-- Status: COMPLETE - Implemented application-level FK validation via gRPC
-- Risk Level: LOW (only removes DB constraint; application already validates)
-- Rollback: ALTER TABLE conversation_members ADD CONSTRAINT conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
