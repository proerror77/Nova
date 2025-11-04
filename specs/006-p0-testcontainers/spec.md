# Feature Specification: CI-Ready Tests (Remove #[ignore] via Testcontainers)

**Feature Branch**: `[006-p0-testcontainers]`
**Created**: 2025-11-04
**Status**: Draft
**Priority**: P0 (Critical for CI/CD automation & test coverage)
**Input**: User description: "Remove #[ignore], add testcontainers, delete empty tests"

## Verification (code audit) — 2025-11-05

- `#[ignore]` is widespread across services, especially integration tests requiring infra:
  - content-service gRPC tests: `backend/content-service/tests/grpc_content_service_test.rs:66,154,260...` (multiple ignored tests; note SERVICES_RUNNING gating comment at 683).
  - messaging-service E2EE/group call: many `#[ignore]` markers; see `backend/messaging-service/tests/e2ee_integration_test.rs` and `group_call_integration_test.rs`.
  - user-service perf/integration tests: e.g., `backend/user-service/tests/performance/events_load_test.rs:55`.
- Positive example: user-service ClickHouse CDC tests already use `testcontainers`.
  - Reference: `backend/user-service/tests/integration/cdc_clickhouse_tests.rs`.

Action:
- Convert ignored tests to use `testcontainers` (Postgres, Redis, Kafka) and remove env gating; delete empty placeholder test files.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Integration tests run in CI (Priority: P0 - Critical)

As a developer, I want integration tests to bring up dependencies automatically (Postgres, Redis, Kafka) so they can run in CI without manual flags.

**Independent Test**: `cargo test -p content-service` runs all previously ignored gRPC tests with testcontainers.

**Acceptance Scenarios**:
1. Given previous `#[ignore]` tests in content-service, When running tests in CI, Then they run and pass using containers.
2. Given CURRENT env gating like `SERVICES_RUNNING=true`, When removed, Then tests still work.

### User Story 2 - Remove dead tests (Priority: P2)

As a maintainer, I want empty placeholder test files removed to avoid false coverage.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Introduce `testcontainers` harnesses for services with external deps (auth/content/user/messaging where applicable).
- FR-002: Replace `#[ignore]` with containerized fixtures or feature-gated setups.
- FR-003: Remove empty tests files (`posts_test.rs`, `comments_test.rs`, `stories_test.rs`) and any 100% placeholder code.
- FR-004: CI updates to allow Docker-in-Docker (or sibling container) for testcontainers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: Coverage >= 80% target for core services after re-enabling tests.
- SC-002: 0 tests remain `#[ignore]` due to missing infra.
