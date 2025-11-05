# Tasks: Database Schema Consolidation

**Status**: Phase 0 COMPLETE (2/2 tasks)

## Phase 0: Freeze & Inventory ✅

- [X] T000 Add migration freeze note in `backend/migrations/` README ✅
  - Created `backend/migrations/README.md` with migration freeze notice
  - Documented all 5 phases (0-5) with timeline and current issues
  - Clear guidelines for requesting migration exceptions
  - Links to specification for reference

- [X] T001 Produce data dictionary in `docs/db/data_dictionary.md` ✅
  - Complete inventory of all 50+ tables by domain
  - Identified duplicate users tables (auth-service, messaging-service, user-service)
  - Documented soft-delete inconsistencies (deleted_at vs deleted BOOLEAN)
  - Flagged redundant counters (like_count, comment_count, reply_count)
  - Service ownership matrix
  - Solution approaches for each category

## Phase 1: Users Canonicalization ⏳

- [X] T010 Implement auth-service gRPC client in messaging-service ✅
  - Created `backend/messaging-service/src/services/auth_client.rs` with gRPC bindings
  - Modified build.rs to generate AuthServiceClient from proto
  - Updated config.rs to accept AUTH_SERVICE_URL environment variable
  - Integrated auth-client into AppState initialization
  - Updated `routes/groups.rs` add_member() to use auth-service instead of shadow users table
  - Replaced direct SQL queries with gRPC calls:
    * `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)` → `auth_client.user_exists()`
    * `SELECT username FROM users WHERE id = $1` → `auth_client.get_user()`
  - Benefits: Eliminates shadow users table dependency, centralizes user source of truth

- [ ] T011 Add foreign keys to canonical `auth.users` where needed (or service API if cross-db not allowed)
  - TODO: Add FK constraints from messaging_service.conversation_members.user_id → auth.users.id

## Phase 2: Soft Delete

- [ ] T020 Migrate `soft_delete`/`deleted` columns to `deleted_at TIMESTAMPTZ NULL`
- [ ] T021 Update application queries to predicate on `deleted_at IS NULL`

## Phase 3: Redundancy & Indexes

- [ ] T030 Drop duplicated counters; add mat-views or single-source updates
- [ ] T031 Add missing composite indexes on `user_id` and hot paths

