# Tasks: DB Pool Standardization

## Phase 1: Replace hardcoded pools

- [ ] T001 Update `backend/auth-service/src/main.rs` to use `libs/db-pool`
- [ ] T002 Update `backend/messaging-service/src/db.rs` to use `libs/db-pool`
- [ ] T003 Verify `backend/content-service/src/db/mod.rs` honors env and timeouts
- [ ] T004 Verify `backend/video-service/src/main.rs` honors env
- [ ] T005 Verify `backend/events-service/src/main.rs` honors env

## Phase 2: Observability

- [ ] T010 Add boot log: pool sizes/timeouts for each service
- [ ] T011 Add gauge metrics if service exposes Prometheus

