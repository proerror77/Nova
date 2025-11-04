# Tasks: Auth Register/Login RPC Implementation

**Input**: Design documents from `/specs/009-p0-auth-register-login/`
**Prerequisites**: plan.md, spec.md, and 005-p1-input-validation completion

## Phase 1: RED — Write Failing Tests (TDD Discipline) (1 day)

Per Constitution Principle III: "Tests MUST be written before implementation code"

- [X] T001 [P] Create `backend/auth-service/tests/integration/auth_register_login_test.rs` with test module skeleton (use `tonic_testing` for gRPC)
- [X] T002 [P] Write failing test: `test_register_valid_email_password_returns_ok` → expects gRPC Status::Ok with token + user_id
- [X] T003 [P] Write failing test: `test_register_weak_password_returns_invalid_argument` → expects gRPC Status::InvalidArgument with message "weak_password"
- [X] T004 Write failing test: `test_register_invalid_email_returns_invalid_argument` → expects gRPC Status::InvalidArgument with message "invalid_email_format"
- [X] T005 Write failing test: `test_register_duplicate_email_returns_already_exists` → expects gRPC Status::AlreadyExists
- [X] T006 [P] Write failing test: `test_login_valid_credentials_returns_ok` → expects gRPC Status::Ok with token + expires_in
- [X] T007 [P] Write failing test: `test_login_wrong_password_5_times_locks_account` → expects gRPC Status::PermissionDenied + message "account_locked_until_<timestamp>"
- [X] T008 Write failing test: `test_login_locked_account_returns_permission_denied` → expects gRPC Status::PermissionDenied with lock expiry
- [X] T009 Write failing test: `test_login_after_lock_expires_succeeds` → expects gRPC Status::Ok
- [X] T010 [P] Write failing test: `test_refresh_with_valid_token_returns_ok` → expects gRPC Status::Ok with new token
- [X] T011 Write failing test: `test_refresh_with_expired_token_returns_unauthenticated` → expects gRPC Status::Unauthenticated
- [X] T012 Write failing test: `test_load_100_concurrent_register_login_calls_p95_under_200ms` → performance target with concurrent gRPC calls

## Phase 2: GREEN — Database Layer Implementation (1-2 days)

Implement minimal code to pass Phase 1 tests.

- [X] T020 [P] Verify users table schema in `backend/migrations/` or create migration `0XX_auth_users_tables.sql`
  - Schema: id (UUID), email (VARCHAR unique), username (VARCHAR), password_hash (VARCHAR), created_at, updated_at, is_active, failed_login_attempts INT DEFAULT 0, locked_until TIMESTAMPTZ NULL, deleted_at
- [X] T021 [P] Implement `UserDb::insert_user(email, username, password_hash) -> Result<User>` in `backend/auth-service/src/db/users.rs`
- [X] T022 [P] Implement `UserDb::get_user_by_email(email) -> Result<Option<User>>`
- [X] T023 Implement `UserDb::update_failed_login_attempts(user_id, count) -> Result<(count, is_locked, locked_until)>`
- [X] T024 Add refresh_tokens table migration if stateful refresh needed: (user_id, token_hash, expires_at, created_at)

## Phase 3: GREEN — JWT & gRPC Handlers Implementation (2-3 days)

Implement gRPC endpoint handlers and JWT logic.

- [X] T030 [P] Add `Register`, `Login`, `Refresh` RPC method definitions to `backend/protos/auth_service.proto`
  - Register(email: string, username: string, password: string) → RegisterResponse { token: string, user_id: string, expires_in: int32 }
  - Login(email: string, password: string) → LoginResponse { token: string, expires_in: int32 }
  - Refresh(refresh_token: string) → RefreshResponse { token: string, expires_in: int32, refresh_token?: string }

- [X] T031 [P] Create `backend/auth-service/src/jwt/claims.rs` with Claims struct (sub, email, username, iat, exp, iss)
- [X] T032 [P] Create `backend/auth-service/src/jwt/mod.rs` with `fn sign_token(claims) -> Result<String>` (RS256)
- [X] T033 [P] Implement `fn validate_token(token) -> Result<Claims>` with expiration check
- [X] T034 Generate or load RSA keypair for RS256 signing (env var `JWT_SIGNING_KEY` or auto-generate)

- [X] T035 [P] Implement gRPC handler: `async fn register(RegisterRequest) -> Result<RegisterResponse>` in `backend/auth-service/src/grpc/mod.rs`
  - Accept email, username, password
  - **DEPENDENCY**: Use validators from 005-p1-input-validation (email format validation + zxcvbn password strength checks already implemented in `backend/auth-service/src/security/password.rs` and DTOs)
  - Hash password with Argon2id
  - INSERT into users table
  - Return gRPC Status::AlreadyExists if email duplicate
  - Return gRPC Status::InvalidArgument if validation fails
  - Sign JWT + return RegisterResponse { token, user_id, expires_in: 3600 }

- [X] T036 [P] Implement gRPC handler: `async fn login(LoginRequest) -> Result<LoginResponse>` in `backend/auth-service/src/grpc/mod.rs`
  - Accept email, password
  - SELECT user by email; return Status::Unauthenticated if not found
  - Verify password hash with constant-time comparison
  - Check if account locked (locked_until > NOW); return Status::PermissionDenied with lock expiry message
  - If wrong password: increment failed_login_attempts + set lock if >= 5; return Status::Unauthenticated
  - On success: reset failed_login_attempts to 0
  - Sign JWT + return LoginResponse { token, expires_in: 3600 }

- [X] T037 Implement gRPC handler: `async fn refresh(RefreshRequest) -> Result<RefreshResponse>`
  - Accept refresh_token
  - Validate refresh token (check DB or embedded timestamp)
  - Return Status::Unauthenticated if invalid/expired
  - Issue new access token + optionally rotate refresh token
  - Return RefreshResponse { token, expires_in: 3600, refresh_token? }

- [X] T038 Map gRPC error codes per spec: InvalidArgument (weak_password), AlreadyExists (duplicate email), Unauthenticated (wrong password/expired token), PermissionDenied (account locked)

## Phase 4: HTTP REST Wrapper (Optional, 1-2 days)

REST API wrappers for web/mobile clients (deferred if not needed).

- [ ] T040 Evaluate need: Does architecture require HTTP REST endpoints for browser clients? (Defer if gRPC-gateway or web SDK sufficient)
- [ ] T041 If REST needed: Add HTTP routes in Actix-web wrapper layer
  - POST /auth/register → call gRPC Register internally
  - POST /auth/login → call gRPC Login internally
  - POST /auth/refresh → call gRPC Refresh internally
- [ ] T042 If REST needed: Implement HTTP error response mapping (gRPC Status → HTTP status codes)

## Phase 5: REFACTOR — Performance & Observability (1 day)

Add metrics and optimize for production.

- [ ] T050 [P] Add Prometheus metrics: register_requests_total, login_requests_total, login_failures_total, account_lockouts_total
- [ ] T051 [P] Add OpenTelemetry tracing to register/login handlers (per Constitution Principle VI)
- [ ] T052 Optimize JWT generation/validation latency (target < 50ms)
- [ ] T053 Add structured logging for security events (registration, login failure, account lockout)
- [ ] T054 Measure p50/p95/p99 latencies; verify p95 < 200ms (SC-002)

## Phase 6: Rate Limiter Integration (1 day)

- [ ] T060 Integrate 002 (Rate Limiter Atomic) spec if not already done
- [ ] T061 Verify failed login attempt count hooks into rate limiter
- [ ] T062 Test: brute force protection working end-to-end (link to Phase 1 tests)

## Phase 7: Documentation & Sign-off (1 day)

- [ ] T070 Update `backend/auth-service/README.md` with register/login examples
- [ ] T071 Document JWT key rotation strategy (how often, how to update)
- [ ] T072 Document Prometheus metrics and observability setup
- [ ] T073 Mark spec complete and verify all tests pass

