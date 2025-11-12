# Migration 121 - Critical Issues Report

## File: 121_performance_optimization_p0.sql

### Status: ⚠️ **PARTIAL - Needs Fixes**

---

## 🟡 **P1 Issues (High Priority)**

### 1. Missing Column: conversations.last_sequence_number

**Location**: Lines 12-34

**Issue**:
The migration adds `last_sequence_number` to conversations table, but this column is needed for the trigger function.

**Current Schema** (from 102_create_conversations.sql):
```sql
CREATE TABLE conversations (
    id UUID PRIMARY KEY,
    kind conversation_type NOT NULL,
    name TEXT,
    description TEXT,
    member_count INT NOT NULL DEFAULT 0,
    last_message_id UUID,  -- ✅ Exists
    -- ❌ last_sequence_number is MISSING
    -- ❌ last_message_at is MISSING
    privacy_mode privacy_mode NOT NULL DEFAULT 'strict_e2e',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Impact**:
- Lines 12-14: ALTER TABLE will ADD the column (✅ OK)
- Lines 30-34: UPDATE query will work (✅ OK)
- Lines 37-60: Trigger function will work AFTER column is added (✅ OK)

**Status**: ✅ **NO FIX NEEDED** - Migration correctly adds the missing column first.

---

### 2. Missing Column: conversations.last_message_at

**Location**: Lines 68-78

**Issue**:
The migration references `last_message_at` but this column doesn't exist in the base schema.

**Current Code**:
```sql
-- Line 71 (ALTER TABLE)
ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ;  -- ✅ Will be added

-- Line 78 (Backfill)
last_message_at = (SELECT created_at FROM messages ...)  -- ✅ OK after ADD
```

**Status**: ✅ **NO FIX NEEDED** - Migration correctly adds the column before using it.

---

### 3. Duplicate Column: messages.sequence_number

**Location**: Lines 9-10

**Issue**:
The migration tries to add `sequence_number` column, but it already exists.

**Current Schema** (from 104_create_messages.sql):
```sql
CREATE TABLE messages (
    ...
    sequence_number BIGSERIAL NOT NULL,  -- ✅ Already exists as BIGSERIAL
    ...
);
```

**Migration Code**:
```sql
-- Line 9-10
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS sequence_number BIGINT DEFAULT 0;  -- ⚠️ Type mismatch
```

**Impact**:
- Column will NOT be added (IF NOT EXISTS skips it)
- But the existing type is `BIGSERIAL` (auto-incrementing)
- Migration assumes manual assignment via trigger

**Conflict**:
- Existing schema: Uses PostgreSQL's BIGSERIAL auto-increment
- This migration: Expects manual assignment via trigger (lines 37-60)

**Fix Required**:
```sql
-- Option 1: Remove ADD COLUMN (keep existing BIGSERIAL)
-- DELETE lines 9-10
-- DELETE lines 16-34 (backfill)
-- DELETE lines 37-60 (trigger - conflicts with BIGSERIAL)

-- Option 2: Change existing BIGSERIAL to BIGINT
-- In migration:
-- Step 1: Drop default sequence
ALTER TABLE messages ALTER COLUMN sequence_number DROP DEFAULT;
DROP SEQUENCE IF EXISTS messages_sequence_number_seq;

-- Step 2: Add trigger for manual assignment
CREATE TRIGGER set_message_sequence ...
```

**Recommended Action**: Remove lines 9-10, 16-34, 37-60 as `sequence_number` already exists with BIGSERIAL auto-increment (simpler and more reliable than trigger-based).

---

### 4. Potential Conflict: Generated Column content_tsv

**Location**: Lines 133-141

**Issue**:
The migration creates a GENERATED column on `content`, but migration 105 already created a GIN index for FTS.

**Existing Index** (from 105_add_message_content_fields.sql):
```sql
CREATE INDEX IF NOT EXISTS idx_messages_content_fulltext
ON messages USING GIN (to_tsvector('english', content));
```

**This Migration** (lines 133-137):
```sql
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS content_tsv tsvector
GENERATED ALWAYS AS (
    to_tsvector('english', COALESCE(content, ''))
) STORED;
```

**Analysis**:
- ✅ Both approaches work for full-text search
- Migration 105: Uses functional index (no extra column)
- This migration: Uses GENERATED column (extra storage)

**Impact**:
- Column will be added successfully (no conflict)
- But now we have TWO FTS solutions:
  1. Functional index on `to_tsvector('english', content)`
  2. Generated column `content_tsv` with GIN index
- Wastes disk space (duplicate data)

**Fix Required**:
```sql
-- Option 1: Remove GENERATED column (keep functional index from 105)
-- DELETE lines 133-141

-- Option 2: Drop old functional index (use GENERATED column)
DROP INDEX IF EXISTS idx_messages_content_fulltext;  -- From migration 105
-- Keep lines 133-141
```

**Recommended Action**: Remove lines 133-141 as migration 105 already provides FTS via functional index.

---

### 5. Duplicate Index: idx_messages_conversation_ts_id

**Location**: Lines 153-155

**Issue**:
Index `idx_messages_conversation_ts_id` may conflict with existing indexes.

**Existing Indexes** (from 105_add_message_content_fields.sql):
```sql
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
ON messages(conversation_id, created_at DESC);
```

**This Migration** (line 153-155):
```sql
CREATE INDEX IF NOT EXISTS idx_messages_conversation_ts_id
ON messages(conversation_id, created_at DESC, id DESC)
WHERE deleted_at IS NULL;
```

**Analysis**:
- ✅ Different index name → no conflict
- ✅ Has additional column `id` → covers more queries
- ✅ Has WHERE clause → smaller index size
- Old index is less efficient (missing `id` and no filter)

**Recommendation**:
```sql
-- Keep new index (line 153-155) as it's better
-- Drop old index from migration 105:
DROP INDEX IF EXISTS idx_messages_conversation_created;

-- Add this DROP before CREATE INDEX (line 152):
DROP INDEX IF EXISTS idx_messages_conversation_created;
CREATE INDEX IF NOT EXISTS idx_messages_conversation_ts_id ...
```

**Status**: ⚠️ **Recommended Optimization** - Drop old index to avoid redundancy.

---

### 6. Wrong Column Name: posts Index

**Location**: Lines 158-160

**Issue**:
Index uses `soft_delete IS NULL` which is correct, but should verify column exists.

**Current Schema** (from 003_posts_schema.sql):
```sql
CREATE TABLE posts (
    ...
    soft_delete TIMESTAMP WITH TIME ZONE,  -- ✅ Correct name
    ...
);
```

**Status**: ✅ **NO FIX NEEDED** - Column name is correct.

---

### 7. Missing Check: deleted_at Column in messages

**Location**: Line 155

**Issue**:
Index filter uses `WHERE deleted_at IS NULL` but messages table schema has `deleted_at`.

**Current Schema** (from 104_create_messages.sql):
```sql
CREATE TABLE messages (
    ...
    deleted_at TIMESTAMPTZ,  -- ✅ Column exists
    ...
);
```

**Status**: ✅ **NO FIX NEEDED** - Column exists.

---

## 📋 **Summary of Fixes**

### Critical Fixes:
1. ⚠️ Remove duplicate sequence_number handling (lines 9-10, 16-34, 37-60)
   - Reason: Column already exists as BIGSERIAL
   - Trigger conflicts with auto-increment

2. ⚠️ Remove duplicate content_tsv generated column (lines 133-141)
   - Reason: FTS index already exists from migration 105
   - Wastes disk space

### Recommended Optimizations:
3. ✅ Drop old idx_messages_conversation_created before creating new index
   - Add: `DROP INDEX IF EXISTS idx_messages_conversation_created;` before line 153

---

## 🔧 **Recommended Action Plan**

### Step 1: Remove Conflicting Code

**Remove sequence_number handling** (lines 9-60):
```sql
-- DELETE lines 9-10:
-- ALTER TABLE messages
-- ADD COLUMN IF NOT EXISTS sequence_number BIGINT DEFAULT 0;

-- DELETE lines 12-14:
-- ALTER TABLE conversations
-- ADD COLUMN IF NOT EXISTS last_sequence_number BIGINT DEFAULT 0;

-- DELETE lines 16-34:
-- WITH numbered_messages AS (...)
-- UPDATE messages m ...

-- DELETE lines 29-34:
-- UPDATE conversations c
-- SET last_sequence_number = ...

-- DELETE lines 37-60:
-- CREATE OR REPLACE FUNCTION assign_message_sequence()
-- ...
-- CREATE TRIGGER set_message_sequence ...
```

**Remove duplicate FTS column** (lines 133-141):
```sql
-- DELETE lines 133-141:
-- ALTER TABLE messages
-- ADD COLUMN IF NOT EXISTS content_tsv tsvector
-- GENERATED ALWAYS AS (...)
-- STORED;
--
-- CREATE INDEX IF NOT EXISTS idx_messages_content_tsv
-- ON messages USING GIN(content_tsv);
```

---

### Step 2: Add Missing Columns (Keep These)

**Keep last_message_at addition** (line 71):
```sql
ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS member_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_message_id UUID,
ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ;  -- ✅ Add this
```

**Keep backfill** (lines 74-78):
```sql
UPDATE conversations c
SET
    member_count = ...,
    last_message_id = ...,
    last_message_at = ...;  -- ✅ Backfill this
```

---

### Step 3: Optimize Index Strategy

**Drop old index before creating new one** (before line 153):
```sql
-- Add this line:
DROP INDEX IF EXISTS idx_messages_conversation_created;

-- Then create new index:
CREATE INDEX IF NOT EXISTS idx_messages_conversation_ts_id
ON messages(conversation_id, created_at DESC, id DESC)
WHERE deleted_at IS NULL;
```

---

### Step 4: Keep Essential Parts

**Keep these sections** (they're correct):
- ✅ Lines 81-126: Triggers for member_count and last_message (essential for denormalization)
- ✅ Lines 144-170: Composite indexes (critical for performance)
- ✅ Lines 173-211: Analyze and logging (safe and useful)

---

## ✅ **After Fixes Applied**

Migration 121 will:
1. ✅ Add missing `last_message_at` column to conversations
2. ✅ Add denormalization triggers for conversations
3. ✅ Add optimized composite indexes
4. ✅ Analyze tables for query planner

**What's Removed**:
1. ❌ Duplicate sequence_number logic (already handled by BIGSERIAL)
2. ❌ Duplicate FTS column (already handled by functional index)

**Estimated Performance Impact**:
- Conversation queries: 3-5x faster (denormalization)
- Message pagination: 2-3x faster (optimized indexes)
- Message search: Already optimized in migration 105

**Deployment Time**: ~2-5 minutes (trigger and index creation)
