# Migration 120 - Critical Issues Report

## File: 120_critical_performance_indexes.sql

### Status: ⚠️ **BLOCKED - Cannot Deploy**

---

## 🔴 **BLOCKER Issues**

### 1. Missing Dependent Tables - engagement_events & trending_scores

**Location**: Lines 34-86

**Issue**:
The migration references tables `engagement_events` and `trending_scores` which do NOT exist in the main migration path.

**Evidence**:
- These tables are defined in `scripts/pending_review/035_trending_system.sql`
- File 035 has NOT been migrated to `backend/migrations/`
- Current migration files: 002-115, 118-119, 998-999
- No 035_trending_system.sql in the main migration directory

**Impact**:
- All indexes on `engagement_events` will FAIL (lines 34-57)
- Primary key on `trending_scores` will FAIL (line 65-67)
- All indexes on `trending_scores` will FAIL (lines 75-85)
- ANALYZE commands will FAIL (lines 115-116)

**Fix Required**:
```sql
-- Option 1: Deploy 035_trending_system.sql FIRST
-- Copy and rename:
cp backend/migrations/scripts/pending_review/035_trending_system.sql \
   backend/migrations/116_trending_system.sql

-- Then renumber 120 to 122 (after 035 becomes 116)
```

**Recommended Action**: Deploy 035_trending_system.sql as migration 116, then renumber this file to 122.

---

### 2. Missing Table: schema_migrations_log

**Location**: Line 125-131

**Issue**:
The migration tries to INSERT into `schema_migrations_log` table which does NOT exist.

**Evidence**:
```bash
$ grep -r "CREATE TABLE.*schema_migrations_log" backend/migrations/
# No results found
```

**Impact**:
- INSERT will FAIL with error: `relation "schema_migrations_log" does not exist`

**Fix Required**:
```sql
-- Remove lines 125-131 OR
-- Create the table first in a prior migration

-- Option 1: Remove logging (safe)
-- DELETE lines 125-131

-- Option 2: Create table (recommended)
CREATE TABLE IF NOT EXISTS schema_migrations_log (
    id SERIAL PRIMARY KEY,
    migration_number VARCHAR(10) NOT NULL,
    table_name TEXT,
    change_description TEXT,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Recommended Action**: Remove the INSERT statement (lines 125-131) or create the table in migration 116.

---

### 3. Wrong Column Name in comments Index

**Location**: Line 106

**Issue**:
Index uses `deleted_at IS NULL` but comments table uses `is_deleted` column.

**Current Code**:
```sql
CREATE INDEX IF NOT EXISTS idx_comments_post_created
ON comments(post_id, created_at DESC)
WHERE deleted_at IS NULL;  -- ❌ WRONG COLUMN
```

**Actual Table Schema** (from 100_social_service_schema.sql):
```sql
CREATE TABLE comments (
    ...
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,  -- ✅ Correct column
    ...
);
```

**Impact**:
- Index creation will FAIL with error: `column "deleted_at" does not exist`

**Fix Required**:
```sql
-- Change line 106 to:
CREATE INDEX IF NOT EXISTS idx_comments_post_created
ON comments(post_id, created_at DESC)
WHERE is_deleted = FALSE;  -- ✅ Use is_deleted instead
```

---

### 4. REINDEX CONCURRENTLY Inside Transaction

**Location**: Lines 188-189

**Issue**:
`REINDEX CONCURRENTLY` cannot run inside a transaction block.

**Current Code**:
```sql
BEGIN;  -- Line 22
...
REINDEX INDEX CONCURRENTLY idx_engagement_events_content_id;  -- ❌ FAILS
REINDEX INDEX CONCURRENTLY idx_trending_scores_rank;          -- ❌ FAILS
COMMIT; -- Line 191
```

**Error**:
```
ERROR: REINDEX CONCURRENTLY cannot run inside a transaction block
```

**Impact**:
- Migration will FAIL at line 188

**Fix Required**:
```sql
-- Option 1: Remove CONCURRENTLY keyword
REINDEX INDEX idx_engagement_events_content_id;
REINDEX INDEX idx_trending_scores_rank;

-- Option 2: Remove REINDEX commands entirely
-- (Not needed for new indexes, only for rebuilding existing ones)

-- Option 3: Move REINDEX outside transaction
COMMIT;
REINDEX INDEX CONCURRENTLY idx_engagement_events_content_id;
REINDEX INDEX CONCURRENTLY idx_trending_scores_rank;
```

**Recommended Action**: Remove REINDEX commands (lines 187-189) as they're unnecessary for new indexes.

---

## ⚠️ **P1 Issues (High Priority)**

### 5. Duplicate Index: idx_posts_user_created

**Location**: Line 95-97

**Issue**:
Index `idx_posts_user_created` already exists from migration 003_posts_schema.sql.

**Evidence**:
```sql
-- From 003_posts_schema.sql (already deployed):
CREATE INDEX idx_posts_user_created
ON posts(user_id, created_at DESC)
WHERE soft_delete IS NULL;

-- This migration (line 95-97):
CREATE INDEX IF NOT EXISTS idx_posts_user_created  -- ✅ Has IF NOT EXISTS
ON posts(user_id, created_at DESC)
WHERE deleted_at IS NULL;  -- ❌ WRONG: should be soft_delete
```

**Impact**:
- No immediate failure (IF NOT EXISTS prevents error)
- But the WHERE clause is WRONG (deleted_at should be soft_delete)
- Index will be skipped entirely due to IF NOT EXISTS

**Fix Required**:
```sql
-- Option 1: Remove entirely (index already exists)
-- DELETE lines 95-97

-- Option 2: Fix column name
CREATE INDEX IF NOT EXISTS idx_posts_user_created
ON posts(user_id, created_at DESC)
WHERE soft_delete IS NULL;  -- ✅ Correct column name
```

**Recommended Action**: Remove lines 95-97 as index already exists with correct definition.

---

## 📋 **Summary of Fixes**

### Blocking Issues (Must Fix Before Deploy):
1. ✅ Deploy 035_trending_system.sql as migration 116
2. ✅ Renumber 120 → 122 (after 035 becomes 116)
3. ✅ Remove schema_migrations_log INSERT (lines 125-131)
4. ✅ Fix comments index WHERE clause: `is_deleted = FALSE` (line 106)
5. ✅ Remove REINDEX commands (lines 187-189)

### High Priority Issues:
6. ✅ Remove duplicate idx_posts_user_created (lines 95-97)

---

## 🔧 **Recommended Action Plan**

### Step 1: Pre-requisite Migration
```bash
# Deploy trending system FIRST
cp backend/migrations/scripts/pending_review/035_trending_system.sql \
   backend/migrations/116_trending_system.sql
```

### Step 2: Renumber Files
```bash
# Renumber performance indexes
mv backend/migrations/120_critical_performance_indexes.sql \
   backend/migrations/122_critical_performance_indexes.sql
```

### Step 3: Apply Fixes to 122_critical_performance_indexes.sql
```sql
-- Fix 1: Line 106 - comments index
CREATE INDEX IF NOT EXISTS idx_comments_post_created
ON comments(post_id, created_at DESC)
WHERE is_deleted = FALSE;  -- Changed from deleted_at IS NULL

-- Fix 2: Remove lines 95-97 (duplicate index)
-- DELETE entire section

-- Fix 3: Remove lines 125-131 (schema_migrations_log)
-- DELETE entire section

-- Fix 4: Remove lines 187-189 (REINDEX CONCURRENTLY)
-- DELETE:
-- -- Reindex to optimize storage
-- REINDEX INDEX CONCURRENTLY idx_engagement_events_content_id;
-- REINDEX INDEX CONCURRENTLY idx_trending_scores_rank;
```

---

## ✅ **After Fixes Applied**

Migration 122 will be safe to deploy AFTER migration 116 (trending system).

**Estimated Performance Impact** (as advertised):
- engagement_events queries: 12.5s → 0.5ms (25,000x improvement)
- trending_scores queries: 2-5s → 0.1ms (20,000-50,000x improvement)
- Database CPU: -50-70%
- Connection utilization: -30-50%

**Deployment Time**: ~5-10 minutes (index creation on large tables)
