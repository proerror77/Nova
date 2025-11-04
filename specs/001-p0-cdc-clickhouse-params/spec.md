# Feature Specification: Secure CDC Inserts (ClickHouse Params)

**Feature Branch**: `[001-p0-cdc-clickhouse-params]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Fix SQL injection in CDC consumer by using parameterized queries"

## Verification (code audit) — 2025-11-05

- CDC path uses typed inserts already: `backend/user-service/src/services/cdc/consumer.rs` calls `ch_client.insert_row(...)` with `clickhouse::Row` structs (safe).
  - Example references: `backend/user-service/src/services/cdc/consumer.rs:236`, `backend/user-service/src/services/cdc/consumer.rs:290`, `backend/user-service/src/services/cdc/consumer.rs:332` (posts/comments/likes insert functions).
- The active SQL injection risk is in the Events consumer batch insert, not CDC:
  - Vulnerable string formatting and ad‑hoc escaping:
    - `backend/user-service/src/services/events/consumer.rs:300-324` builds `INSERT` via `format!(...)` + `escape_string` and executes with `self.ch_client.execute(&query)`.
    - `backend/user-service/src/services/events/consumer.rs:335-342` defines `escape_string`.
- Scope adjustment: keep CDC as-is (typed) and move mitigation to Events consumer by switching to `insert_rows`/typed parameters.

Action:
- Update FR-001 below to target Events consumer path; add explicit success checks for both CDC and Events.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Injection-safe CDC writes (Priority: P1)

As a security engineer, I need CDC writes to ClickHouse to be performed via parameterized/typed inserts so untrusted strings (e.g., content with quotes/newlines) cannot alter SQL.

**Why this priority**: Current string-concatenated SQL in `consumer.rs` can be exploited; this is a P0 vulnerability.

**Independent Test**: Craft payloads with quotes, backslashes, unicode, and long strings; verify no query text contains interpolated literals and rows are correctly inserted.

**Acceptance Scenarios**:
1. Given content `O'Hara \ backslash`, When CDC writes to `posts_cdc`, Then the row is inserted and no SQL error occurs and query text shows bound values (not concatenated).
2. Given malicious content `'); DROP TABLE posts_cdc; --`, When inserted, Then table remains intact and row is stored verbatim.

---

### User Story 2 - Idempotent typed upserts (Priority: P2)

As an operator, I want all CDC tables (posts/follows/comments/likes) written through typed rows using `clickhouse::Client.insert()` so ReplacingMergeTree upserts remain consistent across message replays.

**Why this priority**: Aligns semantics across tables, reduces drift and bugs.

**Independent Test**: Reprocess the same CDC message twice; expect a single logical row (by primary key) after merges.

**Acceptance Scenarios**:
1. Given duplicate CDC messages for a post, When processed twice, Then ClickHouse shows a single final state.

### Edge Cases

- Null `media_url` must be written as NULL (not the string "NULL").
- Delete events set `is_deleted = 1` and still write a consistent row.
- Timestamps parsed with `parseDateTimeBestEffort` but passed as parameters, not inline strings.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Replace string-formatted INSERTs in `backend/user-service/src/services/events/consumer.rs` with parameterized/typed inserts (use `insert_rows` and row structs).
- FR-002: Introduce row structs (derive `clickhouse::Row, Serialize`) for `posts_cdc`, `follows_cdc`, `comments_cdc`, `likes_cdc`.
- FR-003: Add an insertion helper to `backend/user-service/src/db/ch_client.rs` to perform typed batch inserts.
- FR-004: Remove the manual `escape_string` path from CDC code.
- FR-005: Add unit tests that serialize rows with edge-case strings and ensure execution succeeds against a ClickHouse testcontainer.

### Key Entities *(include if feature involves data)*

- posts_cdc(id, user_id, content, media_url?, created_at, cdc_timestamp, is_deleted)
- follows_cdc(follower, followee, created_at, cdc_timestamp, is_deleted)
- comments_cdc(id, post_id, user_id, content, created_at, cdc_timestamp, is_deleted)
- likes_cdc(user_id, post_id, created_at, cdc_timestamp, is_deleted)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: 0 instances of string interpolation in CDC INSERT paths (grep check passes).
- SC-002: CDC e2e tests with adversarial strings pass on first run and replay (idempotent result count).
- SC-003: No regression in insert throughput (>95% of baseline in load test of 1k msgs/sec).
