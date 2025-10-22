# Implementation Plan: Phase 7B - Messaging + Stories System

**Branch**: `002-messaging-stories-system` | **Date**: 2025-10-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-messaging-stories-system/spec.md`

## Summary

Build a production-grade messaging + stories platform enabling real-time 1:1/group communication and ephemeral content sharing. Implement PostgreSQL persistence, Redis caching, Elasticsearch search, and WebSocket real-time sync. Target: 50k+ concurrent connections, <200ms message latency, <100ms story load, 160+ tests with >85% coverage. Phase 7B execution: Weeks 5-12 with 4-5 backend engineers.

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Rust 1.75+ (backend), TypeScript/React (frontend)
**Primary Dependencies**: Tokio (async runtime), axum (web framework), tokio-tungstenite (WebSocket), sqlx (PostgreSQL), redis (caching), elasticsearch-rs (search), serde (JSON)
**Storage**: PostgreSQL (messages, conversations, users, stories), Redis (real-time counters, caching), Elasticsearch (full-text search)
**Testing**: cargo test (unit), tokio test (async), custom load testing framework for 50k+ concurrent connections
**Target Platform**: Linux servers (backend), web browsers (frontend), iOS/Android clients
**Project Type**: Web application (backend API + WebSocket + frontend + mobile clients)
**Performance Goals**: 10,000+ messages/sec throughput, 50,000+ concurrent WebSocket connections, <100ms p50 message latency
**Constraints**: <200ms p95 message delivery, <200ms p95 search, <100ms p95 story feed load, <50ms reaction propagation, offline message queueing, auto-expiration at 24h
**Scale/Scope**: Support 1M+ users, 100M+ daily active conversations, 10B+ messages indexed, 500M+ stories/day creation

## Constitution Check

*GATE: All constraints satisfied. No violations.*

✅ **Architecture Review**:
- Feature complexity (5 major systems): Justified - Messaging, Stories, Reactions, Search, Analytics require independent services
- E2E encryption requirement: Necessitates client-side encryption library + key management service
- Real-time scale (50k+ concurrent): Requires dedicated WebSocket service + load balancing
- Data volume (10B+ messages, 500M stories/day): Necessitates partitioning + archive strategy

## Project Structure

### Documentation (this feature)

```
specs/002-messaging-stories-system/
├── spec.md              # ✅ COMPLETED: Feature specification with 8 user stories, 18 FRs, success criteria
├── plan.md              # This file - Implementation planning
├── research.md          # PENDING: Phase 0 - Technology research & feasibility
├── data-model.md        # PENDING: Phase 1 - Database schema & data relationships
├── quickstart.md        # PENDING: Phase 1 - Developer quickstart guide
├── contracts/           # PENDING: Phase 1 - API contracts (OpenAPI specs)
└── tasks.md             # PENDING: Phase 2 - Detailed task breakdown via /speckit.tasks
```

### Source Code (repository root)

```
backend/user-service/src/
├── api/
│   ├── routes/
│   │   ├── conversations.rs     # Conversation CRUD + membership management
│   │   ├── messages.rs          # Message send/receive/search/delete/reactions
│   │   ├── stories.rs           # Story CRUD + view tracking + expiration
│   │   └── websocket.rs         # WebSocket handler for real-time sync
│   └── handlers/
│       ├── message_handler.rs   # Message business logic + encryption
│       ├── reaction_handler.rs  # Emoji reaction logic + propagation
│       └── story_handler.rs     # Story lifecycle + auto-expiration
│
├── services/
│   ├── messaging/               # [NEW] Messaging service module
│   │   ├── mod.rs
│   │   ├── encryption.rs        # E2E encryption/decryption using TweetNaCl
│   │   ├── offline_queue.rs     # Local message queue for offline clients
│   │   └── mention_resolver.rs  # @mention parsing & notification dispatch
│   │
│   ├── stories/                 # [NEW] Stories service module
│   │   ├── mod.rs
│   │   ├── expiration.rs        # 24h auto-expiration worker
│   │   └── privacy.rs           # Three-tier privacy enforcement
│   │
│   ├── reaction_service.rs      # [EXISTING] Extend for message reactions
│   └── redis_job.rs             # [EXISTING] Real-time counter updates
│
├── db/
│   ├── messaging_repo.rs        # [EXISTING] Message/Conversation persistence
│   └── mod.rs                   # Add story repository if needed
│
└── main.rs                       # Add WebSocket route + encryption key rotation task

backend/user-service/migrations/
├── 0001_create_conversations.sql
├── 0002_create_messages.sql
├── 0003_create_message_reactions.sql
├── 0004_create_stories.sql
├── 0005_create_story_views.sql
├── 0006_create_conversation_members.sql
└── 0007_add_encryption_keys_table.sql

frontend/src/
├── components/
│   ├── MessagingUI/
│   │   ├── ConversationList.tsx
│   │   ├── MessageThread.tsx
│   │   ├── MessageComposer.tsx   # With @mention autocomplete
│   │   └── ReactionPicker.tsx
│   │
│   └── StoriesUI/
│       ├── StoryFeed.tsx
│       ├── StoryCreator.tsx      # With privacy level selector
│       └── StoryViewer.tsx
│
├── services/
│   ├── websocket/                # [NEW] WebSocket management
│   │   └── ws-client.ts
│   ├── encryption/               # [NEW] Client-side E2E encryption
│   │   └── crypto.ts
│   └── messaging/                # [NEW] Message API client
│       └── api.ts
│
└── hooks/
    └── useMessaging.ts           # React hook for messaging state

tests/
├── unit/
│   ├── message_encryption_test.rs
│   ├── offline_queue_test.rs
│   ├── reaction_propagation_test.rs
│   ├── story_expiration_test.rs
│   └── privacy_enforcement_test.rs
│
├── integration/
│   ├── messaging_e2e_test.rs
│   ├── websocket_sync_test.rs
│   ├── story_lifecycle_test.rs
│   └── search_integration_test.rs
│
└── load/
    ├── websocket_load_test.rs    # 50k concurrent connections
    ├── message_throughput_test.rs # 10k msg/sec
    └── story_feed_test.rs         # <100ms P95
```

**Structure Decision**: Extended Option 2 (Web application with backend + frontend).
- **Backend**: Rust/axum in existing `backend/user-service/` project, adding 5 new service modules
- **Frontend**: TypeScript/React in existing `frontend/` project, adding 2 new component suites
- **Migrations**: 7 new PostgreSQL migration files for messaging data model
- **Tests**: 40+ integration + load tests in `tests/` directory

## Complexity Tracking

| Component | Why Needed | Technical Justification |
|-----------|-----------|-------------------------|
| E2E Encryption (TweetNaCl) | FR-017 security requirement | Message content encrypted client-side; server cannot read. Requires symmetric key exchange + per-message nonce |
| WebSocket Handler | Real-time sync requirement | HTTP polling insufficient for <100ms latency. Tokio-tungstenite + axum upgrade for <50ms reaction propagation |
| Elasticsearch integration | Search requirement (FR-006) | PostgreSQL full-text insufficient at 10B+ messages. Need Elasticsearch for <200ms P95 sub-second results |
| Offline message queue | Mobile-first design | Clients buffer 1000+ messages locally during disconnects. On reconnect, replay in order. Requires deterministic sequencing |
| 24h story auto-expiration | Business requirement (FR-008) | PostgreSQL TTL insufficient; require scheduled job + cascade delete. Redis TTL for performance cache + Tokio interval task |
| Three-tier privacy enforcement | User requirement (FR-018) | Followers/close-friends require relationship graph lookup per story view. Cannot be simple boolean flag |
| @mention notification dispatch | User requirement (FR-016) | Real-time notification + persistence. Requires async task queue + Redis for delivery state tracking |

## Implementation Phases & Timeline

**Total Duration**: 8 weeks (Week 5-12) | **Team**: 4-5 Backend + 2-3 Frontend + 1 QA

### Phase 0: Research & Design (Week 5 - Days 1-2)
**Deliverables**: research.md + data-model.md + API contracts

- [ ] TweetNaCl/libsodium E2E encryption integration feasibility
- [ ] Elasticsearch message indexing strategy for 10B+ messages
- [ ] PostgreSQL sharding/partitioning for 500M stories/day
- [ ] WebSocket load testing framework for 50k concurrent
- [ ] Redis key expiration strategy for 24h stories
- [ ] Kafka integration for message CDC to Elasticsearch

**Output**: 3 documents ready for Phase 1 design

### Phase 1: Data Model & Contracts Design (Week 5 - Days 3-5)
**Deliverables**: data-model.md + contracts/ + quickstart.md

- [ ] PostgreSQL schema: conversations, messages, stories, reactions, views
- [ ] Message encryption key management schema
- [ ] Elasticsearch mapping for full-text search
- [ ] OpenAPI contract for REST endpoints
- [ ] WebSocket message protocol specification
- [ ] Database migration scripts (0001-0007)

**Output**: Design artifacts ready for implementation

### Phase 2: Core Infrastructure (Week 6-7)
**Tasks**: T211-T213 (Messaging Model, API, WebSocket)
**Owners**: Backend Engineers A, B, C

**Week 6 (T211: Message Model + Encryption)**
- [ ] Implement Message, Conversation, ConversationMember entities in Rust
- [ ] Add TweetNaCl/libsodium wrapper for encryption/decryption
- [ ] Offline queue implementation for buffered message replay
- [ ] 40+ unit tests for encryption + queueing logic
- [ ] Database migrations 0001-0002

**Week 6-7 (T212: REST API + Search)**
- [ ] POST /conversations (create 1:1/group)
- [ ] POST /messages (send + encrypt)
- [ ] GET /messages (fetch + search via Elasticsearch)
- [ ] DELETE /messages/{id} (delete + broadcast)
- [ ] Elasticsearch integration + CDC from Kafka
- [ ] 30+ integration tests

**Week 7 (T213: WebSocket Real-time Sync)**
- [ ] WebSocket handler in axum (tokio-tungstenite)
- [ ] Message broadcast to all conversation members
- [ ] Reaction propagation <50ms via pub/sub
- [ ] Connection tracking + offline detection
- [ ] Load test: 50,000 concurrent connections
- [ ] 20+ E2E tests for sync scenarios

### Phase 3: Stories System (Week 8-9)
**Tasks**: T214-T215 (Stories Model, API + Features)
**Owners**: Backend Engineer D, Frontend Engineer A

**Week 8 (T214: Story Model + Expiration)**
- [ ] Create Story, StoryView, CloseFriends entities
- [ ] 24h auto-expiration Tokio task
- [ ] Privacy enforcement (public/followers/close-friends)
- [ ] Story view counter with Redis caching
- [ ] 30+ unit tests for expiration + privacy
- [ ] Database migrations 0004-0006

**Week 9 (T215: Story API + Frontend)**
- [ ] POST /stories (create with privacy level)
- [ ] GET /stories/feed (fetch + privacy filter)
- [ ] POST /stories/{id}/views (track views)
- [ ] Reaction support for stories
- [ ] Frontend: StoryCreator, StoryFeed, StoryViewer components
- [ ] 25+ integration + 15 component tests

### Phase 4: Advanced Features & Quality (Week 10-11)
**Tasks**: Reactions, @mentions, Analytics, Performance optimization
**Owners**: All engineers

**Week 10: Features**
- [ ] @mention parsing + real-time notification dispatch
- [ ] Conversation metadata + analytics API
- [ ] Message edit with history tracking
- [ ] Reaction emoji picker + counter updates
- [ ] 25+ tests for new features

**Week 11: Performance & Stability**
- [ ] Message throughput load test (10,000 msg/sec)
- [ ] Story feed P95 <100ms optimization
- [ ] Search latency P95 <200ms tuning
- [ ] Reaction propagation P99 <100ms validation
- [ ] Stress test with 50k concurrent + high message volume
- [ ] Error handling + retry logic for transient failures
- [ ] 20+ load + chaos tests

### Phase 5: Launch Preparation (Week 12)
**Deliverables**: Production-ready system + documentation

- [ ] Security review + penetration testing
- [ ] Performance targets validation (all SLAs met)
- [ ] Documentation: runbooks, on-call playbooks, deployment guide
- [ ] Team training + knowledge transfer
- [ ] Monitoring + alerting setup (Prometheus + PagerDuty)
- [ ] Canary deployment strategy for 1% → 10% → 100%
- [ ] Final E2E testing with production-like data volume

## Success Criteria & Metrics

| Metric | Target | Validation |
|--------|--------|------------|
| **Messaging Latency (P50)** | <100ms | Automated load test with 50k concurrent |
| **Messaging Latency (P95)** | <200ms | Sustained under peak load |
| **Search Latency (P95)** | <200ms | 1000+ result queries |
| **Story Feed Load (P95)** | <100ms | 10k stories in feed, privacy filtered |
| **Reaction Propagation (P99)** | <100ms | 1000 simultaneous reactions |
| **Message Throughput** | 10,000 msg/sec | Sustained for 1 minute |
| **Concurrent WebSocket** | 50,000+ | Zero connection drops |
| **Message Delivery Rate** | >99.9% | Zero unplanned loss over 30 days |
| **Code Coverage** | >85% | 160+ tests (unit + integration) |
| **E2E Encryption** | Zero client-side message leaks | Security review certified |
| **Story Auto-deletion** | 100% within 1h of expiration | Automated verification |
| **Team Productivity** | 8 weeks on schedule | Weekly burn-down tracking |

## Risk & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|-----------|
| E2E encryption complexity | 2-3 week delay | Medium | Start with TweetNaCl POC week 5, pair programming |
| WebSocket scale testing | 1-2 week delay | Medium | Early load test framework in week 6 |
| Elasticsearch indexing lag | Search SLA miss | Low | Implement CDC monitoring, alert on lag >5s |
| Story expiration gaps | Data loss | Low | Periodic consistency check job, PostgreSQL TTL backup |
| Message order corruption | Delivery guarantees broken | Very Low | Sequence numbers + deterministic ordering tests |

