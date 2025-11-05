# Tasks: CI-Ready Tests via Testcontainers

**Status**: ⏳ PARTIAL - 1/5 tasks (cleanup complete, infrastructure work needed)

- [ ] T001 Add `testcontainers` to workspace and service test deps
- [ ] T002 Create shared harness in `backend/tests/common/testcontainers.rs` (new)
- [ ] T003 Migrate `backend/content-service/tests/grpc_content_service_test.rs` off `#[ignore]`
- [X] T004 Remove placeholder tests: `backend/content-service/tests/{posts_test.rs,comments_test.rs,stories_test.rs}` ✅ DELETED (empty shells)
- [ ] T005 Update CI workflow to allow Docker tests

**Notes**:
- Empty placeholder files removed (3 files)
- T001-T003, T005 require:
  - Adding testcontainers crate to Cargo.toml
  - Building container fixtures for Postgres, Redis, Kafka
  - Refactoring ignored tests to use fixtures
  - CI pipeline updates for Docker-in-Docker

