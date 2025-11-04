# Feature Specification: DB Pool Standardization (20–50, timeouts)

**Feature Branch**: `[003-p0-db-pool-standardization]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Increase pool sizes, add timeouts/idle/lifetime, make configurable"

## Verification (code audit) — 2025-11-05

- Shared lib present: `backend/libs/db-pool` with sane defaults (max=20, min=5, connect=30s, idle=600s, lifetime=1800s) and env overrides.
  - Reference: `backend/libs/db-pool/src/lib.rs:12-44`, `backend/libs/db-pool/src/lib.rs:72-89`.
- user-service: uses a local `create_pool` with timeouts set; default max from config is 10 (env `DATABASE_MAX_CONNECTIONS`).
  - References: `backend/user-service/src/db/mod.rs:23-31`, `backend/user-service/src/config/mod.rs:170`, `backend/user-service/src/main.rs:106-114`.
- content-service: in `main.rs` constructs pool with only `.max_connections(...)` and no acquire/idle/lifetime settings.
  - Reference: `backend/content-service/src/main.rs:324-333`. Default max is 10 in `content-service` config.
- Other services (cdn/events/video/search) already import `libs/db-pool`.

Action:
- Adopt `libs/db-pool` in user-service and content-service; set default max to >=20 and expose idle/lifetime/connect timeouts via env.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Configurable sane defaults (Priority: P1)

As an operator, I want consistent pool settings across services (max 20–50, min 5–10, acquire/idle/lifetime timeouts) via env/config.

**Independent Test**: Boot each service with no env overrides; verify pool sizes/timeouts via logs/metrics match defaults.

**Acceptance Scenarios**:
1. Given auth-service default pool=20, When under load, Then no pool exhaustion occurs at 100 rps.
2. Given messaging-service previously hardcoded 5, When standardized, Then pooled connections respect env vars.

### User Story 2 - Unified creation API (Priority: P2)

As a developer, I want all services to use `libs/db-pool` so settings are centralized and auditable.

**Independent Test**: Code grep reveals no direct scattered `PgPoolOptions::new().max_connections(5)` in service mains.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Adopt `backend/libs/db-pool` in all services that still set pool options inline.
- FR-002: Ensure config envs `DB_MAX_CONNECTIONS`, `DB_MIN_CONNECTIONS`, `DB_CONNECT_TIMEOUT_SECS`, `DB_IDLE_TIMEOUT_SECS`, `DB_MAX_LIFETIME_SECS` are honored.
- FR-003: Add simple pool metrics (in-flight, waits) exposed via logs/metrics where available.

### Key Entities

- `DbConfig` (libs/db-pool) → `PgPool`

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: No hardcoded `max_connections(5)` remains in code (grep check passes).
- SC-002: Load test shows no pool exhaustion in auth/content/messaging under 200 rps each.
- SC-003: Configured timeouts observed in logs (connect/acquire/idle/lifetime).
