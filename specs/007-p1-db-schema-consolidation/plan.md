# Implementation Plan: Database Schema Consolidation

**Branch**: `[007-p1-db-schema-consolidation]` | **Date**: 2025-11-04 | **Spec**: specs/007-p1-db-schema-consolidation/spec.md

## Summary

12-week Strangler plan to consolidate duplicated schemas, unify soft delete, remove redundant counters, and fix FKs/indexes.

## Phases

1) Week 1–2: Freeze migrations; produce data dictionary and ownership matrix
2) Week 3–4: Users table unification (auth-service canonical); add views/shims
3) Week 5–6: Soft delete normalization (`deleted_at`); remove boolean flags
4) Week 7–8: Redundant tables/columns removal (e.g., like_count), backfilled aggregates
5) Week 9–10: FK and index strategy cleanup; add composites; remove dupes
6) Week 11–12: Cutover and deprecation of shims; perf validation

