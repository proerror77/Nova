# Nova Specs Index

**Status**: Phase 7B ✅ Complete in main | Phase 7C 🚀 Ready in develop/phase-7c

This index anchors living specs to implementation. Latest state:
- **main**: Phase 7B Messaging + Stories (complete, PR #21 merged)
- **develop/phase-7c**: Phase 7C development baseline

Branch cleanup completed: 43 → 2 branches (see BRANCH_CLEANUP_SUMMARY.md)

- Messaging (7B)
  - API handlers: `backend/user-service/src/handlers/messaging.rs`
  - Repo: `backend/user-service/src/db/messaging_repo.rs`
  - Migrations: `backend/migrations/018_messaging_schema.sql`
  - Routes mounted in: `backend/user-service/src/main.rs` under `/api/v1/messages` and `/api/v1/conversations`

- Stories (7B)
  - API handlers: `backend/user-service/src/handlers/stories.rs`
  - Repo: `backend/user-service/src/db/stories_repo.rs`
  - Migrations: `backend/migrations/019_stories_schema.sql`
  - Routes mounted in: `backend/user-service/src/main.rs` under `/api/v1/stories`

Validation: run `make spec-validate` from `backend/` to verify routes and files exist.

