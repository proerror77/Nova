# Feature Specification: Outbox Event Consumer

**Feature Branch**: `[011-p1-outbox-consumer]`
**Created**: 2025-11-05
**Status**: Draft
**Priority**: P1 (Event reliability - prevents message loss)
**Input**: Decomposed from former 009-p2-core-features

## Quick Summary

Implement Outbox pattern consumer worker to publish PostgreSQL outbox table events to Kafka with exactly-once semantics, retries, and DLQ support.

## Verification (code audit) — 2025-11-05

- Outbox table exists: migrations/067_outbox_pattern_v2.sql
- Consumer NOT implemented: no worker loop exists
- Status: Infrastructure ready, business logic needed

## User Scenarios *(mandatory)*

### User Story 1 - Reliable event publishing (Priority: P1)

As an operator, events written to the outbox table are published to Kafka with zero loss, even on transient failures.

**Independent Test**: Simulate transient failures → events retried → succeed → no duplicates in topic.

**Acceptance Scenarios**:
1. Given event in outbox table, When consumer runs, Then event published to Kafka within 5 seconds.
2. Given transient failure, When retry succeeds, Then exactly-once delivery (no duplicates).
3. Given 3 retries fail, Then event moved to DLQ topic for investigation.

---

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Consumer worker reads outbox table WHERE processed_at IS NULL
- FR-002: Publish to Kafka with retry logic (exponential backoff)
- FR-003: Mark outbox row as processed (processed_at = NOW) only after Kafka ACK
- FR-004: DLQ topic for poison messages (>3 retries)
- FR-005: Graceful shutdown (drain in-flight events)

## Success Criteria *(mandatory)*

- SC-001: 100% of outbox events reach Kafka (no losses)
- SC-002: No duplicate events in topic (exactly-once)
- SC-003: p95 latency outbox→published < 5s
- SC-004: Poison messages route to DLQ after 3 retries

---

## Timeline Estimate

- ~4 days (depends on testcontainers 006 for Kafka integration tests)

