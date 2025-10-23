# Implementation Plan: Phase 7B - Messaging + Stories System

**Branch**: `002-messaging-stories-system` | **Date**: 2025-10-22 | **Spec**: `/specs/002-messaging-stories-system/spec.md`

**Input**: Feature specification from `/specs/002-messaging-stories-system/spec.md`

## Summary

Build production-grade messaging + stories platform supporting 1M+ users with real-time 1:1/group communication, 24-hour auto-expiring stories, and emoji reactions. Core encryption uses libsodium NaCl (E2E) with server-side searchable encryption for Elasticsearch integration. System delivers <200ms P95 message latency and <100ms story feed load times.

## Technical Context

**Language/Version**:
- Backend: Rust 1.75+ (async/await, Tokio, axum)
- Frontend: TypeScript 5.2+, React 18.2+, Node.js 20 LTS

**Primary Dependencies**:
- **Backend**: axum (web framework), tokio (async runtime), tokio-tungstenite (WebSocket), sqlx (async SQL), libsodium via sodiumoxide (encryption), elasticsearch-rs (search), rdkafka (Kafka), redis (fanout/cache), uuid, serde, tracing
- **Frontend**: React, Zustand (state), Vite (build), axios (HTTP), TanStack Query (async data), Vitest (tests), vite-plugin-wasm (WASM integration for Rust crypto)

**Storage**:
- **Primary**: PostgreSQL 15+ (messages, conversations, reactions, stories)
- **Search**: Elasticsearch 8.x (full-text search on encrypted keywords)
- **Cache**: Redis 7+ (WebSocket pub/sub, session cache, rate limiting)

**Testing**:
- **Backend**: cargo test (unit + integration), testcontainers (PostgreSQL/Redis/ES containers)
- **Frontend**: Vitest + React Testing Library
- **E2E**: Playwright or manual WebSocket client tests

**Target Platform**: Linux servers (cloud-native, containerized), Web browsers (Chrome 90+, Safari 15+, Firefox 88+)

**Project Type**: Web application (backend REST API + WebSocket + frontend SPA)

**Performance Goals**:
- Message latency P95: <200ms
- Story feed load: <100ms P95
- Search queries: <200ms P95 for <1000 results
- Reaction propagation: <50ms
- Throughput: 10,000+ messages/sec, 50,000+ concurrent WebSocket connections

**Constraints**:
- TLS 1.3 mandatory (no fallback to 1.2)
- Privacy modes per conversation:
  - Strict E2E: Client-held keys; server never sees plaintext; not searchable; no admin read access.
  - Search-enabled: Server-side decryption for indexing/moderation; encryption-at-rest; auditable access.
- Message ordering: sequence_number + idempotency_key for deduplication

**Scale/Scope**:
- 1M+ registered users
- 100M+ daily active conversations
- 10B+ messages (indexed and searchable)
- 500M+ new stories/day
- ~215 tasks across 8 user stories

---

## Constitution Check

**GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.**

### Constitutional Principles Validation

| Principle | Status | Evidence | Action |
|-----------|--------|----------|--------|
| **TDD (Red-Green-Refactor)** | ✅ PASS | Add TDD gate tasks per story; tests precede code | Enforce in CI (block PRs without tests) |
| **Rust for Business Logic** | ✅ PASS | Crypto in Rust (`libs/crypto-core`) and reused by FE via WASM | Remove JS crypto; FE calls WASM wrapper |
| **Microservices + Event-Driven** | ✅ PASS | Messaging, Stories, Search, Notifications services; Kafka topics defined | Implement producers/consumers and CDC where appropriate |
| **Security & Privacy First** | ✅ PASS | TLS1.3 ingress, privacy modes, audited access | Add TLS/cert tasks; retention/DR tasks |
| **Observability & Monitoring** | ✅ PASS | Prometheus/OTel tasks exist | Wire metrics/traces per service |
| **CI/CD** | ✅ PASS | Lint/format/test gates; containers | Add pipelines per service |

**Verdict**: Proceed with multi-service architecture (Messaging, Stories, Search, Notifications) from Phase 7B. No monolith exception required.

---

## Project Structure

### Documentation (this feature)

```
specs/002-messaging-stories-system/
├── spec.md              # Requirements + architecture decisions
├── plan.md              # This file (technical + constitution check)
├── research.md          # Technology selection (Rust/Tokio/axum, E2E encryption approaches)
├── data-model.md        # Database schema, key entities, relationships
├── quickstart.md        # Getting started for developers
├── contracts/           # API contracts (OpenAPI, WebSocket message formats)
└── tasks.md             # 215 tasks organized by user story + phase
```

### Source Code Structure

```
backend/
├── messaging-service/
│   ├── src/ (models, services, routes, websocket, events)
│   ├── migrations/
│   └── tests/ (unit, integration, load)
├── story-service/
│   ├── src/
│   ├── migrations/
│   └── tests/
├── search-service/
│   ├── src/ (indexer consumers, APIs for search)
│   ├── docs/ (CDC, topic schemas)
│   └── tests/
├── notification-service/
│   ├── src/
│   ├── migrations/
│   └── tests/
└── libs/
    └── crypto-core/ (Rust crate, WASM build target)

frontend/
└── src/ (components, stores, services)

frontend/
├── src/
│   ├── main.tsx                         # React entry point
│   ├── App.tsx                          # Root component
│   ├── components/
│   │   ├── MessagingUI/
│   │   │   ├── ConversationList.tsx     # List all conversations (US1)
│   │   │   ├── MessageThread.tsx        # Message display area (US1)
│   │   │   ├── MessageComposer.tsx      # Message input + send (US1)
│   │   │   ├── GroupCreator.tsx         # Group creation modal (US2)
│   │   │   ├── MemberList.tsx           # Group member list (US2)
│   │   │   ├── SearchBar.tsx            # Message search (US3)
│   │   │   ├── StoryFeed.tsx            # Story list (US4)
│   │   │   ├── StoryViewer.tsx          # Story viewing (US4)
│   │   │   ├── ReactionPicker.tsx       # Emoji reaction selector (US5)
│   │   │   └── MessageActions.tsx       # Edit/delete/react menu (US6)
│   │   └── Layout/
│   │       ├── Header.tsx               # Top navigation
│   │       └── Sidebar.tsx              # Conversation navigation
│   ├── services/
│   │   ├── api/
│   │   │   ├── client.ts                # Axios HTTP client
│   │   │   ├── conversations.ts         # Conversation API calls
│   │   │   ├── messages.ts              # Message API calls
│   │   │   ├── stories.ts               # Story API calls
│   │   │   ├── search.ts                # Search API calls
│   │   │   └── reactions.ts             # Reaction API calls
│   │   ├── websocket/
│   │   │   └── WebSocketClient.ts       # WebSocket connection manager
│   │   ├── encryption/
│   │   │   └── client.ts                # WASM wrapper over Rust crypto-core
│   │   └── offlineQueue/
│   │       └── Queue.ts                 # IndexedDB offline message queue
│   ├── stores/
│   │   ├── appStore.ts                  # Global Zustand store
│   │   ├── messagingStore.ts            # Messaging state slice
│   │   ├── storyStore.ts                # Story state slice
│   │   └── authStore.ts                 # Auth state slice
│   ├── hooks/
│   │   ├── useMessaging.ts              # Messaging logic hooks
│   │   ├── useWebSocket.ts              # WebSocket connection hook
│   │   └── useOfflineQueue.ts           # Offline queue hook
│   ├── types/
│   │   ├── api.ts                       # API request/response types
│   │   ├── models.ts                    # Domain model types
│   │   └── websocket.ts                 # WebSocket message types
│   └── utils/
│       ├── formatters.ts                # Date/time formatting
│       └── validators.ts                # Input validation
├── tests/
│   ├── components/
│   │   ├── MessagingUI.test.tsx         # Component tests
│   │   └── __snapshots__/               # Snapshot files
│   ├── services/
│   │   ├── websocket.test.ts            # WebSocket client tests
│   │   └── encryption.test.ts           # Encryption roundtrip tests
│   └── integration/
│       └── messaging.test.ts            # Integration tests
├── vite.config.ts                       # Vite build config
├── tsconfig.json                        # TypeScript config
├── package.json                         # Node.js dependencies
├── .env.example                         # Environment template
└── .dockerignore                        # Docker build exclusions

docker-compose.yml                       # Local development: PostgreSQL, Redis, Elasticsearch
Dockerfile (backend)                     # Container image build
Dockerfile (frontend)                    # Container image build
```

**Structure Decision**:
- **Web application** with separate backend (Rust) and frontend (React/TypeScript)
- Backend: axum REST API + WebSocket server (stateless, horizontally scalable)
- Frontend: SPA (Vite build) served from CDN or static hosting
- Database: PostgreSQL with sqlx async client (connection pooling)
- Search: Elasticsearch for full-text search (deterministic encrypted keywords)
- Real-time: Redis pub/sub for WebSocket fanout across backend instances
- All business logic in Rust backend; frontend is presentation + offline queue only

---

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected |
|-----------|------------|------------------------------|
| Searchable Encryption (deterministic) | Enable server-side Elasticsearch search while maintaining E2E encryption | Pure E2E: search impossible server-side; Plaintext search: breaks privacy |
| Admin Key (separate from user keys) | Allow admins to view group messages without compromising E2E of individual members | Break E2E entirely: violates constitutional principle; Per-user admin decryption: admin key exposure compromises all users |
| Redis pub/sub in single service | Enable WebSocket broadcasting across multiple backend instances without Kafka overhead | Single instance: no horizontal scaling; Full Kafka: overkill for 50k concurrent (defer to Phase 7C microservices) |
| 215 tasks (vs. smaller batch) | Cover all FR + NFR + TDD gates + E2E test scenarios thoroughly | Smaller task set: risks incomplete coverage, hard to parallelize team work |

---

## Implementation Phases

### Phase 0: Setup & Infrastructure (Week 1)
- Database schema (PostgreSQL migrations)
- Environment configuration
- Docker Compose local dev setup
- Backend + Frontend project scaffolding
- Test infrastructure (testcontainers, fixtures)

### Phase 1: User Story 1 & 2 (Weeks 2-4)
- Direct messaging + Group conversations
- E2E encryption + Searchable encryption integration
- WebSocket real-time delivery
- REST API endpoints
- Frontend components
- Unit + Integration tests

### Phase 2: User Story 3-5 (Weeks 5-7)
- Message search (Elasticsearch)
- Stories (creation, expiry, view tracking)
- Emoji reactions (real-time propagation)
- Performance optimization + load testing

### Phase 3: User Story 6-8 + Polish (Weeks 8)
- Message editing/deletion (15-minute window)
- Offline queue sync
- Conversation metadata + analytics
- Security hardening (TLS, PII at rest)
- Launch readiness

---

## Next Steps

1. **Review & Approve**: Confirm spec.md architecture decisions + plan.md technical context
2. **Create research.md**: Document technology selection rationale (Rust vs Go, axum vs actix, libsodium vs ring, etc.)
3. **Create data-model.md**: Full SQL schema with indexes, relationships, constraints
4. **Generate tasks.md**: 215 tasks reordered for TDD (unit tests before impl), grouped by story
5. **Kick off Phase 0**: Database setup + infrastructure
