# Feature Specification: Core Feature Build-Out (DEPRECATED - See Below)

⚠️ **STATUS**: DEPRECATED - Decomposed into 4 independent specs for clarity

**Original Branch**: `[009-p2-core-features]`
**Created**: 2025-11-04
**Superseded By**: See decomposition below
**Input**: User description: "Implement Auth Register/Login, CreateComment, Outbox consumer, Circuit Breaker"

---

## ⚠️ DECOMPOSITION NOTICE

This spec has been reorganized into 4 independent, prioritized specs per Linus Torvalds' "one spec, one problem" principle:

| # | Feature | Priority | Location |
|---|---------|----------|----------|
| **009-A** | **Auth Register/Login** | **P0** (elevated!) | `specs/009-p0-auth-register-login/` |
| **010-B** | **CreateComment RPC** | **P1** | `specs/010-p1-comment-rpc/` |
| **011-C** | **Outbox Consumer** | **P1** | `specs/011-p1-outbox-consumer/` |
| **012-D** | **Circuit Breaker** | **P2** | `specs/012-p2-circuit-breaker/` |

**All new specs follow spec-kit CLI convention with spec.md, plan.md, and tasks.md.**

---

## Archive: Original Content Below

## Verification (code audit) — 2025-11-05

- Auth register/login: HTTP routes stubbed in auth-service with validation and token generation; persistence not wired yet.
  - References: `backend/auth-service/src/handlers/auth.rs:62-106,113-144` (register/login handlers), DTO validations present.
- CreateComment: No implemented RPC in content-service yet; only read/list paths exist.
- Outbox consumer: Outbox pattern migrations present (`083_outbox_pattern_v2.sql`), consumer worker not implemented.
- Circuit breaker: Implemented and used in user-service and content-service for downstreams; verify per-service coverage.

Action:
- Fill DB persistence for auth register/login; implement content-service `CreateComment` RPC; build out outbox consumer worker; expand breaker usage to all critical external calls.

## User Scenarios & Testing *(mandatory)*

### User Story A - Register/Login (Priority: P1)

As a user, I can create an account and login via auth-service (Argon2id, JWTs). Email validated; passwords strength checked pre-hash.

**Independent Test**: Register + login e2e passes; refresh tokens rotate; invalid creds return 401.

### User Story B - CreateComment (Priority: P2)

As a user, I can add a comment to a post; content validated; comment appears in content-service and feed invalidation occurs.

**Independent Test**: POST comment → row in DB; gRPC to feed invalidation fires; fetching comments returns new item.

### User Story C - Outbox Consumer (Priority: P2)

As an operator, events written to DB outbox are consumed and published; retries with backoff; DLQ for poison messages.

**Independent Test**: Simulate transient failures; messages retried then succeed; poison routed to DLQ.

### User Story D - Circuit Breaker (Priority: P2)

As a platform, cross-service calls degrade gracefully to PostgreSQL or cached responses when dependencies fail.

**Independent Test**: Dependency down → breaker opens → fallback path returns 200 with degraded data; metrics emitted.

## Requirements *(mandatory)*

### Functional Requirements

- FR-A: Auth register/login endpoints (REST/gRPC), JWT issuance/validation, refresh flow, email+password validation (see 005 spec).
- FR-B: Content-service `CreateComment` RPC + persistence + validation; audit/logging; rate limit per user.
- FR-C: Outbox table + consumer worker with exactly-once semantics; retries; DLQ.
- FR-D: Circuit breaker middleware (e.g., `tower`/custom) with metrics and fallback strategies.

## Success Criteria *(mandatory)*

- SC: E2E path for each story green; failure injection tests show resilience.
