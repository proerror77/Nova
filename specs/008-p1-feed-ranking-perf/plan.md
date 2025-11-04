# Implementation Plan: Feed Ranking Micro-optimizations

**Branch**: `[008-p1-feed-ranking-perf]` | **Date**: 2025-11-04 | **Spec**: specs/008-p1-feed-ranking-perf/spec.md

## Steps

1) In `backend/feed-service/src/handlers/*`, parse inbound post IDs once to `Vec<Uuid>` with `with_capacity`
2) In `hybrid_ranker`, allocate score vectors/maps with `with_capacity(candidates.len())`
3) Replace `reason: String` with `&'static str` or `Cow<'static, str>`
4) Add criterion benches under `backend/feed-service/benches/`

