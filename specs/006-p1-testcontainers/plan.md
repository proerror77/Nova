# Implementation Plan: CI-Ready Tests via Testcontainers

**Branch**: `[006-p0-testcontainers]` | **Date**: 2025-11-04 | **Spec**: specs/006-p0-testcontainers/spec.md
**Priority**: P0 (Critical - blocks CI/CD pipeline, test coverage at 35% vs 80% target)

## Summary

Replace `#[ignore]` integration tests with testcontainers-based fixtures. Remove empty placeholder tests. Update CI to allow containers. This is a **P0 blocker** because:
- Currently 0 integration tests run in CI (all marked #[ignore])
- Test coverage stuck at 35-45% vs 80% target
- Unable to validate code changes before production deployment
- All 6 P0/P1 security fixes in other specs depend on having working CI tests

## Steps

1) Add a reusable test harness crate/module to start Postgres/Redis/Kafka.
2) Migrate content-service gRPC tests to use harness; remove `#[ignore]`.
3) Update auth-service and user-service tests that require Redis/DB.
4) Prune empty test files.
5) Update CI workflow to enable Docker (if not already).

