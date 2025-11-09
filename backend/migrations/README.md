# Database Migrations

This directory contains all PostgreSQL migrations for the Nova platform.

## ⚠️ MIGRATION FREEZE (Spec 007: Database Schema Consolidation)

**Effective Date**: 2025-11-05
**Duration**: 12 weeks (through January 2026)
**Status**: FROZEN - New migrations require review and approval

### Why?

We are consolidating duplicated database schemas across services using the **Strangler Pattern**:
1. **Users Table Unification** - Consolidate shadow `users` tables in auth-service, messaging-service, and user-service
2. **Soft Delete Normalization** - Standardize all soft deletes to use `deleted_at TIMESTAMPTZ NULL`
3. **Redundancy Removal** - Eliminate duplicate counters and denormalized data
4. **Index & FK Strategy** - Add missing composite indexes and fix foreign key constraints

### Migration Guidelines

**FROZEN - Do NOT commit new migrations without approval!**

Before submitting a new migration:
1. Contact the database architect (see CODEOWNERS)
2. Explain why this cannot be deferred until Jan 2026
3. Get explicit approval with a comment in the PR
4. Coordinate with Phase 0-2 strangler migrations to avoid conflicts

### Phases

- **Phase 0 (Week 1-2)**: Freeze + Data Dictionary + Ownership Matrix
- **Phase 1 (Week 3-4)**: Users table unification; auth-service canonical source
- **Phase 2 (Week 5-6)**: Soft delete normalization (`deleted_at`)
- **Phase 3 (Week 7-8)**: Redundancy removal; aggregation strategy
- **Phase 4 (Week 9-10)**: FK & index cleanup; composite indexes
- **Phase 5 (Week 11-12)**: Cutover; shim deprecation; validation

### Current Schema Issues

#### Duplicate Users Tables
```
backend/migrations/001_initial_schema.sql       → users table (ROOT)
backend/auth-service/migrations/...             → users table (SHADOW)
backend/messaging-service/migrations/...        → users table (SHADOW)
backend/user-service/migrations/...             → users table (SHADOW)
```

**Goal**: Single canonical `users` table in auth-service. All other services reference by `user_id` only.

#### Soft Delete Inconsistency
- Some tables use `deleted BOOLEAN`
- Some use `soft_delete BOOLEAN`
- Some already use `deleted_at TIMESTAMPTZ`

**Goal**: Standardize to `deleted_at TIMESTAMPTZ NULL` across all tables.

#### Redundant Counters
- `posts.like_count` + `likes` table (dual source of truth)
- `comments.reply_count` + separate `replies` table
- `users.follower_count` + `follows` table

**Goal**: Remove denormalized counters; compute from materialized views or live aggregates.

### Migration Numbering

Current highest: **070** (as of Nov 5, 2025)

All new Phase 0-5 strangler migrations will use **071-100** range reserved for consolidation work.

### Testing

Run migrations locally before deployment:
```bash
# In nova/ root
sqlx migrate run --database-url postgresql://user:pass@localhost/nova_db

# Verify schema consistency
psql -d nova_db -c '\dt'  # List all tables
```

### Questions?

See: `specs/007-p1-db-schema-consolidation/`
- `spec.md` - Full requirements
- `plan.md` - 12-week timeline
- `tasks.md` - Detailed tasks
