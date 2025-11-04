# Tasks: Outbox Event Consumer

**Input**: Design documents from `/specs/011-p1-outbox-consumer/`
**Prerequisites**: plan.md, spec.md, 006-p0-testcontainers completion

## Phase 1: Consumer Loop (2 days)

- [ ] T001 [P] Implement `OutboxConsumer::run()` main loop
- [ ] T002 [P] Read outbox WHERE processed_at IS NULL LIMIT 100
- [ ] T003 [P] Implement retry logic with exponential backoff (3 retries)
- [ ] T004 Update outbox row: processed_at = NOW() only after Kafka ACK

## Phase 2: Kafka + DLQ (1 day)

- [ ] T010 [P] Implement Kafka publish to `events` topic
- [ ] T011 Implement DLQ topic routing for failed messages
- [ ] T012 Graceful shutdown: drain in-flight events

## Phase 3: Tests (1 day)

- [ ] T020 Integration test: outbox → Kafka → consumed successfully
- [ ] T021 Test: transient failure → retry → success
- [ ] T022 Test: poison message → DLQ after 3 retries
- [ ] T023 Load test: 1000 events → all published

