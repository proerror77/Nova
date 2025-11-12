-- ============================================
-- Batch 3 Migration Verification Script
-- ============================================
--
-- Purpose: Quick verification of migrations 118, 119, 122
-- Usage: Run this AFTER applying migrations to verify correctness
--
-- Expected Results:
-- - All queries should execute without errors
-- - All counts should be >= 0
-- - All helper functions should return results
--
-- ============================================

\echo '=== Batch 3 Migration Verification ==='
\echo ''

-- ============================================
-- Test 1: Verify oauth_connections table exists (Migration 118)
-- ============================================
\echo '1. Checking oauth_connections table...'

SELECT
    'oauth_connections' AS table_name,
    COUNT(*) AS row_count,
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'oauth_connections' AND column_name = 'access_token_encrypted'
    ) AS has_encrypted_columns,
    EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'oauth_connections' AND indexname = 'idx_oauth_expiring_tokens'
    ) AS has_expiring_tokens_index
FROM oauth_connections;

-- Test helper function
\echo '  Testing count_old_oauth_tokens() function...'
SELECT * FROM count_old_oauth_tokens();

-- ============================================
-- Test 2: Verify messages encryption constraints (Migration 119)
-- ============================================
\echo ''
\echo '2. Checking messages encryption constraints...'

SELECT
    'messages' AS table_name,
    COUNT(*) AS total_messages,
    COUNT(*) FILTER (WHERE encryption_version = 1) AS plaintext_v1,
    COUNT(*) FILTER (WHERE encryption_version = 2) AS encrypted_v2,
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_messages_encryption_version_valid'
    ) AS has_version_constraint,
    EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename = 'messages' AND indexname = 'idx_messages_encryption_version'
    ) AS has_version_index
FROM messages;

-- Test helper function
\echo '  Testing get_message_encryption_stats() function...'
SELECT * FROM get_message_encryption_stats();

-- ============================================
-- Test 3: Verify device_keys and key_exchanges tables (Migration 122)
-- ============================================
\echo ''
\echo '3. Checking device_keys table...'

SELECT
    'device_keys' AS table_name,
    COUNT(*) AS row_count,
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'device_keys_unique_device'
    ) AS has_unique_constraint,
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'device_keys_user_fk'
    ) AS has_user_fk
FROM device_keys;

\echo ''
\echo '4. Checking key_exchanges table...'

SELECT
    'key_exchanges' AS table_name,
    COUNT(*) AS row_count,
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'key_exchanges_conv_fk'
    ) AS has_conv_fk,
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'key_exchanges_initiator_fk'
    ) AS has_initiator_fk,
    EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'key_exchanges_peer_fk'
    ) AS has_peer_fk
FROM key_exchanges;

-- Test helper function
\echo '  Testing get_device_key_stats() function...'
SELECT * FROM get_device_key_stats();

-- ============================================
-- Test 4: Verify column types and nullability
-- ============================================
\echo ''
\echo '5. Verifying column definitions...'

SELECT
    table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name IN ('oauth_connections', 'device_keys', 'key_exchanges')
    AND column_name IN (
        'access_token_encrypted',
        'refresh_token_encrypted',
        'tokens_encrypted',
        'public_key',
        'private_key_encrypted',
        'shared_secret_hash'
    )
ORDER BY table_name, column_name;

-- ============================================
-- Test 5: Verify updated_at triggers
-- ============================================
\echo ''
\echo '6. Checking updated_at triggers...'

SELECT
    trigger_name,
    event_manipulation,
    event_object_table,
    action_timing
FROM information_schema.triggers
WHERE event_object_table IN ('oauth_connections', 'device_keys')
    AND trigger_name LIKE '%updated_at%'
ORDER BY event_object_table;

-- ============================================
-- Test 6: Test constraint enforcement (should FAIL as expected)
-- ============================================
\echo ''
\echo '7. Testing constraint enforcement...'

-- This should FAIL (invalid encryption_version)
\echo '  Testing encryption_version constraint (should FAIL)...'
DO $$
BEGIN
    -- Try to insert message with invalid encryption_version
    INSERT INTO messages (
        id,
        conversation_id,
        sender_id,
        content_encrypted,
        content_nonce,
        encryption_version,
        content
    )
    SELECT
        uuid_generate_v4(),
        id,
        created_by,
        E'\\x00'::bytea,
        E'\\x00'::bytea,
        99, -- INVALID
        ''
    FROM conversations LIMIT 1;

    RAISE EXCEPTION 'ERROR: Constraint did not prevent invalid encryption_version!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'SUCCESS: encryption_version constraint working correctly';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'ERROR: Unexpected exception: %', SQLERRM;
END $$;

-- ============================================
-- Summary
-- ============================================
\echo ''
\echo '=== Verification Complete ==='
\echo ''
\echo 'Expected results:'
\echo '  - oauth_connections: has_encrypted_columns = TRUE'
\echo '  - messages: has_version_constraint = TRUE'
\echo '  - device_keys: has_unique_constraint = TRUE, has_user_fk = TRUE'
\echo '  - key_exchanges: has_conv_fk = TRUE, has_initiator_fk = TRUE, has_peer_fk = TRUE'
\echo '  - All helper functions should return valid results'
\echo '  - Constraint test should print "SUCCESS: encryption_version constraint working correctly"'
\echo ''
