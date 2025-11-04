# Implementation Plan: Auth Register/Login RPC

**Branch**: `[009-p0-auth-register-login]` | **Date**: 2025-11-05 | **Spec**: specs/009-p0-auth-register-login/spec.md
**Priority**: P0 (Critical - foundational user authentication)
**Dependency**: 005-p1-input-validation (must be complete first)

## Summary

Complete HTTP/gRPC handlers for user registration and login with full persistence to PostgreSQL, JWT issuance, and account lockout for brute force protection.

## Project Structure

```
backend/auth-service/
├── src/
│   ├── handlers/auth.rs               # POST /register, /login, /refresh
│   ├── models/user.rs                 # DTOs + validation (already done)
│   ├── security/password.rs           # Argon2id + zxcvbn (already done)
│   ├── db/
│   │   ├── mod.rs                     # Pool + query helpers
│   │   └── users.rs                   # INSERT user, SELECT by email, UPDATE failed attempts
│   └── jwt/
│       ├── mod.rs                     # JWT encoding/decoding (RS256)
│       └── claims.rs                  # Token struct
├── tests/
│   ├── integration/
│   │   └── auth_register_login_test.rs # E2E register/login/refresh tests

database/
├── migrations/
│   └── 0XX_auth_users_tables.sql      # users + refresh_tokens tables if needed
```

## Technical Context

**Language/Version**: Rust 1.75+
**Framework**: Actix-web (HTTP) + Tonic (gRPC)
**Crypto**: Argon2id (password hashing), RS256 (JWT signing)
**Database**: PostgreSQL
**Dependencies**: `jsonwebtoken`, `uuid`, `chrono`, `sqlx`, `argon2`, `zxcvbn`
**Target**: Linux server
**Performance**: JWT generation/validation < 50ms; login/register < 200ms p95

## Constitution Check

- Security-first: passwords hashed before storage, account lockout prevents brute force
- No complexity increase: reuse existing validation + password modules
- Backward compat: gRPC endpoint addition doesn't break existing services

## Dependencies & Execution Order

1. **Prerequisite**: 005-p1-input-validation must be complete (email + password validation DTOs)
2. Phase 1: Wire database layer (users table CRUD)
3. Phase 2: Implement JWT signing/validation
4. Phase 3: HTTP /register, /login, /refresh endpoints
5. Phase 4: gRPC RPC equivalent (if required by architecture)
6. Phase 5: Integration tests + load validation
7. Phase 6: Rate limiter integration (account lockout)

## Acceptance Timeline

- **Phase 1** (DB layer): 1-2 days
- **Phase 2** (JWT): 1 day
- **Phase 3** (Handlers): 2 days
- **Phase 4** (gRPC): 1-2 days (if needed)
- **Phase 5** (Tests): 1-2 days
- **Total**: 5-7 days

## Parallel Work

Can run in parallel with:
- 001-004 (P0 security fixes) — these don't depend on users existing
- 006 (testcontainers) — tests will use this spec's register endpoint for setup
- 008 (feed ranking) — doesn't depend on auth

**Blocker For**:
- 009-P1-B (CreateComment) — needs authenticated user
- 009-P1-C (Outbox) — needs user context
- 009-P2-D (Circuit Breaker) — testing needs auth
