# Implementation Plan: CreateComment RPC

**Branch**: `[010-p1-comment-rpc]` | **Date**: 2025-11-05 | **Spec**: specs/010-p1-comment-rpc/spec.md
**Priority**: P1 (Core feature - comments are primary engagement)
**Dependency**: 009-p0-auth-register-login (need authenticated users)

## Summary

Add CreateComment gRPC method to content-service with validation, persistence, and cache invalidation.

## Project Structure

```
backend/content-service/src/
├── grpc/mod.rs                # Add CreateComment RPC
├── db/comment.rs              # INSERT comment, validate post exists
└── cache/comment_cache.rs     # Invalidate comment list cache

backend/content-service/tests/
└── integration/comment_test.rs # E2E CreateComment tests
```

## Timeline

- Phase 1 (DB layer): 1 day
- Phase 2 (RPC + validation): 1 day
- Phase 3 (Cache + tests): 1-2 days
- **Total**: 3-4 days

## Parallel Work

Can run after: 009-p0-A (Auth) — needs authenticated user
Can run parallel with: 001-008 (all P0 specs)
Blocker for: 011 (Outbox) — comments trigger outbox events
