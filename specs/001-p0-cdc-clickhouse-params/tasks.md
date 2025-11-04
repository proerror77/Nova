# Tasks: Secure CDC Inserts (ClickHouse Params)

**Input**: Design documents from `/specs/001-p0-cdc-clickhouse-params/`
**Prerequisites**: plan.md, spec.md

## Phase 1: Setup

- [ ] T001 [P] Add typed row structs in `backend/user-service/src/services/cdc/rows.rs` (new)
- [ ] T002 [P] Extend `backend/user-service/src/db/ch_client.rs` with `insert_rows<T: clickhouse::Row>(table, rows)` helper

## Phase 2: Replace INSERTs

- [ ] T010 Replace `insert_posts_cdc` with typed insert in `backend/user-service/src/services/cdc/consumer.rs`
- [ ] T011 Replace `insert_follows_cdc` with typed insert in `backend/user-service/src/services/cdc/consumer.rs`
- [ ] T012 Replace `insert_comments_cdc` with typed insert in `backend/user-service/src/services/cdc/consumer.rs`
- [ ] T013 Replace `insert_likes_cdc` with typed insert in `backend/user-service/src/services/cdc/consumer.rs`
- [ ] T014 Remove `escape_string` and its tests from `consumer.rs`

## Phase 3: Tests

- [ ] T020 [P] Add ClickHouse testcontainer setup in `backend/user-service/tests/integration/cdc_clickhouse_tests.rs`
- [ ] T021 [P] Adversarial string cases (quotes, backslashes, unicode, long strings)
- [ ] T022 Replay idempotency test (double-consume same CDC message)

## Phase 4: Validation

- [ ] T030 Grep check: no string concatenations for CDC INSERTs remain
- [ ] T031 Load-test locally (1k msgs/sec) and record p95 insert latency

