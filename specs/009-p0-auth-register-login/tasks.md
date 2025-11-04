# Tasks: Auth Register/Login RPC Implementation

**Input**: Design documents from `/specs/009-p0-auth-register-login/`
**Prerequisites**: plan.md, spec.md, and 005-p1-input-validation completion

## Phase 1: Database Layer (1-2 days)

- [ ] T001 [P] Verify users table schema in `backend/migrations/` or create if missing
- [ ] T002 [P] Add `failed_login_attempts INT DEFAULT 0` and `locked_until TIMESTAMPTZ NULL` to users table if not present
- [ ] T003 Add refresh_tokens table with (user_id, token_hash, expires_at, created_at) if stateful refresh needed
- [ ] T004 [P] Implement `UserDb::insert_user(email, username, password_hash) -> Result<User>` in `backend/auth-service/src/db/users.rs`
- [ ] T005 [P] Implement `UserDb::get_user_by_email(email) -> Result<Option<User>>`
- [ ] T006 Implement `UserDb::update_failed_login_attempts(user_id, count) -> Result<(count, is_locked, locked_until)>`

## Phase 2: JWT Signing/Validation (1 day)

- [ ] T010 [P] Create `backend/auth-service/src/jwt/claims.rs` with Claims struct (sub, email, username, iat, exp, iss)
- [ ] T011 [P] Create `backend/auth-service/src/jwt/mod.rs` with `fn sign_token(claims) -> Result<String>` (RS256)
- [ ] T012 [P] Implement `fn validate_token(token) -> Result<Claims>`
- [ ] T013 Generate or load RSA keypair for RS256 signing (env var `JWT_SIGNING_KEY`)

## Phase 3: HTTP Endpoints (2 days)

- [ ] T020 [P] Implement POST `/auth/register` handler in `backend/auth-service/src/handlers/auth.rs`
  - Accept RegisterRequest { email, username, password }
  - Call 005 validation (email format, password strength)
  - Hash password with Argon2id
  - INSERT into users table
  - Sign JWT + return RegisterResponse { token, user_id, expires_in }

- [ ] T021 [P] Implement POST `/auth/login` handler in `backend/auth-service/src/handlers/auth.rs`
  - Accept LoginRequest { email, password }
  - SELECT user by email
  - Verify password hash
  - Check if account locked (locked_until > NOW)
  - If wrong password: increment failed_login_attempts + set lock if >= 5
  - On success: reset failed_login_attempts to 0
  - Sign JWT + return LoginResponse { token, expires_in }

- [ ] T022 Implement POST `/auth/refresh` handler
  - Accept refresh token
  - Validate refresh token (check DB or embedded timestamp)
  - Issue new access token + optionally rotate refresh token

- [ ] T023 Add error responses: 400 invalid_email, 400 weak_password, 409 email_exists, 401 invalid_credentials, 429 account_locked

## Phase 4: gRPC Endpoints (1-2 days) [Optional if REST only]

- [ ] T030 Add `Register`, `Login`, `Refresh` RPC methods to `backend/protos/auth_service.proto`
- [ ] T031 Implement gRPC equivalents in `backend/auth-service/src/grpc/mod.rs`
  - Map to same business logic as HTTP handlers (DRY principle)

## Phase 5: Integration Tests (1-2 days)

- [ ] T040 [P] Create `backend/auth-service/tests/integration/auth_register_login_test.rs`
- [ ] T041 [P] Test: Register with valid email/password → 200 + token
- [ ] T042 Test: Register with weak password → 400 weak_password
- [ ] T043 Test: Register with invalid email → 400 invalid_email_format
- [ ] T044 Test: Register with duplicate email → 409 conflict
- [ ] T045 [P] Test: Login with correct credentials → 200 + token
- [ ] T046 [P] Test: Login with wrong password 5 times → 429 + account locked
- [ ] T047 Test: Login on locked account → 429 wait 15min
- [ ] T048 Test: Successful login after 15min lock expires → 200
- [ ] T049 Test: JWT expires → refresh with valid refresh_token → 200 new token
- [ ] T050 Test: Refresh with expired refresh_token → 401
- [ ] T051 Load test: 100 concurrent register/login requests → p95 < 200ms, 0 errors

## Phase 6: Rate Limiter Integration (1 day)

- [ ] T060 Integrate 002 (Rate Limiter Atomic) spec if not already done
- [ ] T061 Verify failed login attempt count hooks into rate limiter
- [ ] T062 Test: brute force protection working end-to-end

## Phase 7: Documentation & Sign-off

- [ ] T070 Update `backend/auth-service/README.md` with register/login examples
- [ ] T071 Document JWT key rotation strategy (how often, how to update)
- [ ] T072 Mark spec complete in spec-kit CLI

