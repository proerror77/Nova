# Tasks: User Authentication Service

**Input**: Design from `/specs/002-user-auth/spec.md` and `/specs/002-user-auth/plan.md`
**Priority**: P0/P1/P2/P3 from spec | **Testing**: TDD Red-Green-Refactor required
**Coverage Goal**: 80% minimum from Constitution

---

## Phase 0: Project Setup (Blocking Prerequisites)

**Purpose**: Infrastructure that enables all user story work. MUST complete before stories begin.

- [ ] **AUTH-001** [P0] Setup Rust project structure and dependencies
  - *Goal*: Initialize Cargo workspace with web framework (Actix-web), database driver (sqlx), crypto libs
  - *Details*: Create `backend/user-service/` with Cargo.toml, add dependencies: actix-web, tokio, sqlx, bcrypt, jsonwebtoken, redis, serde
  - *Time*: 2h
  - *Files*: `backend/Cargo.toml`, `backend/user-service/Cargo.toml`, `backend/Dockerfile`

- [ ] **AUTH-002** [P0] Setup PostgreSQL database and migrations framework
  - *Goal*: Initialize database with sqlx migrations tool, create schema versioning
  - *Details*: Install sqlx-cli, create `migrations/` directory, setup connection pooling with PgBouncer config
  - *Time*: 2h
  - *Files*: `backend/migrations/001_initial_schema.sql`, `sqlx-data.json`

- [ ] **AUTH-003** [P0] Create PostgreSQL database schema
  - *Goal*: Implement all 5 core tables (users, oauth_connections, auth_tokens, password_reset_tokens, auth_logs)
  - *Details*: UUIDs as primary keys, proper indexes for email/username lookups, foreign key constraints, soft deletes for GDPR
  - *Time*: 3h
  - *Migration*: `migrations/001_initial_schema.sql`
  - *Spec Ref*: Key Entities section

- [ ] **AUTH-004** [P0] Setup Redis cache and connection
  - *Goal*: Connect to Redis for rate limiting, JWT blacklist, session management
  - *Details*: Add redis crate, create connection pool, sentinel configuration for HA
  - *Time*: 1.5h
  - *Files*: `backend/src/cache/mod.rs`, `backend/redis-sentinel.conf`

- [ ] **AUTH-005** [P0] Setup API routing and middleware structure
  - *Goal*: Create Actix-web route handlers, JWT middleware framework, error handling
  - *Details*: Implement `AuthMiddleware` trait, centralized error response format, request/response logging
  - *Time*: 2.5h
  - *Files*: `backend/src/handlers/mod.rs`, `backend/src/middleware/jwt.rs`, `backend/src/errors.rs`

- [ ] **AUTH-006** [P0] Setup CI/CD pipeline
  - *Goal*: GitHub Actions workflow for build, test, lint, Docker push
  - *Details*: cargo test, cargo clippy, rustfmt checks, Docker build, deploy to staging
  - *Time*: 2h
  - *Files*: `.github/workflows/ci.yml`, `backend/.dockerignore`

- [ ] **AUTH-0007** [P0] Setup email service (SendGrid/SES) + mock for local dev
  - *Goal*: Configure email provider client and credentials for production and local development
  - *Details*:
    - Production: SendGrid/SES API keys in secrets manager (AWS Secrets Manager / HashiCorp Vault)
    - Local dev: Mock email service that prints to stdout (for testing email generation)
    - Testing: testcontainers or similar for E2E email simulation
    - Environment variables: `EMAIL_PROVIDER`, `EMAIL_API_KEY`, `SENDER_EMAIL`
  - *Files*: `backend/src/services/email/mod.rs`, `backend/.env.example`, `.github/secrets-setup.md`
  - *Dependencies*: AUTH-001 (project structure)
  - *Time*: 1h
  - *Spec Ref*: Dependencies section (line 220)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 1: User Story 1 - Email Registration & Login (P1) 🎯 MVP

**Goal**: Core email authentication - users can register, verify, login, logout
**Independent Test**: Can complete full auth cycle: signup → email verify → login → logout

### Tests (Write FIRST - Red Phase)

- [ ] **AUTH-1001** [P1] Unit test: `UserModel::validate_email()`
  - *Goal*: Email validation (RFC 5322 format)
  - *Test File*: `backend/tests/unit/models/user_test.rs`
  - *Success*: Accepts valid emails, rejects invalid formats
  - *Time*: 1h

- [ ] **AUTH-1002** [P1] Unit test: `UserModel::hash_password()` and `verify_password()`
  - *Goal*: Bcrypt hashing (cost=12) and verification
  - *Test File*: `backend/tests/unit/security/password_test.rs`
  - *Success*: Bcrypt hashes correctly, verification works, never returns plaintext
  - *Time*: 1h

- [ ] **AUTH-1003** [P1] Integration test: `POST /auth/register` - happy path
  - *Goal*: Registration endpoint creates user, sends verification email
  - *Test File*: `backend/tests/integration/auth_register_test.rs`
  - *Success*: User created, email sent, returns 201 with user data
  - *Time*: 1.5h

- [ ] **AUTH-1004** [P1] Integration test: `POST /auth/verify-email` - email verification
  - *Goal*: Email verification token validation and activation
  - *Test File*: `backend/tests/integration/auth_verify_test.rs`
  - *Success*: Valid token activates account, invalid/expired tokens rejected
  - *Time*: 1.5h

- [ ] **AUTH-1005** [P1] Integration test: `POST /auth/login` - login flow
  - *Goal*: Login with correct credentials returns JWT tokens
  - *Test File*: `backend/tests/integration/auth_login_test.rs`
  - *Success*: Correct creds return access+refresh tokens, incorrect rejected
  - *Time*: 1.5h

- [ ] **AUTH-1006** [P1] Integration test: `POST /auth/logout` - revoke tokens
  - *Goal*: Logout revokes access token
  - *Test File*: `backend/tests/integration/auth_logout_test.rs`
  - *Success*: Token blacklisted, subsequent requests fail
  - *Time*: 1h

### Implementation (Green Phase)

- [ ] **AUTH-1010** [P1] Create User model and database repository
  - *Goal*: Define User struct, implement CRUD operations
  - *Details*: UUID, email, username, password_hash, status, timestamps
  - *Files*: `backend/src/models/user.rs`, `backend/src/repositories/user_repo.rs`
  - *Dependencies*: AUTH-003 (schema)
  - *Time*: 2h
  - *Spec Ref*: FR-001, Key Entities

- [ ] **AUTH-1011** [P1] Implement password hashing and validation
  - *Goal*: bcrypt integration (cost factor 12)
  - *Files*: `backend/src/security/password.rs`
  - *Dependencies*: AUTH-1002 (tests must pass)
  - *Time*: 1.5h
  - *Spec Ref*: FR-003

- [ ] **AUTH-1012** [P1] Implement email verification flow
  - *Goal*: Generate verification tokens (1-hour expiry), store in Redis
  - *Files*: `backend/src/services/email_verification.rs`
  - *Dependencies*: AUTH-004 (Redis)
  - *Time*: 2h
  - *Spec Ref*: FR-002, FR-014

- [ ] **AUTH-1013** [P1] Implement POST `/auth/register` endpoint
  - *Goal*: Handle user registration, validation, email sending
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-1010, AUTH-1011, AUTH-1012, AUTH-1003 (tests must pass)
  - *Time*: 2h
  - *Spec Ref*: FR-001, FR-002

- [ ] **AUTH-1014** [P1] Implement POST `/auth/verify-email` endpoint
  - *Goal*: Activate user account via email verification token
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-1012, AUTH-1004 (tests must pass)
  - *Time*: 1.5h
  - *Spec Ref*: FR-002

- [ ] **AUTH-1015** [P1] Implement JWT token generation and validation
  - *Goal*: Issue access (1h) and refresh (30d) tokens, RS256 signing
  - *Files*: `backend/src/security/jwt.rs`
  - *Time*: 2.5h
  - *Spec Ref*: FR-005

- [ ] **AUTH-1016** [P1] Implement POST `/auth/login` endpoint
  - *Goal*: Authenticate with email+password, return JWT tokens
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-1010, AUTH-1011, AUTH-1015, AUTH-1005 (tests must pass)
  - *Time*: 2h
  - *Spec Ref*: FR-005

- [ ] **AUTH-1017** [P1] Implement POST `/auth/logout` endpoint
  - *Goal*: Revoke access token by adding to Redis blacklist
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-004, AUTH-1006 (tests must pass)
  - *Time*: 1.5h
  - *Spec Ref*: FR-008

- [ ] **AUTH-1018** [P1] Implement rate limiting (5 attempts / 15 min)
  - *Goal*: Redis-based rate limiting for login attempts
  - *Files*: `backend/src/middleware/rate_limit.rs`
  - *Dependencies*: AUTH-004
  - *Time*: 1.5h
  - *Spec Ref*: FR-007

### Refactoring (Refactor Phase)

- [ ] **AUTH-1020** [P1] Code review and cleanup
  - *Goal*: Remove duplication, improve error handling consistency
  - *Time*: 1.5h
  - *Coverage Target*: 80%+ for auth module

**Checkpoint**: User Story 1 fully functional - users can register, verify, login, logout

---

## Phase 2: User Story 3 - Password Recovery (P1)

**Goal**: Users can reset forgotten passwords securely via email
**Independent Test**: Request reset → receive email → verify token → set new password

- [ ] **AUTH-2001** [P1] Integration test: `POST /auth/forgot-password` and reset flow
  - *Goal*: Password reset token generation and validation
  - *Test File*: `backend/tests/integration/auth_password_reset_test.rs`
  - *Time*: 2h

- [ ] **AUTH-2010** [P1] Implement PasswordResetToken model and repository
  - *Goal*: Time-limited reset tokens with hash storage
  - *Files*: `backend/src/models/password_reset_token.rs`
  - *Dependencies*: AUTH-003 (schema)
  - *Time*: 1h

- [ ] **AUTH-2011** [P1] Implement POST `/auth/forgot-password` endpoint
  - *Goal*: Generate reset token, send via email
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-2010, AUTH-2001 (tests must pass)
  - *Time*: 1.5h
  - *Spec Ref*: FR-006

- [ ] **AUTH-2012** [P1] Implement POST `/auth/reset-password` endpoint
  - *Goal*: Validate reset token, update password
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-1011 (password hashing), AUTH-2010
  - *Time*: 1.5h
  - *Spec Ref*: FR-006, FR-015 (prevent reuse)

**Checkpoint**: Password recovery fully functional - users can reset forgotten passwords

---

## Phase 3: User Story 2 - OAuth2 Social Login (P2)

**Goal**: Users can login/signup with Apple, Google, Facebook

- [ ] **AUTH-3001** [P2] Integration tests: OAuth flows (Apple, Google, Facebook)
  - *Goal*: End-to-end OAuth authorization code flow
  - *Test File*: `backend/tests/integration/oauth_test.rs`
  - *Time*: 3h

- [ ] **AUTH-3010** [P2] Create OAuthConnection model and repository
  - *Goal*: Link OAuth providers to users
  - *Files*: `backend/src/models/oauth_connection.rs`
  - *Dependencies*: AUTH-003 (schema)
  - *Time*: 1h

- [ ] **AUTH-3011** [P2] Implement OAuth provider abstraction trait
  - *Goal*: Unified trait for Apple/Google/Facebook
  - *Files*: `backend/src/services/oauth/mod.rs`, `backend/src/services/oauth/providers/`
  - *Time*: 2h
  - *Spec Ref*: FR-004

- [ ] **AUTH-3012** [P2] Implement Apple Sign In provider
  - *Goal*: OAuth2 authorization code flow for Apple
  - *Files*: `backend/src/services/oauth/providers/apple.rs`
  - *Dependencies*: AUTH-3011, AUTH-3001 (tests must pass)
  - *Time*: 2.5h
  - *Spec Ref*: FR-004

- [ ] **AUTH-3013** [P2] Implement Google OAuth provider
  - *Goal*: OAuth2 authorization code flow for Google
  - *Files*: `backend/src/services/oauth/providers/google.rs`
  - *Dependencies*: AUTH-3011
  - *Time*: 2h

- [ ] **AUTH-3014** [P2] Implement Facebook OAuth provider
  - *Goal*: OAuth2 authorization code flow for Facebook
  - *Files*: `backend/src/services/oauth/providers/facebook.rs`
  - *Dependencies*: AUTH-3011
  - *Time*: 2h

- [ ] **AUTH-3015** [P2] Implement POST `/auth/oauth/authorize` callback endpoint
  - *Goal*: Handle OAuth provider redirects, create/link user
  - *Files*: `backend/src/handlers/oauth.rs`
  - *Dependencies*: AUTH-3010, AUTH-3011, AUTH-3001 (tests must pass)
  - *Time*: 2h
  - *Spec Ref*: FR-004, FR-009

- [ ] **AUTH-3016** [P2] Implement account linking for OAuth
  - *Goal*: Allow existing email users to link social accounts
  - *Files*: `backend/src/handlers/oauth.rs`
  - *Dependencies*: AUTH-3015
  - *Time*: 1.5h
  - *Spec Ref*: FR-009

**Checkpoint**: OAuth login fully functional - users can signup/login with social providers

---

## Phase 4: User Story 4 - Two-Factor Authentication (P3)

**Goal**: Users can enable TOTP-based 2FA for enhanced security

- [ ] **AUTH-4001** [P3] Integration tests: 2FA setup and verification flow
  - *Goal*: QR code generation, TOTP validation, backup codes
  - *Test File*: `backend/tests/integration/auth_2fa_test.rs`
  - *Time*: 2h

- [ ] **AUTH-4010** [P3] Implement TOTP generation and verification
  - *Goal*: Generate shared secrets, validate 6-digit codes
  - *Files*: `backend/src/security/totp.rs`
  - *Time*: 1.5h
  - *Spec Ref*: FR-011

- [ ] **AUTH-4011** [P3] Implement POST `/auth/2fa/enable` endpoint
  - *Goal*: Generate QR code, store secret, enable 2FA flag
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-4010
  - *Time*: 1.5h
  - *Spec Ref*: FR-011

- [ ] **AUTH-4012** [P3] Implement 2FA verification in login flow
  - *Goal*: After password validation, require 2FA code if enabled
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-1016 (login), AUTH-4010
  - *Time*: 1.5h
  - *Spec Ref*: FR-011

- [ ] **AUTH-4013** [P3] Generate and manage backup codes
  - *Goal*: Provide recovery codes for account lockout
  - *Files*: `backend/src/security/backup_codes.rs`
  - *Time*: 1h
  - *Spec Ref*: FR-011

**Checkpoint**: 2FA fully functional - users can secure accounts with TOTP

---

## Phase 5: Security, Logging, and Hardening (P1)

**Goal**: Production-ready security, audit logging, monitoring

- [ ] **AUTH-5001** [P1] Implement authentication event logging
  - *Goal*: Log all auth events (login, logout, failed attempts, password reset)
  - *Files*: `backend/src/models/auth_log.rs`, `backend/src/services/auth_logger.rs`
  - *Dependencies*: AUTH-003 (auth_logs table)
  - *Time*: 2h
  - *Spec Ref*: FR-013

- [ ] **AUTH-5002** [P1] Implement CSRF protection for OAuth
  - *Goal*: State parameter validation for OAuth flows
  - *Files*: `backend/src/middleware/csrf.rs`
  - *Time*: 1h
  - *Spec Ref*: Plan section 7 (Security)

- [ ] **AUTH-5003** [P1] Setup Prometheus metrics for monitoring
  - *Goal*: Track auth metrics (login success rate, avg latency, rate limit hits)
  - *Files*: `backend/src/metrics/mod.rs`
  - *Time*: 1.5h

- [ ] **AUTH-5004** [P1] Implement TLS/SSL configuration
  - *Goal*: Force HTTPS, TLS 1.3 minimum
  - *Files*: `backend/docker-compose.yml`, `backend/nginx.conf`
  - *Time*: 1h
  - *Spec Ref*: Constitution - Security principle

- [ ] **AUTH-5005** [P1] Input validation across all endpoints
  - *Goal*: Sanitize email, password, username inputs, prevent injection
  - *Files*: `backend/src/validators/mod.rs`
  - *Time*: 1.5h

- [ ] **AUTH-5006** [P1] Implement account deletion (GDPR compliance)
  - *Goal*: Soft delete, cascade to oauth_connections, maintain audit trail
  - *Files*: `backend/src/handlers/auth.rs`
  - *Dependencies*: AUTH-5001 (logging)
  - *Time*: 1.5h
  - *Spec Ref*: FR-012

- [ ] **AUTH-5007** [P1] Implement JWT key rotation + JWKS endpoint
  - *Goal*: Enable secure key rotation for RS256-signed JWT tokens without user disruption
  - *Details*:
    - Monthly automated key rotation (configurable interval)
    - Keep 2 key versions live during rotation window (previous + current)
    - Publish active keys at `/.well-known/jwks.json` endpoint (JWKS - JSON Web Key Set)
    - Clients cache and refresh JWKS on unknown `kid` (Key ID)
    - Old keys retained in database for token validation during grace period
    - Rotation SOP documented in README
  - *Files*: `backend/src/security/jwt.rs` (enhanced), `backend/src/handlers/jwks.rs`, `backend/migrations/add_key_rotation.sql`
  - *Dependencies*: AUTH-1015 (JWT implementation complete)
  - *Time*: 1.5h
  - *Spec Ref*: Security principle IV (Constitution), plan.md Section 5 (JWT Token Flow)

**Checkpoint**: Security hardened - production-ready for deployment

---

## Phase 6: Testing Coverage and Documentation (P0)

**Goal**: 80%+ coverage, complete documentation

- [ ] **AUTH-6001** [P0] Add security-specific tests
  - *Goal*: SQL injection, password brute force, JWT tampering tests
  - *Test File*: `backend/tests/security/security_test.rs`
  - *Time*: 2h

- [ ] **AUTH-6002** [P0] Load testing - concurrent logins
  - *Goal*: Verify 1000 concurrent logins without degradation (SC-010)
  - *Test File*: `backend/tests/performance/load_test.rs`
  - *Time*: 1.5h

- [ ] **AUTH-6003** [P0] Generate API documentation (OpenAPI 3.0)
  - *Goal*: Swagger/OpenAPI spec for all endpoints
  - *Files*: `backend/docs/openapi.yaml`
  - *Time*: 1.5h

- [ ] **AUTH-6004** [P0] Verify 80% coverage threshold
  - *Goal*: Run coverage report, identify gaps
  - *Time*: 1h

---

## Task Dependencies & Parallel Opportunities

### Blocking Dependencies (Must Complete in Order)
```
Phase 0 (Setup)
  ↓
Phase 1 (Email Auth) 🚀 Core MVP
  ├─ Phase 2 (Password Reset) [Can start after Phase 1 models]
  ├─ Phase 3 (OAuth) [Can start after Phase 1 models]
  └─ Phase 4 (2FA) [Can start after Phase 1 models]
  ↓
Phase 5 (Security & Hardening)
  ↓
Phase 6 (Testing & Documentation)
```

### Parallel Opportunities
- **Phase 1**: Tasks AUTH-1010/1011/1012 can run in parallel [P]
- **Phase 2**: Can start immediately after Phase 1 models done
- **Phase 3**: OAuth providers (AUTH-3012/3013/3014) can run in parallel [P]
- **Phase 4**: 2FA tasks can run in parallel with Phase 3

---

## Estimated Timeline

| Phase | Tasks | Duration | Notes |
|-------|-------|----------|-------|
| Phase 0 (Setup) | AUTH-001 to 007 | 13.5h | Blocking all others (**+1h for email service**) |
| Phase 1 (Email Auth) | AUTH-1001 to 1020 | 28h | MVP core - write tests first |
| Phase 2 (Password Reset) | AUTH-2001 to 2012 | 7.5h | Sequential after Phase 1 |
| Phase 3 (OAuth) | AUTH-3001 to 3016 | 16.5h | Can run in parallel with Phase 2 |
| Phase 4 (2FA) | AUTH-4001 to 4013 | 8.5h | Can run in parallel with Phase 3 |
| Phase 5 (Security) | AUTH-5001 to 5007 | 10h | After core features done (**+1.5h for JWT key rotation**) |
| Phase 6 (Testing) | AUTH-6001 to 6004 | 6h | Final verification |
| **TOTAL** | **35 tasks** | **~89.5 hours** | ~2.5 weeks for 1 developer, ~1 week for team of 3 |

---

## Implementation Strategy

### MVP First (User Story 1 + 3 - Production Ready)
1. Complete Phase 0 (13.5h) - **includes email service + JWT key setup**
2. Complete Phase 1 (28h)
3. Complete Phase 2 (7.5h)
4. Deploy and validate
5. **STOP and SHIP** (49h total = ~1 week, with email + key rotation production-ready)

### Full Feature Set
1-6: Complete all phases (89.5h total = ~2.5 weeks single developer)

### Team Strategy (3 developers)
- **Developer A**: Phase 0 + Phase 1 (Email Auth) - 41.5h
- **Developer B**: Phase 2 (Password Reset) + Phase 4 (2FA) - 16h
- **Developer C**: Phase 3 (OAuth) + Phase 5 (Security) - 26.5h
- **All**: Phase 6 (Testing/Docs) - 6h
- **Total**: ~1 week wall clock time
