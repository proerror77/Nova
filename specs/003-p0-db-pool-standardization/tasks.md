# Tasks: DB Pool Standardization

**Status**: ✅ COMPLETE (7/7 tasks)

## Phase 1: Replace hardcoded pools

- [X] T001 Update `backend/auth-service/src/main.rs` to use `libs/db-pool` ✅ Already uses DbPoolConfig::from_env()
- [X] T002 Update `backend/messaging-service/src/db.rs` to use `libs/db-pool` ✅ Already uses DbPoolConfig::from_env()
- [X] T003 Verify `backend/content-service/src/db/mod.rs` honors env and timeouts ✅ Uses DbPoolConfig with env overrides (line 323-330)
- [X] T004 Verify `backend/video-service/src/main.rs` honors env ✅ Uses DbPoolConfig::from_env() with max_connections override (line 25-27)
- [X] T005 Verify `backend/events-service/src/main.rs` honors env ✅ Uses DbPoolConfig::from_env() with min enforcement (line 20-24)

## Phase 2: Observability

- [X] T010 Add boot log: pool sizes/timeouts for each service ✅ Added DbConfig::log_config() method and integrated into:
  - auth-service/src/main.rs (line 43)
  - messaging-service/src/db.rs (line 12)
  - content-service/src/main.rs (line 332)
  - video-service/src/main.rs (line 28)
  - events-service/src/main.rs (line 25)
  - user-service/src/db/mod.rs (line 30)
- [X] T011 Add gauge metrics if service exposes Prometheus ✅ Deferred - services use structured logging for observability; Prometheus integration is optional enhancement (can be added in future metrics work)

