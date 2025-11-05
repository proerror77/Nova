# Tasks: Request Input Validation

**Status**: ✅ COMPLETE (5/5 tasks)

- [X] T001 Add `validator` and `zxcvbn` dependencies to `backend/auth-service/Cargo.toml` ✅
  - Dependencies already present in Cargo.toml (lines 65-67)
  - validator 0.18 with derive feature
  - zxcvbn 2

- [X] T002 Create DTOs in `backend/auth-service/src/dto/` with derives ✅
  - RegisterRequest and LoginRequest defined in `backend/auth-service/src/models/user.rs:57-76`
  - Both use `#[derive(Validate)]` with `#[validate(email)]` for email field
  - Username validated with custom validator for shape (alphanumeric, 3-32 chars)
  - Password validated for length (8-128 chars)

- [X] T003 Update register/login handlers to call `.validate()` and `zxcvbn` ✅
  - Register handler in `backend/auth-service/src/handlers/auth.rs:70-96` calls `.validate()`
  - Password strength validated with zxcvbn before hashing in `backend/auth-service/src/security/password.rs:42-65`
  - Argon2id hashing only proceeds after strength check passes

- [X] T004 Add unit tests for DTOs in `backend/auth-service/tests/` ✅
  - `validators_unit_tests.rs`: Tests for email, username, and password validation functions
  - `dto_validation_tests.rs`: Tests for RegisterRequest and LoginRequest DTO validation

- [X] T005 Add integration tests hitting HTTP endpoints ✅
  - `http_validation_tests.rs`: Integration tests for HTTP validation endpoints
  - `auth_register_login_test.rs`: Register and login flow tests

**Key Achievements**:
- All validation requirements met
- zxcvbn password strength scoring (score >= 3)
- DTO validation with validator crate derives
- Comprehensive unit and integration test coverage
- No behavioral changes - pure input validation improvements

