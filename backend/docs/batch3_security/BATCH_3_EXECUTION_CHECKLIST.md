# Batch 3 Migration Execution Checklist

**Migrations**: 118, 119, 122
**Date Prepared**: 2025-11-12
**Status**: Ready for Review

---

## Pre-Execution Checklist

### 1. Code Review
- [ ] Review migration 118 (oauth_encrypted_tokens.sql)
- [ ] Review migration 119 (add_message_encryption.sql)
- [ ] Review migration 122 (create_device_keys_and_key_exchanges.sql)
- [ ] Review BATCH_3_MIGRATION_REPORT.md
- [ ] Verify no SQL syntax errors (run through formatter/linter)

### 2. Dependency Verification
- [ ] Confirm `users` table exists (migration 001)
- [ ] Confirm `conversations` table exists (migration 018)
- [ ] Confirm `messages` table has `encryption_version`, `content_encrypted`, `content_nonce` columns (migrations 104, 113)
- [ ] Verify no other migrations are pending (run `SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 10;`)

### 3. Application Code Status
- [ ] **BLOCKER**: AWS KMS integration implemented?
  - [ ] Master key created in KMS
  - [ ] IAM roles configured
  - [ ] App can encrypt/decrypt with master key
- [ ] **BLOCKER**: Cryptography libraries integrated?
  - [ ] `aes-gcm` crate for OAuth token encryption
  - [ ] `x25519-dalek` crate for ECDH
  - [ ] `chacha20poly1305` crate for message encryption
- [ ] OAuth token refresh job implemented?
- [ ] Device key registration endpoints implemented?
- [ ] E2EE message encryption/decryption implemented?

### 4. Environment Preparation
- [ ] Schedule maintenance window (estimate: 60 minutes total)
- [ ] Notify users of potential downtime
- [ ] Prepare rollback plan document
- [ ] Backup production database (verify backup integrity)
- [ ] Set up monitoring alerts for:
  - [ ] Database CPU usage
  - [ ] Long-running queries
  - [ ] Connection pool exhaustion
  - [ ] Failed migration detection

### 5. Staging Environment Testing
- [ ] Deploy migrations to staging database
- [ ] Run BATCH_3_VERIFICATION.sql script
- [ ] Verify all tests pass
- [ ] Test OAuth login flow
- [ ] Test device key registration
- [ ] Test E2EE message send/receive
- [ ] Measure performance impact:
  - [ ] oauth_connections table insert/update latency
  - [ ] messages table insert latency
  - [ ] device_keys table lookup latency
- [ ] Test rollback procedure on staging

---

## Execution Phase

### Step 1: Backup and Verification (10 minutes)
```bash
# Backup production database
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f backup_pre_batch3_$(date +%Y%m%d_%H%M%S).dump

# Verify backup integrity
pg_restore --list backup_pre_batch3_*.dump | head -20

# Check current schema version
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 5;"
```

**Checklist**:
- [ ] Backup file created successfully
- [ ] Backup file size reasonable (not 0 bytes)
- [ ] Current schema version is 115 or later

---

### Step 2: Apply Migration 118 - OAuth Encrypted Tokens (10 minutes)
```bash
# Apply migration
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f 118_oauth_encrypted_tokens.sql

# Verify table created
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT COUNT(*) as table_exists
FROM information_schema.tables
WHERE table_name = 'oauth_connections';
"

# Verify indexes created
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT indexname
FROM pg_indexes
WHERE tablename = 'oauth_connections'
ORDER BY indexname;
"

# Test helper function
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT * FROM count_old_oauth_tokens();"
```

**Checklist**:
- [ ] Migration applied without errors
- [ ] `oauth_connections` table exists
- [ ] 5 indexes created (idx_oauth_connections_user_id, idx_oauth_connections_provider, idx_oauth_connections_provider_user_id, idx_oauth_expiring_tokens, idx_oauth_last_refresh)
- [ ] Helper function `count_old_oauth_tokens()` works
- [ ] Trigger `trigger_oauth_connections_updated_at` exists

**Rollback if needed**:
```sql
DROP TABLE IF EXISTS oauth_connections CASCADE;
DROP FUNCTION IF EXISTS count_old_oauth_tokens();
DROP FUNCTION IF EXISTS update_oauth_connections_updated_at();
```

---

### Step 3: Apply Migration 119 - Message Encryption Validation (5 minutes)
```bash
# Apply migration
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f 119_add_message_encryption.sql

# Verify constraint added
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT conname, contype, pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conname = 'chk_messages_encryption_version_valid';
"

# Verify index created
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT indexname, indexdef
FROM pg_indexes
WHERE indexname = 'idx_messages_encryption_version';
"

# Test helper function
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT * FROM get_message_encryption_stats();"
```

**Checklist**:
- [ ] Migration applied without errors
- [ ] Constraint `chk_messages_encryption_version_valid` exists (CHECK encryption_version IN (1, 2))
- [ ] Index `idx_messages_encryption_version` created
- [ ] Helper function `get_message_encryption_stats()` works
- [ ] Existing messages unaffected (all should have encryption_version = 1)

**Rollback if needed**:
```sql
DROP INDEX IF EXISTS idx_messages_encryption_version;
DROP FUNCTION IF EXISTS get_message_encryption_stats();
ALTER TABLE messages DROP CONSTRAINT IF EXISTS chk_messages_encryption_version_valid;
```

---

### Step 4: Apply Migration 122 - Device Keys and Key Exchanges (10 minutes)
```bash
# Apply migration
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f 122_create_device_keys_and_key_exchanges.sql

# Verify tables created
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT table_name
FROM information_schema.tables
WHERE table_name IN ('device_keys', 'key_exchanges')
ORDER BY table_name;
"

# Verify foreign keys
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT conname, contype, conrelid::regclass as table_name, confrelid::regclass as referenced_table
FROM pg_constraint
WHERE conname LIKE 'device_keys_%' OR conname LIKE 'key_exchanges_%'
ORDER BY conname;
"

# Test helper function
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT * FROM get_device_key_stats();"
```

**Checklist**:
- [ ] Migration applied without errors
- [ ] `device_keys` table created
- [ ] `key_exchanges` table created
- [ ] Foreign keys exist:
  - [ ] device_keys_user_fk (device_keys.user_id -> users.id)
  - [ ] key_exchanges_conv_fk (key_exchanges.conversation_id -> conversations.id)
  - [ ] key_exchanges_initiator_fk (key_exchanges.initiator_id -> users.id)
  - [ ] key_exchanges_peer_fk (key_exchanges.peer_id -> users.id)
- [ ] Unique constraint `device_keys_unique_device` exists
- [ ] Helper function `get_device_key_stats()` works
- [ ] Trigger `trigger_device_keys_updated_at` exists

**Rollback if needed**:
```sql
DROP TABLE IF EXISTS key_exchanges CASCADE;
DROP TABLE IF EXISTS device_keys CASCADE;
DROP FUNCTION IF EXISTS get_device_key_stats();
DROP FUNCTION IF EXISTS update_device_keys_updated_at();
```

---

### Step 5: Run Comprehensive Verification (10 minutes)
```bash
# Run verification script
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f BATCH_3_VERIFICATION.sql

# Check for any new errors in logs
tail -100 /var/log/postgresql/postgresql.log | grep ERROR
```

**Checklist**:
- [ ] All verification queries execute successfully
- [ ] No unexpected errors in PostgreSQL logs
- [ ] All boolean checks return `TRUE`
- [ ] Constraint enforcement test passes (prints "SUCCESS: encryption_version constraint working correctly")

---

### Step 6: Smoke Testing (15 minutes)

#### Test 1: OAuth Connection
```sql
-- Insert test OAuth connection
INSERT INTO oauth_connections (
    user_id,
    provider,
    provider_user_id,
    email,
    access_token_encrypted,
    refresh_token_encrypted,
    tokens_encrypted,
    token_expires_at
)
SELECT
    id,
    'google',
    'test-provider-user-123',
    'test@example.com',
    E'\\x0001020304'::bytea, -- Fake encrypted token
    E'\\x0506070809'::bytea, -- Fake encrypted token
    TRUE,
    NOW() + INTERVAL '1 hour'
FROM users
WHERE is_active = TRUE
LIMIT 1;

-- Verify inserted
SELECT
    provider,
    provider_user_id,
    tokens_encrypted,
    updated_at > created_at as trigger_works
FROM oauth_connections
WHERE provider_user_id = 'test-provider-user-123';

-- Cleanup
DELETE FROM oauth_connections WHERE provider_user_id = 'test-provider-user-123';
```

**Checklist**:
- [ ] OAuth connection inserted successfully
- [ ] `updated_at` trigger works (`trigger_works` = FALSE initially)
- [ ] Cleanup successful

---

#### Test 2: Device Key Registration
```sql
-- Insert test device key
INSERT INTO device_keys (
    user_id,
    device_id,
    public_key,
    private_key_encrypted
)
SELECT
    id,
    'test-device-001',
    'dGVzdC1wdWJsaWMta2V5LWJhc2U2NA==', -- Base64 "test-public-key-base64"
    'dGVzdC1wcml2YXRlLWtleS1lbmNyeXB0ZWQ=' -- Base64 "test-private-key-encrypted"
FROM users
WHERE is_active = TRUE
LIMIT 1;

-- Verify inserted
SELECT
    device_id,
    public_key,
    updated_at > created_at as trigger_works
FROM device_keys
WHERE device_id = 'test-device-001';

-- Test unique constraint (should FAIL)
DO $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT user_id INTO v_user_id FROM device_keys WHERE device_id = 'test-device-001';

    INSERT INTO device_keys (user_id, device_id, public_key, private_key_encrypted)
    VALUES (v_user_id, 'test-device-001', 'different-key', 'different-enc');

    RAISE EXCEPTION 'ERROR: Unique constraint did not prevent duplicate!';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'SUCCESS: Unique constraint working correctly';
END $$;

-- Cleanup
DELETE FROM device_keys WHERE device_id = 'test-device-001';
```

**Checklist**:
- [ ] Device key inserted successfully
- [ ] `updated_at` trigger works
- [ ] Unique constraint prevents duplicates (test prints "SUCCESS")
- [ ] Cleanup successful

---

#### Test 3: Key Exchange Audit Trail
```sql
-- Insert test key exchange
INSERT INTO key_exchanges (
    conversation_id,
    initiator_id,
    peer_id,
    shared_secret_hash
)
SELECT
    c.id,
    cm1.user_id,
    cm2.user_id,
    E'\\x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'::bytea -- 32-byte HMAC-SHA256 hash
FROM conversations c
JOIN conversation_members cm1 ON cm1.conversation_id = c.id
JOIN conversation_members cm2 ON cm2.conversation_id = c.id AND cm2.user_id != cm1.user_id
WHERE c.conversation_type = 'direct'
LIMIT 1;

-- Verify inserted
SELECT
    conversation_id,
    initiator_id,
    peer_id,
    length(shared_secret_hash) as hash_length -- Should be 32 bytes
FROM key_exchanges
ORDER BY created_at DESC
LIMIT 1;

-- Cleanup
DELETE FROM key_exchanges WHERE created_at > NOW() - INTERVAL '1 minute';
```

**Checklist**:
- [ ] Key exchange inserted successfully
- [ ] `hash_length` = 32 bytes
- [ ] Foreign key constraints enforced (no errors)
- [ ] Cleanup successful

---

#### Test 4: E2EE Message Insertion (encryption_version = 2)
```sql
-- Insert E2EE message
INSERT INTO messages (
    id,
    conversation_id,
    sender_id,
    content_encrypted,
    content_nonce,
    encryption_version,
    content,
    sequence_number
)
SELECT
    uuid_generate_v4(),
    c.id,
    cm.user_id,
    E'\\x0001020304050607'::bytea, -- Fake ChaCha20-Poly1305 ciphertext
    E'\\x08090a0b0c0d0e0f'::bytea, -- Fake nonce
    2, -- E2EE
    '', -- Empty for E2EE messages
    nextval('messages_sequence_number_seq'::regclass)
FROM conversations c
JOIN conversation_members cm ON cm.conversation_id = c.id
LIMIT 1;

-- Verify inserted
SELECT
    encryption_version,
    length(content_encrypted) as ciphertext_length,
    length(content_nonce) as nonce_length,
    content = '' as content_empty
FROM messages
WHERE encryption_version = 2
ORDER BY created_at DESC
LIMIT 1;

-- Cleanup
DELETE FROM messages WHERE encryption_version = 2 AND created_at > NOW() - INTERVAL '1 minute';
```

**Checklist**:
- [ ] E2EE message inserted successfully
- [ ] `encryption_version` = 2
- [ ] `content_encrypted` and `content_nonce` populated
- [ ] `content` is empty string
- [ ] Cleanup successful

---

## Post-Execution Verification

### Performance Monitoring (30 minutes)
- [ ] Monitor database CPU usage (should return to baseline)
- [ ] Check for slow queries (query time > 1s)
- [ ] Verify connection pool not exhausted
- [ ] Check index usage:
  ```sql
  SELECT
      schemaname,
      tablename,
      indexname,
      idx_scan,
      idx_tup_read,
      idx_tup_fetch
  FROM pg_stat_user_indexes
  WHERE tablename IN ('oauth_connections', 'device_keys', 'key_exchanges', 'messages')
  ORDER BY tablename, indexname;
  ```
- [ ] Monitor OAuth token refresh job (if running)
- [ ] Monitor device key registration rate
- [ ] Monitor E2EE message creation rate

### Application Integration Testing
- [ ] Test OAuth login flow (new logins should use encrypted tokens)
- [ ] Test device key registration API
- [ ] Test E2EE message send/receive
- [ ] Verify no errors in application logs
- [ ] Verify metrics dashboards (Prometheus/Grafana)

---

## Rollback Decision Tree

### Scenario 1: Migration fails to apply
**Action**: Immediate rollback
```bash
# Restore from backup
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME -c backup_pre_batch3_*.dump
```

### Scenario 2: Migration applies but verification fails
**Action**: Investigate, then decide
1. Check PostgreSQL logs for specific errors
2. Run individual verification queries to isolate issue
3. If critical (e.g., foreign key broken): Rollback immediately
4. If non-critical (e.g., index not used): Mark for follow-up, continue

### Scenario 3: Application errors after deployment
**Action**: Check if migration-related
1. Review application logs
2. If "column does not exist" or "table does not exist": **ROLLBACK IMMEDIATELY**
3. If "constraint violation": Investigate app code (may be bug, not migration issue)
4. If "encryption/decryption error": Verify KMS integration (not migration issue)

### Scenario 4: Performance degradation
**Action**: Monitor, then decide
1. Check if specific to new tables (oauth_connections, device_keys, key_exchanges)
2. If yes: Investigate index usage, consider adding additional indexes
3. If no: Unrelated to migrations, investigate separately
4. If severe (> 10x latency increase): Consider rollback

---

## Success Criteria

Migration is considered **successful** if:
- [x] All migrations applied without errors
- [x] All verification queries pass
- [x] All smoke tests pass
- [x] No errors in PostgreSQL logs
- [x] No errors in application logs
- [x] Performance metrics within acceptable range:
  - oauth_connections insert/update < 50ms p95
  - device_keys insert < 20ms p95
  - key_exchanges insert < 20ms p95
  - messages insert (E2EE) < 100ms p95 (includes encryption)
- [x] Rollback procedure tested and documented

---

## Post-Migration Tasks

### Immediate (Day 1)
- [ ] Update schema documentation
- [ ] Update API documentation (if device key/OAuth endpoints changed)
- [ ] Notify development team of new tables
- [ ] Archive this checklist with execution notes

### Short-term (Week 1)
- [ ] Monitor OAuth token refresh job performance
- [ ] Monitor E2EE adoption rate
- [ ] Review query performance (identify slow queries on new tables)
- [ ] Adjust indexes if needed based on actual query patterns

### Long-term (Month 1)
- [ ] Review OAuth token encryption migration progress (how many users re-authenticated?)
- [ ] Review E2EE adoption metrics
- [ ] Plan for deprecating legacy `access_token_hash`/`refresh_token_hash` columns
- [ ] Plan for key rotation policy implementation

---

## Notes and Observations

**Execution Date**: _______________

**Executed By**: _______________

**Issues Encountered**:
-
-

**Deviations from Plan**:
-
-

**Performance Observations**:
-
-

**Recommendations for Future Migrations**:
-
-

---

**End of Checklist**
