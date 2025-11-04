# Feature Specification: Auth Register/Login RPC Implementation

**Feature Branch**: `[009-p0-auth-register-login]`
**Created**: 2025-11-05
**Status**: Draft
**Priority**: P0 (Critical - User authentication is foundational)
**Input**: Decomposed from former 009-p2-core-features; elevated to P0 due to foundational importance

## Verification (code audit) — 2025-11-05

- HTTP routes stubbed in auth-service: `backend/auth-service/src/handlers/auth.rs:62-106,113-144` (register/login handlers exist)
- DTOs with validation present: `backend/auth-service/src/models/user.rs:33-55`
- Password security: Argon2id hashing + zxcvbn strength checks `backend/auth-service/src/security/password.rs:1-40`
- **Database persistence NOT WIRED**: handlers don't write to users table; need DB integration

**Action**:
- Wire HTTP handlers to actually INSERT/SELECT from users table
- Implement JWT issuance (register → token) and validation (login)
- Add refresh token rotation
- Complete database layer integration

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Register new account (Priority: P0)

As a user, I can create a new account via POST /auth/register with email + password.

**Why this priority**: Without registration, no user can log in or use the system.

**Independent Test**: POST /register with valid email/strong password → 200 + JWT token; invalid credentials → 400.

**Acceptance Scenarios**:
1. Given valid `email=user@example.com, password=MySecurePass2025!`, When POST /auth/register, Then response 200 with `{ token: "jwt...", user_id: "uuid" }`.
2. Given duplicate email, Then response 409 conflict.
3. Given weak password `password123`, Then 400 `weak_password`.
4. Given invalid email format `userexample.com`, Then 400 `invalid_email_format`.

---

### User Story 2 - Login and get JWT (Priority: P0)

As a user, I can log in with email + password to get a JWT access token.

**Independent Test**: POST /login with correct credentials → 200 + token; incorrect password → 401.

**Acceptance Scenarios**:
1. Given registered user with email/password, When POST /auth/login with correct creds, Then response 200 with `{ token: "jwt...", expires_in: 3600 }`.
2. Given 5+ failed login attempts, Then account locked for 15 minutes (rate limiting).
3. Given wrong password, Then 401 `invalid_credentials`.

---

### User Story 3 - JWT token refresh (Priority: P1, but implement with register/login)

As a client, I can refresh an expiring JWT using a refresh token without re-entering credentials.

**Acceptance Scenarios**:
1. Given valid refresh_token + JWT, When POST /auth/refresh, Then response 200 with new access token and refreshed refresh token.
2. Given expired refresh token, Then 401.

---

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Implement POST `/auth/register` endpoint → INSERT into users table; hash password with Argon2id; validate email/password (see 005 spec).
- FR-002: Implement POST `/auth/login` endpoint → SELECT from users WHERE email; compare password; issue JWT on success.
- FR-003: JWT encoding: `{ sub: user_id, email, username, iat, exp: +3600s, iss: "nova" }` signed with RS256.
- FR-004: Implement POST `/auth/refresh` endpoint with refresh_token rotation.
- FR-005: Rate limit login attempts: 5 failed → 15min account lock; clear on successful login.
- FR-006: Both HTTP REST and gRPC endpoints (or gRPC only if API protocol chosen).

### Key Entities

- users(id, email, username, password_hash, created_at, updated_at, is_active, failed_login_attempts, locked_until, deleted_at)
- tokens table OR in-app JWT store with refresh token tracking

### Database

- Ensure users table is writable from auth-service
- Add refresh_tokens table if stateful refresh supported
- Index on email for login lookups

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: `cargo test -p auth-service` passes all register/login/refresh tests (100%).
- SC-002: E2E: register → login → refresh succeeds in < 200ms p95 latency.
- SC-003: Account lockout verified: 5 failed logins trigger 15min lock.
- SC-004: Zero hardcoded credentials; all env/config driven.

---

## Rationale for P0 Elevation

**Previous Classification**: P2 (part of 009-p2-core-features)

**Why Now P0**:
- User authentication is **foundational** — all other features depend on knowing "who" the user is
- Cannot test content creation, messaging, feed without authenticated users
- Blocks validation of all downstream gRPC services
- Other P0 specs (001-005) assume users exist; this spec provides them

---

## Timeline Estimate

- ~5-7 days (dependent on 005 input validation being complete)
- Blocker for: 009-p1-B (CreateComment), 009-p1-C (Outbox), etc.

