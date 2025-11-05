# Tasks: CI-Ready Tests via Testcontainers

**Status**: ✅ COMPLETE (5/5 tasks)

- [X] T001 Add `testcontainers` to workspace and service test deps ✅
  - Added testcontainers 0.17 to workspace Cargo.toml with postgres, redis features
  - Added to content-service, auth-service, user-service dev-dependencies

- [X] T002 Create shared harness in `backend/tests/common/testcontainers.rs` ✅
  - PostgresContainer fixture with wait_ready() and connection_string()
  - RedisContainer fixture with wait_ready() and connection_string()
  - Combined TestEnvironment for coordinated container startup
  - Automatic cleanup on drop

- [X] T003 Migrate `backend/content-service/tests/grpc_content_service_test.rs` off `#[ignore]` ✅
  - Removed all 11 `#[ignore]` markers from gRPC tests
  - Removed SERVICES_RUNNING environment variable checks
  - Tests now run directly when infrastructure is available
  - Updated documentation with docker-compose usage

- [X] T004 Remove placeholder tests: `backend/content-service/tests/{posts_test.rs,comments_test.rs,stories_test.rs}` ✅
  - Deleted empty shells (3 files)
  - Removed test declarations from Cargo.toml

- [X] T005 Update CI workflow to allow Docker tests ✅
  - Created `.github/workflows/integration-tests.yml` workflow
  - Includes Postgres and Redis services via GitHub Actions
  - Runs integration tests with proper environment setup
  - Supports coverage reporting
  - Created `/backend/INTEGRATION_TESTS.md` with comprehensive testing guide

**Key Achievements**:
- Testcontainers infrastructure fully in place
- All 11 ignored gRPC tests in content-service now enabled
- CI/CD workflow ready for automated integration testing
- Comprehensive documentation for local and CI testing
- Docker Compose support verified and documented

