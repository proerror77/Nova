# Tasks: Database Schema Consolidation

## Phase 0: Freeze & Inventory

- [ ] T000 Add migration freeze note in `backend/migrations/` README
- [ ] T001 Produce data dictionary in `docs/db/data_dictionary.md`

## Phase 1: Users Canonicalization

- [ ] T010 Identify and remove shadow `users` tables in `auth/user/messaging` services
- [ ] T011 Add foreign keys to canonical `auth.users` where needed (or service API if cross-db not allowed)

## Phase 2: Soft Delete

- [ ] T020 Migrate `soft_delete`/`deleted` columns to `deleted_at TIMESTAMPTZ NULL`
- [ ] T021 Update application queries to predicate on `deleted_at IS NULL`

## Phase 3: Redundancy & Indexes

- [ ] T030 Drop duplicated counters; add mat-views or single-source updates
- [ ] T031 Add missing composite indexes on `user_id` and hot paths

