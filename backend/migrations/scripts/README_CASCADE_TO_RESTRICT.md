# Migration 067 → 083: CASCADE to RESTRICT

## TL;DR

**Migration 067** implemented `ON DELETE CASCADE` for `messages.sender_id`.
**Migration 083** reverses this to `ON DELETE RESTRICT` + Outbox pattern.

**Why?** CASCADE violates soft-delete audit trail requirements.

**Action required:** None if you run migrations sequentially. Migration 083 is idempotent and cleans up Migration 067 automatically.

---

## Problem Statement

### Original Issue (Migration 067)

- `messages.sender_id` had no explicit `ON DELETE` behavior
- Hard deletes of users would fail due to FK constraint
- Solution: Added `ON DELETE CASCADE`

### Why CASCADE Was Wrong

1. **Audit Trail Violation**
   - CASCADE silently deletes messages when user is hard-deleted
   - No record of what was deleted or when
   - Violates GDPR "right to know what data was deleted"

2. **Microservices Architecture**
   - Messages might live in separate service/database
   - CASCADE can't work across service boundaries
   - Need event-driven cascade via Kafka

3. **Soft-Delete Pattern**
   - Nova uses soft-delete (`deleted_at` timestamp)
   - Hard deletes should be prevented, not cascaded
   - Cascade deletions should happen via events

---

## Solution (Migration 083)

### Correct Approach

```sql
ALTER TABLE messages
    ADD CONSTRAINT fk_messages_sender_id
    FOREIGN KEY (sender_id) REFERENCES users(id)
    ON DELETE RESTRICT;  -- ← Prevents hard deletes
```

### Cascade via Outbox Pattern

1. **User soft-deleted** → Trigger inserts event into `outbox_events`
2. **Kafka consumer** → Reads event, publishes to Kafka topic
3. **Messaging service** → Listens to Kafka, soft-deletes user's messages
4. **Audit trail** → Every step is logged (outbox + Kafka + application logs)

### Benefits

- ✅ Full audit trail (who deleted what and when)
- ✅ Works across microservices
- ✅ Retry-able (Kafka provides durability)
- ✅ Prevents accidental hard deletes
- ✅ GDPR compliant

---

## Migration Strategy

### Fresh Install (No Data)

Run migrations sequentially:
```bash
# Migration 067 will run (creates CASCADE constraint)
# Migration 083 will run (drops CASCADE, creates RESTRICT)
# Final state: RESTRICT + Outbox pattern
```

### Existing Database (With Data)

Migration 083 is **idempotent** and handles cleanup:
```sql
-- Drop all possible constraint names
DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
DROP CONSTRAINT IF EXISTS fk_messages_sender_id_cascade;  -- Migration 067
DROP CONSTRAINT IF EXISTS fk_messages_sender_id;          -- Migration 083 (idempotent)

-- Create correct constraint
ADD CONSTRAINT fk_messages_sender_id
    FOREIGN KEY (sender_id) REFERENCES users(id)
    ON DELETE RESTRICT;
```

### Verification

Run verification script:
```bash
psql -d nova_db -f backend/migrations/verify_foreign_key_constraints.sql
```

Expected output:
```
constraint_name         | fk_messages_sender_id
delete_rule             | RESTRICT
status                  | ✅ CORRECT
```

---

## Troubleshooting

### Scenario 1: Migration 083 Failed

**Symptoms:**
- `verify_foreign_key_constraints.sql` shows `CASCADE` or `NO ACTION`
- Migration 083 logs show errors

**Solution:**
```bash
# Run manual fix script (ONLY if 083 failed)
psql -d nova_db -f backend/migrations/manual_fix_cascade_to_restrict.sql
```

### Scenario 2: Cannot Drop Constraint

**Error:**
```
ERROR: cannot drop constraint messages_sender_id_fkey because other objects depend on it
```

**Cause:** Views or functions depend on the constraint

**Solution:**
```sql
-- Use CASCADE option (this is safe for FK constraints)
ALTER TABLE messages
    DROP CONSTRAINT messages_sender_id_fkey CASCADE;
```

### Scenario 3: Data Inconsistency After 067

**Symptoms:**
- Messages exist with `deleted_at = NULL` but `sender_id` points to deleted user
- Orphaned messages in database

**Cause:** Migration 067 was applied, user was hard-deleted via CASCADE

**Solution:**
```sql
-- Find orphaned messages
SELECT m.id, m.sender_id, m.created_at
FROM messages m
WHERE NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = m.sender_id
);

-- Option 1: Soft-delete orphaned messages
UPDATE messages
SET deleted_at = NOW(),
    deleted_by = 'system_migration_083_cleanup'
WHERE sender_id NOT IN (SELECT id FROM users);

-- Option 2: Hard-delete orphaned messages (if no audit trail needed)
DELETE FROM messages
WHERE sender_id NOT IN (SELECT id FROM users);
```

---

## File Reference

| File | Purpose |
|------|---------|
| `067_fix_messages_cascade.sql` | Original CASCADE migration (superseded) |
| `083_outbox_pattern_v2.sql` | Correct RESTRICT + Outbox pattern |
| `verify_foreign_key_constraints.sql` | Verification script |
| `manual_fix_cascade_to_restrict.sql` | Emergency manual fix (if 083 fails) |
| `README_CASCADE_TO_RESTRICT.md` | This document |

---

## Architectural Decision Record

**Decision:** Use `ON DELETE RESTRICT` + Outbox pattern for user → messages cascade

**Rationale:**
1. Soft-delete audit trail requirement
2. Microservices architecture (can't use database CASCADE across services)
3. Event-driven architecture (Kafka-based event propagation)
4. GDPR compliance (full audit trail of deletions)

**Alternatives Considered:**
- ❌ `ON DELETE CASCADE` → Violates audit trail
- ❌ `ON DELETE SET NULL` → Loses message authorship information
- ❌ `ON DELETE NO ACTION` → Allows orphaned messages
- ✅ `ON DELETE RESTRICT` + Outbox → Enforces correct workflow

**Consequences:**
- Hard deletes of users are prevented (must use soft-delete)
- Cascade deletions happen asynchronously via Kafka
- Full audit trail of all deletions
- Requires Kafka infrastructure (already in place)

---

## References

- [Outbox Pattern (Microservices.io)](https://microservices.io/patterns/data/transactional-outbox.html)
- [PostgreSQL Foreign Keys](https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK)
- [GDPR Right to Erasure](https://gdpr-info.eu/art-17-gdpr/)

---

**Last Updated:** 2025-11-06
**Migration Pair:** 067 (superseded) → 083 (current)
**Database:** PostgreSQL 14+
**Status:** ✅ Production Ready
