# Nova Specs Index

This index anchors living specs to implementation. It focuses on Phase 7B for now.

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

