# Implementation Plan: Outbox Event Consumer

**Branch**: `[011-p1-outbox-consumer]` | **Date**: 2025-11-05 | **Spec**: specs/011-p1-outbox-consumer/spec.md
**Priority**: P1 (Event reliability)
**Dependencies**: 006-p0-testcontainers (need Kafka test containers) AND 010-p1-comment-rpc (comments trigger outbox events)

## Summary

Implement background worker to consume PostgreSQL outbox table, publish to Kafka with exactly-once semantics.

## Project Structure

```
backend/user-service/src/services/
├── outbox/
│   ├── consumer.rs          # Main consumer loop
│   ├── publisher.rs         # Kafka publish logic
│   └── models.rs            # OutboxEvent struct
```

## Timeline

- Phase 1 (Consumer loop + retry): 2 days
- Phase 2 (Kafka + DLQ): 1 day
- Phase 3 (Tests + integration): 1 day
- **Total**: 4 days

## Parallel Work

Can run after: 006 (testcontainers) + 010 (comment-rpc must complete first, as comments trigger outbox events)
Blocker for: none (optional event publishing)
Note: 010 comment creation populates outbox table; 011 consumer processes those events
