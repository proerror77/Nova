# Feature Specification: Feed Ranking Micro-optimizations

**Feature Branch**: `[008-p1-feed-ranking-perf]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Avoid repeated UUID::parse_str and avoid repeated string allocations; pre-allocate vectors"

## Verification (code audit) — 2025-11-05

- Ranking loop parses UUID per candidate and allocates `String` for reason each push; vectors are not preallocated.
  - References: `backend/content-service/src/services/feed_ranking.rs:224-246` (loop with `post_id_uuid()?`, `reason: "combined_score".to_string()`), no `with_capacity`.
- Candidate fetch paths use parameterized queries (good): `query_with_params` in ClickHouse client.
  - Reference: `backend/content-service/src/db/ch_client.rs:49-63`, used in feed ranking methods.

Action:
- Pre-allocate `ranked` with `with_capacity(candidates.len())`, use `&'static str` or `Cow<'static, str>` for `reason`, and consider parsing UUIDs at source if possible.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Efficient candidate handling (Priority: P2)

As a performance engineer, I want ranking to pre-parse IDs and pre-allocate buffers to minimize per-candidate overhead at 1k+ candidates.

**Independent Test**: 1k candidates benchmark shows reduced allocations and CPU (criterion.rs).

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Convert inbound candidate strings to `Vec<Uuid>` once at API boundary; reuse across pipeline.
- FR-002: Use `Vec::with_capacity` for score vectors; avoid repeated `String` allocations for reason by using `&'static str` or `Cow`.
- FR-003: Add micro-benchmarks for 100/1k/10k candidates.

## Success Criteria *(mandatory)*

- SC-001: >=20% reduction in allocations (measured via heap profiler or criterion)
- SC-002: p95 latency improves by >=10% for 1k candidates on dev hardware
