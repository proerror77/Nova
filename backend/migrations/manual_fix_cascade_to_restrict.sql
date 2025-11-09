-- ============================================
-- Manual Fix: CASCADE to RESTRICT
-- ============================================
--
-- Purpose: Manually fix messages.sender_id constraint if Migration 083 failed
--          or was not applied.
--
-- ⚠️  USE ONLY IF:
-- - Migration 083 failed to apply
-- - You verified CASCADE constraint exists using verify_foreign_key_constraints.sql
-- - You have database admin privileges
-- - You have a backup
--
-- DO NOT use this if Migration 083 succeeded.
-- Migration 083 is idempotent and self-correcting.
--
-- Author: Nova Team
-- Date: 2025-11-06
-- ============================================

BEGIN;

\echo '================================================'
\echo 'Manual Fix: CASCADE to RESTRICT'
\echo '================================================'
\echo ''
\echo 'WARNING: This will drop and recreate messages.sender_id constraint'
\echo 'Press Ctrl+C to cancel, or press Enter to continue...'
\echo ''

-- Step 1: Drop all possible constraint variants
\echo 'Step 1: Dropping existing constraints...'

ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_fkey CASCADE;

ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS fk_messages_sender_id_cascade CASCADE;

ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS fk_messages_sender_id CASCADE;

\echo '✓ Old constraints dropped'
\echo ''

-- Step 2: Create the correct RESTRICT constraint
\echo 'Step 2: Creating RESTRICT constraint...'

ALTER TABLE messages
    ADD CONSTRAINT fk_messages_sender_id
    FOREIGN KEY (sender_id) REFERENCES users(id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE;

\echo '✓ RESTRICT constraint created'
\echo ''

-- Step 3: Add documentation comment
\echo 'Step 3: Adding documentation...'

COMMENT ON CONSTRAINT fk_messages_sender_id ON messages IS
    'FK to users.id with ON DELETE RESTRICT (no hard deletes allowed).
     Hard deletes are prevented to enforce soft-delete audit trail.
     Cascade deletions are handled via Outbox pattern + Kafka event propagation.
     NEVER change this to CASCADE - it would bypass the audit trail.

     Manually fixed from CASCADE to RESTRICT (Migration 083 cleanup).';

\echo '✓ Documentation added'
\echo ''

-- Step 4: Verify the fix
\echo 'Step 4: Verifying fix...'

SELECT
    tc.constraint_name,
    rc.delete_rule,
    CASE
        WHEN rc.delete_rule = 'RESTRICT' THEN '✅ CORRECT'
        ELSE '❌ FAILED: Still not RESTRICT'
    END AS status
FROM information_schema.table_constraints AS tc
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.table_name = 'messages'
    AND tc.constraint_name = 'fk_messages_sender_id';

\echo ''
\echo '================================================'
\echo 'Manual fix complete'
\echo '================================================'
\echo ''
\echo 'If status shows ✅ CORRECT:'
\echo '  → Transaction will be committed'
\echo '  → Migration 083 state is now consistent'
\echo ''
\echo 'If status shows ❌ FAILED:'
\echo '  → Transaction will be rolled back'
\echo '  → Check PostgreSQL logs for errors'
\echo ''

COMMIT;

\echo 'Transaction committed successfully'
