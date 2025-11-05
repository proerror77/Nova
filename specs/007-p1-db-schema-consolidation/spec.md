# Feature Specification: Database Schema Consolidation (Strangler Pattern)

**Feature Branch**: `[007-p1-db-schema-consolidation]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Unify users table, normalize soft delete, remove redundancy, fix FK/index strategy"

## Verification (code audit) — 2025-11-05

- Duplicate `users` schemas confirmed:
  - Root migrations: `backend/migrations/001_initial_schema.sql` defines `users`.
  - auth-service: `backend/auth-service/migrations/001_create_users_table.sql` defines `users`.
  - messaging-service: `backend/messaging-service/migrations/0001_create_users.sql` defines a shadow `users`.
- Soft-delete normalization work observed (migrations 066, 070), but duplicates remain.
  - References: `backend/migrations/082_unify_soft_delete_v2.sql`, `backend/migrations/070_unify_soft_delete_complete.sql`.

Action:
- Freeze new migrations; plan strangler migrations to consolidate on auth-service `users` as the single source of truth and drop shadows.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single Source of Truth: users (Priority: P1)

As a platform, I need one canonical `users` schema (auth-service) with other services referencing it by `user_id` only; no shadow tables.

**Independent Test**: New migrations remove/rename duplicated `users` tables; cross-service queries rely on IDs not local copies.

**Acceptance Scenarios**:
1. Given messaging-service duplicated users schema, When consolidation is applied, Then it references auth.users and drops shadow schema.

---

### User Story 2 - Consistent soft delete (Priority: P1)

As a maintainer, I want all entities to use `deleted_at TIMESTAMPTZ NULL` (no booleans), with cascades disabled or carefully scoped.

**Independent Test**: All services handle soft-deleted rows uniformly; FKs do not hard-delete.

---

### User Story 3 - Remove redundancy (Priority: P1)

As an operator, I want redundant tables/columns (e.g., duplicate like_count) removed; aggregation via single source or materialized views.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Freeze new migrations (review gate) while consolidation proceeds.
- FR-002: Author phased migrations to: unify `users`, normalize soft delete fields, remove redundant counters, standardize FKs, and add missing composite indexes.
- FR-003: Provide data backfills and triggers to bridge old→new during cutover.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: 0 duplicate `users` schemas; documented data dictionary.
- SC-002: All soft deletes represented by `deleted_at` consistently.
- SC-003: Query plans show correct index usage on hot paths.
