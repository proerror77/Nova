# Implementation Plan: Core Feature Build-Out

**Branch**: `[009-p2-core-features]` | **Date**: 2025-11-04 | **Spec**: specs/009-p2-core-features/spec.md

## Steps (High-Level)

1) Auth-service: add register/login routes, JWT issuance, refresh
2) Content-service: add `CreateComment` RPC + persistence + validations
3) Shared: outbox table/migrations; consumer worker in respective service
4) Cross-cutting: circuit breaker middleware + fallbacks (Postgres/cache)
5) E2E tests across services

