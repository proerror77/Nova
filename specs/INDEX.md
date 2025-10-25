# Nova Specs Index

This index anchors living specs to implementation. Updated 2025-10-25.

## Active Specs

### 003-critical-fixes-p1-stabilization ✅ COMPLETED
**Status**: All 5 CRITICAL issues resolved
**Branch**: `feature/US3-message-search-fulltext`
**Commit**: 8143b193

Fixes for:
- TOCTOU race condition (messages.rs)
- Message loss on reconnection (handlers.rs)
- Redis unbounded growth (streams.rs)
- Code quality warnings (jwt.rs, authorization.rs)
- iOS infinite retry loop (ChatViewModel.swift)

Implementation: `backend/messaging-service/src/routes/messages.rs`, `backend/messaging-service/src/websocket/handlers.rs`, `backend/messaging-service/src/websocket/streams.rs`, `ios/NovaSocialApp/ViewModels/Chat/ChatViewModel.swift`

---

### 002-messaging-stories-system 🟡 IN DEVELOPMENT
**Status**: Phase 7B - Core messaging complete, search in progress
**Branch**: `feature/US3-message-search-fulltext`

#### Messaging (7B) - ✅ Complete
  - API handlers: `backend/messaging-service/src/routes/messages.rs`
  - Services: `backend/messaging-service/src/services/message_service.rs`
  - WebSocket: `backend/messaging-service/src/websocket/handlers.rs`
  - Migrations: `backend/messaging-service/migrations/`
  - Routes: `/api/v1/messages`, `/api/v1/conversations`

#### Search (US3) - 🟡 In Progress
  - Service: `backend/search-service/src/`
  - Elasticsearch integration
  - Full-text search with encryption

#### Stories (7B) - Not Started
  - Service: `backend/story-service/src/`
  - Ephemeral content (24-hour auto-expire)

Validation: run `make spec-validate` from `backend/` to verify routes and files exist.

---

### 001-rtmp-hls-streaming 🟡 IN DEVELOPMENT
**Status**: Video streaming infrastructure
**Branch**: Various feature branches

Implementation in progress.

---

## Historical Specs

- Phase 6 progress: `docs/phase-6/`
- Phase 7A completion: Notifications + Social Graph
- Phase 7B planning: Messaging + Stories

---

## Key Metrics

| Spec | Status | Completion | Risk |
|------|--------|------------|------|
| 003-critical-fixes | ✅ Complete | 100% | 🟢 LOW |
| 002-messaging-stories | 🟡 In Progress | ~70% | 🟡 MEDIUM |
| 001-rtmp-hls-streaming | 🟡 In Progress | ~40% | 🔴 HIGH |

**Overall Project**: Ready for Phase 7B core features, critical stability issues resolved.

---

## Next Milestones

- [ ] Merge spec 003 (critical fixes) to main
- [ ] Complete spec 002 message search (US3)
- [ ] Progress spec 002 stories (US4)
- [ ] Begin spec 001 streaming completion

---

**Last Updated**: 2025-10-25
**Next Review**: 2025-10-30

