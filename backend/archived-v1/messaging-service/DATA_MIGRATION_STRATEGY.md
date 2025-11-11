# Message Data Migration Strategy (2025-10-26)

## Overview

After the transition from Option A (client-side encryption) to Option B (server-side encryption with plaintext storage), we need a migration strategy for messages still in encrypted format.

## Current State

### Schema Evolution

```
Migration 0004: Original schema with encrypted fields
├── content_encrypted (BYTEA)
├── content_nonce (BYTEA)
└── encryption_algorithm (VARCHAR)

Migration 0005: Added plaintext support
├── content (TEXT) - NEW plaintext field
├── version_number (BIGINT)
└── recalled_at (TIMESTAMPTZ)

Migration 0009: Unified storage
├── Dropped content_encrypted, content_nonce, encryption_algorithm
├── Kept content (TEXT) as the single source of truth
└── Database-level encryption via PostgreSQL TDE

Migration 0011: Search optimization
├── Added content_tsv (GENERATED tsvector column)
├── Added GIN index for efficient FTS
└── Removed dual-path message_search_index approach
```

## Data Categories

### 1. **Pre-Migration Messages** (Still Encrypted)

**Characteristics:**
- Have `content_encrypted` and `content_nonce` values
- Empty or NULL in `content` field
- Were sent before migration 0009

**Options:**

#### A. One-Time Decryption & Backfill (RECOMMENDED)
- **Pros:** Messages remain searchable and readable
- **Cons:** Requires maintaining decryption keys temporarily
- **Process:**
  ```sql
  UPDATE messages
  SET content = decrypt_with_key(content_encrypted, content_nonce, master_key)
  WHERE content IS NULL AND content_encrypted IS NOT NULL;
  ```

#### B. Mark as Unrecoverable
- **Pros:** Simple, no key management needed
- **Cons:** Users lose message history
- **Process:**
  ```sql
  UPDATE messages
  SET content = '[Message content unavailable - archived before plaintext migration]'
  WHERE content IS NULL AND content_encrypted IS NOT NULL;
  ```

#### C. Defer Until Access (Lazy Migration)
- **Pros:** Only decrypt when user actually reads message
- **Cons:** Performance impact on first access; requires runtime decryption logic
- **Process:** Keep encrypted fields temporarily, decrypt on API layer

### 2. **Post-Migration Messages** (Plaintext)

**Characteristics:**
- Have content in `content` field
- Have NULL in `content_encrypted` and `content_nonce`
- Created after migration 0009

**Status:** ✅ Fully compatible with current API

### 3. **Partial Migration Messages** (Edge Case)

**Characteristics:**
- Have BOTH content and content_encrypted populated
- Should not occur in normal operation
- May occur if migration script was interrupted

**Action:** Delete encrypted duplicates, keep plaintext
```sql
UPDATE messages
SET content_encrypted = NULL, content_nonce = NULL
WHERE content IS NOT NULL AND content_encrypted IS NOT NULL;
```

## Recommended Strategy: Staged Migration

### Phase 1: Assessment (Non-Breaking)
```sql
-- Identify messages that need migration
SELECT
    COUNT(*) as total_messages,
    COUNT(CASE WHEN content IS NOT NULL THEN 1 END) as plaintext_messages,
    COUNT(CASE WHEN content IS NULL AND content_encrypted IS NOT NULL THEN 1 END) as encrypted_messages
FROM messages;

-- Identify by conversation
SELECT
    conversation_id,
    COUNT(*) as total,
    COUNT(CASE WHEN content_encrypted IS NOT NULL THEN 1 END) as encrypted_count
FROM messages
WHERE content IS NULL
GROUP BY conversation_id
ORDER BY encrypted_count DESC;
```

### Phase 2: Backup & Prepare
```sql
-- Create backup of encrypted data
CREATE TABLE messages_encrypted_backup AS
SELECT id, content_encrypted, content_nonce
FROM messages
WHERE content_encrypted IS NOT NULL;

-- Mark backup for audit trail
ALTER TABLE messages_encrypted_backup
ADD COLUMN backed_up_at TIMESTAMPTZ DEFAULT NOW();
```

### Phase 3: Decryption & Backfill
```sql
-- If decryption keys are available:
UPDATE messages
SET content = decrypt_message(content_encrypted, content_nonce, master_key)
WHERE content IS NULL AND content_encrypted IS NOT NULL;

-- Verify decryption success
SELECT COUNT(*) as failed_decryptions
FROM messages
WHERE content_encrypted IS NOT NULL AND (content IS NULL OR length(content) = 0);
```

### Phase 3b: Re-encrypt using conversation keys

After migrating plaintext into `content`, re-apply the new Strict-E2E model so the REST API
returns `encrypted_payload` instead of plaintext:

```sql
-- Generate encrypted payloads using application logic.
-- Pseudo-code (execute via maintenance script):
-- for each strict_e2e conversation:
--   key = conversation_key(conversation_id)
--   for each message:
--       ciphertext, nonce = secretbox(content, key)
--       UPDATE messages SET
--           content_encrypted = ciphertext,
--           content_nonce = nonce,
--           encryption_version = 1,
--           content = ''
--       WHERE id = message_id;

-- At the SQL level, ensure any rows that still expose plaintext are marked as unavailable
UPDATE messages
SET content = '[Encrypted message unavailable]'
WHERE privacy_mode = 'strict_e2e' AND (content_encrypted IS NULL OR content_nonce IS NULL);
```

### Phase 4: Cleanup (After Verification)
```sql
-- Only after confirming all messages have plaintext content:
DELETE FROM messages_encrypted_backup;

-- Drop encrypted columns (if migration 0009 hasn't already)
ALTER TABLE messages DROP COLUMN IF EXISTS content_encrypted;
ALTER TABLE messages DROP COLUMN IF EXISTS content_nonce;
ALTER TABLE messages DROP COLUMN IF EXISTS encryption_algorithm;
```

## API-Level Compatibility

### Search API Changes

**Before (Using message_search_index):**
```sql
SELECT * FROM messages m
JOIN message_search_index si ON m.id = si.message_id
WHERE si.search_text @@ to_tsquery('query');
```

**After (Direct FTS on messages.content):**
```sql
SELECT * FROM messages m
WHERE m.content IS NOT NULL
  AND to_tsvector('english', m.content) @@ plainto_tsquery('english', 'query');
```

### GET Message API Changes

**No changes required** - Returns `content` field in plaintext for all messages

### POST/PUT Message API Changes

**Input:** Still accepts plaintext from clients
**Output:** Returns plaintext (never returns encrypted_content)

## Timeline & Execution

### Immediate (Now)
- ✅ Remove dual-path search index logic (DONE)
- ✅ Update search_messages to use direct FTS (DONE)
- ✅ Create migration 0011 for GIN index (DONE)
- [ ] Execute data migration (Phase 1-4 above)

### Short Term (This Sprint)
- [ ] Run assessment queries
- [ ] Create encrypted data backup
- [ ] Execute decryption (if keys available)
- [ ] Verify data integrity

### Medium Term (Next Release)
- [ ] Drop encrypted columns (migration 0012)
- [ ] Remove message_search_index table entirely (migration 0013)
- [ ] Update iOS client to remove encryption logic

## iOS Client Compatibility

### Current Behavior
- Client expects `encrypted_content` and `nonce` fields in API responses
- Client maintains local encryption for at-rest protection

### Migration Path
1. Server: Return BOTH `content` (plaintext) AND `encrypted_content` (for backward compat)
2. iOS: Accept plaintext, gradually remove encryption logic
3. Server: Eventually drop encrypted field support

**Note:** Requires separate iOS client update - coordinate with mobile team

## Monitoring & Validation

### Before Migration
```sql
SELECT
    COUNT(*) as total,
    AVG(length(content)) as avg_content_length,
    MIN(created_at) as oldest_plaintext,
    MAX(created_at) as newest_plaintext
FROM messages
WHERE content IS NOT NULL;
```

### After Migration
```sql
-- Verify all messages have content
SELECT COUNT(*) as missing_content
FROM messages
WHERE content IS NULL;

-- Verify search functionality
SELECT COUNT(*) as search_results
FROM messages m
WHERE to_tsvector('english', m.content) @@ plainto_tsquery('english', 'test')
  AND m.deleted_at IS NULL;
```

## Rollback Strategy

If migration fails:

1. Restore from `messages_encrypted_backup`
2. Keep current code (it supports both plaintext and encrypted)
3. Retry migration with corrected parameters
4. Coordinate with iOS team for extended support window

## Dependencies

- PostgreSQL TDE enabled (handles at-rest encryption)
- `master_key` available for decryption (if choosing Option A)
- iOS client updated to handle plaintext (if using Option 1 from API compat)

## Decision Point

**⚠️ ACTION REQUIRED:** Choose migration approach

- [ ] **Option A**: Decrypt & backfill (requires keys, best UX)
- [ ] **Option B**: Mark unrecoverable (simplest, loses history)
- [ ] **Option C**: Lazy decryption (deferred, performance impact)

Recommend: **Option A** if keys available, otherwise **Option B** with user notification
