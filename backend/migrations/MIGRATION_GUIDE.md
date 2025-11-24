# Database Migration Guide

## Critical Issues Fixed (2025-11-24)

### 1. Duplicate Performance Optimization Migrations

**Problem**: Migrations 117 and 121 contained identical performance optimizations.

**Solution**: Migration 121 has been deleted. Use migration 117 only.

### 2. Destructive DROP TABLE Operations

**Problem**: Migrations 998, 999, and 100 used `DROP TABLE ... CASCADE` which causes permanent data loss.

**Solution**: Converted to expand-contract pattern:

#### Migration 998: Messaging Schema Deprecation
- **998_deprecate_old_messaging_schema.sql** - EXPAND phase: Marks tables as deprecated, disables triggers
- **998b_drop_old_messaging_schema.sql** - CONTRACT phase: Actually drops tables (run only after data migration)

#### Migration 999: Social Schema Cleanup
- **999_cleanup_social_conflicts.sql** - EXPAND phase: Marks tables as deprecated, disables triggers
- **999b_drop_old_social_schema.sql** - CONTRACT phase: Actually drops tables (run only after data migration)

#### Migration 100: Social Service Schema
- Changed from `DROP TABLE IF EXISTS` to `CREATE TABLE IF NOT EXISTS`
- Safe to run on existing databases

### 3. Duplicate Table Definitions

**Problem**: `likes`, `comments`, and `social_metadata` tables defined in both migration 004 and migration 100 with conflicting schemas.

**Solution**:

#### For New Installations
1. Skip migration 004 social tables (they're deprecated)
2. Use migration 100 which has the improved social-service schema

#### For Existing Installations
1. Migration 004 created basic `likes`, `comments`, `social_metadata` tables
2. Migration 999 deprecates them (disables triggers, adds warnings)
3. Migrate data from old schema to new schema (see DATA_MIGRATION.md)
4. Migration 999b drops old tables
5. Migration 100 creates new social-service schema

## Table Ownership Matrix

| Table | Owned By | Defined In Migration | Status |
|-------|----------|---------------------|--------|
| `users` | identity-service | 001 | ✅ Active |
| `posts` | content-service | 003 | ✅ Active |
| `follows` | graph-service | 004 | ✅ Active |
| `likes` (old) | N/A | 004 | ⚠️ Deprecated (use migration 100) |
| `comments` (old) | N/A | 004 | ⚠️ Deprecated (use migration 100) |
| `social_metadata` (old) | N/A | 004 | ⚠️ Deprecated (use migration 100) |
| `likes` (new) | social-service | 100 | ✅ Active |
| `comments` (new) | social-service | 100 | ✅ Active |
| `shares` | social-service | 100 | ✅ Active |
| `post_counters` | social-service | 100 | ✅ Active |
| `conversations` (old) | N/A | 018 | ⚠️ Deprecated (use realtime-chat) |
| `messages` (old) | N/A | 018 | ⚠️ Deprecated (use realtime-chat) |

## Migration Sequence for Production

### Phase 1: Deprecation (Safe - No Data Loss)
```bash
# Already applied if you're on latest
sqlx migrate run --database-url $DATABASE_URL
# This runs migrations 998, 999 which mark tables as deprecated
```

### Phase 2: Verify Deprecation
```sql
-- Check that deprecated tables have triggers disabled
SELECT tgrelid::regclass, tgenabled FROM pg_trigger
WHERE tgrelid::regclass::text IN ('messages', 'conversations', 'post_shares', 'social_metadata');
-- All should show 'D' (disabled)
```

### Phase 3: Deploy New Services
```bash
# Deploy social-service with migration 100 schema
# Deploy realtime-chat-service with new messaging schema
kubectl apply -f k8s/microservices/social-service-deployment.yaml
kubectl apply -f k8s/microservices/realtime-chat-service-deployment.yaml
```

### Phase 4: Data Migration (Run Scripts)
```bash
# Migrate social data from old to new schema
psql $DATABASE_URL -f backend/migrations/scripts/migrate_social_data.sql

# Migrate messaging data from old to new schema
psql $DATABASE_URL -f backend/migrations/scripts/migrate_messaging_data.sql
```

### Phase 5: Verify Data Migration
```sql
-- Check that all data was migrated
SELECT
  (SELECT COUNT(*) FROM likes) as new_likes,
  (SELECT COUNT(*) FROM old_likes_backup) as old_likes;
-- Counts should match
```

### Phase 6: CONTRACT Phase (Destructive - Run Only After Verification)
```bash
# WARNING: This permanently deletes old tables
# Backup first!
pg_dump $DATABASE_URL > backup_$(date +%Y%m%d).sql

# Drop old messaging schema
sqlx migrate run --source backend/migrations/998b_drop_old_messaging_schema.sql

# Drop old social schema
sqlx migrate run --source backend/migrations/999b_drop_old_social_schema.sql
```

## Rollback Plan

If something goes wrong during migration:

### Rollback Deprecation (Re-enable Old Schema)
```bash
sqlx migrate revert --database-url $DATABASE_URL
# This runs .down.sql files for migrations 998, 999
```

### Emergency Restore
```bash
# Restore from backup if data was lost
psql $DATABASE_URL < backup_YYYYMMDD.sql
```

## Best Practices

1. **Never modify old migrations** - They're already applied in production
2. **Always use expand-contract pattern** for schema changes
3. **Test migrations on staging first**
4. **Always backup before running CONTRACT phase**
5. **Keep rollback migrations** (.down.sql files) for all critical operations

## References

- [Expand-Contract Pattern](https://www.martinfowler.com/bliki/ParallelChange.html)
- [Zero-Downtime Database Migrations](https://fly.io/blog/zero-downtime-postgres-migrations/)
