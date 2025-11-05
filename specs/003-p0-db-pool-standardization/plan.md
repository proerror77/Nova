# Implementation Plan: DB Pool Standardization (20–50, timeouts)

**Branch**: `[003-p0-db-pool-standardization]` | **Date**: 2025-11-04 | **Spec**: specs/003-p0-db-pool-standardization/spec.md

## Summary

Replace hardcoded `PgPoolOptions` in services with `libs/db-pool::create_pool`, align defaults and envs.

## Project Structure

```
specs/003-p0-db-pool-standardization/
├── plan.md
└── spec.md

backend/auth-service/src/main.rs                 # replace inline pool
backend/messaging-service/src/db.rs              # replace inline pool
backend/content-service/src/db/mod.rs            # verify uses config/timeouts
backend/user-service/src/db/mod.rs               # verify already OK
backend/video-service/src/main.rs                # verify config
backend/events-service/src/main.rs               # verify config
```

## Steps

1) Introduce `DbConfig::from_env()` usage in service mains
2) Replace `PgPoolOptions::new()...` calls with `libs/db-pool::create_pool`
3) Add log lines for pool sizes/timeouts on boot
4) Add smoke tests in CI to ensure env vars override defaults

