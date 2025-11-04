# Implementation Plan: Bounded Redis SCAN Invalidation

**Branch**: `[004-p0-redis-scan-bounds]` | **Date**: 2025-11-04 | **Spec**: specs/004-p0-redis-scan-bounds/spec.md

## Summary

Bound the SCAN loop with iteration and key caps; add metrics and jitter; ensure graceful exit under churn.

## Steps

1) Add constants `MAX_ITERATIONS`, `MAX_KEYS`
2) Track `iterations` and `deleted_total`; break when caps hit
3) Randomize COUNT in [100, 500]; small `tokio::time::sleep(1-2ms)` per 10k keys
4) Log continuation hint with `pattern` and last `cursor` if not fully complete

