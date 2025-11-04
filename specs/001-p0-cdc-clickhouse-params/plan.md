# Implementation Plan: Secure CDC Inserts (ClickHouse Params)

**Branch**: `[001-p0-cdc-clickhouse-params]` | **Date**: 2025-11-04 | **Spec**: specs/001-p0-cdc-clickhouse-params/spec.md
**Input**: Feature specification from `/specs/001-p0-cdc-clickhouse-params/spec.md`

## Summary

Replace ad-hoc SQL string concatenation in CDC consumer with typed, parameterized inserts using the `clickhouse` crate’s insert API and row structs. Remove `escape_string` from hot paths and add tests with adversarial content.

## Technical Context

**Language/Version**: Rust 1.75+  
**Primary Dependencies**: `clickhouse`, `serde`, `rdkafka`, `sqlx`  
**Storage**: ClickHouse (ReplacingMergeTree tables)  
**Testing**: `cargo test`, `testcontainers` (ClickHouse)  
**Target Platform**: Linux server  
**Performance Goals**: Parity with baseline insert throughput (>=95%)  
**Constraints**: Preserve exactly-once semantics with existing offset manager

## Project Structure

### Documentation (this feature)

```
specs/001-p0-cdc-clickhouse-params/
├── plan.md
└── spec.md
```

### Source Code (repository root)

```
backend/user-service/src/
├── db/ch_client.rs                 # Add typed insert helpers
└── services/cdc/consumer.rs        # Replace string INSERTs with typed inserts
backend/user-service/tests/
└── integration/cdc_clickhouse_tests.rs   # New tests (with testcontainers)
```

**Structure Decision**: Minimal changes localized to user-service CDC code + tests.

## Constitution Check

- Security-first change; reduces complexity in CDC SQL paths; testability improves. No violations.

## Dependencies & Execution Order

1) Add row types and typed insert helper (CH client)
2) Replace INSERT construction in CDC handlers (posts/follows/comments/likes)
3) Add integration tests with ClickHouse testcontainer
4) Remove redundant escaping; keep minor validation utilities
5) Load-validate throughput on dev env

