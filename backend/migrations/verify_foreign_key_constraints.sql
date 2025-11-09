-- ============================================
-- Foreign Key Constraint Verification Script
-- ============================================
--
-- Purpose: Verify that messages.sender_id has the correct ON DELETE RESTRICT constraint
--          after Migrations 067 and 083 have been applied.
--
-- Expected result: Single row with delete_rule = 'RESTRICT'
--
-- If this query returns:
-- - CASCADE: BLOCKER - Migration 083 failed to clean up Migration 067
-- - NO ACTION: WARNING - Default constraint (should be explicit RESTRICT)
-- - RESTRICT: ✅ CORRECT - Soft-delete audit trail enforced
--
-- Author: Nova Team
-- Date: 2025-11-06
-- ============================================

\echo '================================================'
\echo 'Foreign Key Constraint Verification'
\echo '================================================'
\echo ''

-- Query 1: Check messages.sender_id constraint
\echo '1. Checking messages.sender_id foreign key constraint:'
\echo ''

SELECT
    tc.constraint_name AS constraint_name,
    tc.table_name AS table_name,
    kcu.column_name AS column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule AS delete_rule,
    rc.update_rule AS update_rule,
    CASE
        WHEN rc.delete_rule = 'RESTRICT' THEN '✅ CORRECT'
        WHEN rc.delete_rule = 'CASCADE' THEN '❌ BLOCKER: CASCADE found (Migration 067 not cleaned up)'
        WHEN rc.delete_rule = 'NO ACTION' THEN '⚠️  WARNING: NO ACTION (should be explicit RESTRICT)'
        ELSE '❓ UNKNOWN: Unexpected delete rule'
    END AS status
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
    AND tc.table_schema = rc.constraint_schema
WHERE tc.table_schema = 'public'
    AND tc.table_name = 'messages'
    AND kcu.column_name = 'sender_id'
    AND tc.constraint_type = 'FOREIGN KEY';

\echo ''
\echo '================================================'
\echo '2. Checking for orphaned Migration 067 constraints:'
\echo '================================================'
\echo ''

-- Query 2: Find any CASCADE constraints (should be none)
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.table_schema = 'public'
    AND tc.table_name = 'messages'
    AND rc.delete_rule = 'CASCADE';

\echo ''
\echo 'Expected result: 0 rows (no CASCADE constraints found)'
\echo ''

\echo '================================================'
\echo '3. All foreign keys on messages table:'
\echo '================================================'
\echo ''

-- Query 3: Show all foreign keys on messages table
SELECT
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS foreign_table,
    ccu.column_name AS foreign_column,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.table_schema = 'public'
    AND tc.table_name = 'messages'
    AND tc.constraint_type = 'FOREIGN KEY'
ORDER BY kcu.column_name;

\echo ''
\echo '================================================'
\echo 'Verification complete'
\echo '================================================'
\echo ''
\echo 'If you see CASCADE in delete_rule for sender_id:'
\echo '  → Run Migration 083 again (it is idempotent)'
\echo '  → Check migration logs for errors'
\echo ''
\echo 'Expected output for messages.sender_id:'
\echo '  constraint_name: fk_messages_sender_id'
\echo '  delete_rule: RESTRICT'
\echo '  status: ✅ CORRECT'
\echo ''
