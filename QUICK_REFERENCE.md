# Nova Social Platform - Quick Reference

**Last Updated**: 2025-10-24  
**Current Branch**: feature/US3-message-search-fulltext  
**Status**: Phase 7B in progress (Messaging + Stories)

---

## At a Glance

| Aspect | Details |
|--------|---------|
| **Type** | Microservices (Rust + PostgreSQL) |
| **Services** | 3 active (user, messaging, search) + 2 planned |
| **Platform** | iOS (SwiftUI) + React (TypeScript) |
| **Database** | PostgreSQL 14+, shared single DB |
| **Message Queue** | Kafka (events) + Redis pub/sub (real-time) |
| **Deployment** | Docker + Kubernetes + GitHub Actions |
| **Current Feature** | User Story 3: Message Full-Text Search (P2) |

---

## Service Quick Lookup

### user-service (Port 8080)
- **What**: Authentication, users, relationships, feed, posts, videos, streaming, stories
- **Tech**: Actix-web / Axum, FFmpeg, TensorFlow
- **Status**: 🟢 STABLE
- **Key Files**: `src/handlers/`, `src/services/`

### messaging-service (Port 8085 external, 3000 internal)
- **What**: Real-time 1:1 & group chat, E2E encryption, reactions, attachments
- **Tech**: Axum, Tokio, WebSocket, libsodium (NaCl)
- **Status**: 🟡 BETA (US1 complete, US2 partial)
- **Key Files**: `src/routes/`, `src/websocket/`, `src/services/`

### search-service (Port 8081) ⭐
- **What**: Full-text search (messages, users, posts)
- **Tech**: Axum, PostgreSQL tsvector/tsquery, Redis, Kafka
- **Status**: 🚀 IN DEVELOPMENT (US3 P2)
- **Key Files**: `src/main.rs`, `src/events/`

---

## Database Schema Quick Map

```
📊 PostgreSQL (Single Shared DB)

User Service:
├─ users                    (user profiles)
├─ social_graph             (follows/followers)
├─ feeds                    (feed entries)
├─ videos                   (video metadata)
├─ video_embeddings         (pgvector ML features)
└─ streaming_sessions       (live stream tracking)

Messaging Service:
├─ conversations            (chat rooms)
├─ conversation_members     (membership)
├─ messages                 (encrypted messages)
├─ message_reactions        (emoji reactions)
└─ read_receipts            (message read status)

Search Service:
└─ message_search_index     (plaintext for searching)

Auth/Security:
├─ jwt_signing_keys         (JWT rotation)
└─ oauth_credentials        (provider configs)
```

**Total Migrations**: 25+ (in `backend/migrations/`)

---

## API Endpoints Quick Reference

### User Service (user-service:8080)
Note: endpoints marked [JWT] require Bearer token.
```
POST   /api/v1/auth/register              # Register
POST   /api/v1/auth/login                 # Login
POST   /api/v1/auth/google-verify         # OAuth Google
POST   /api/v1/auth/apple-verify          # OAuth Apple
POST   /api/v1/auth/facebook-verify       # OAuth Facebook
GET    /api/v1/users/:id                  # Get user
POST   /api/v1/users/:id/follow           # Follow user
DELETE /api/v1/users/:id/follow           # Unfollow user
GET    /api/v1/users/:id/followers        # List followers
GET    /api/v1/users/:id/following        # List following
GET    /api/v1/discover/suggested-users   # Friend discovery (Neo4j-backed when enabled)
GET    /api/v1/feed                       # Get feed
GET    /api/v1/videos/:id                 # Get video
GET    /api/v1/streams/:id/manifest       # HLS manifest
```

### Messaging Service (external http://localhost:8085, internal http://messaging-service:3000)
Note: no /api/v1 prefix in this service.
```
POST   /api/v1/conversations              # Create chat
GET    /api/v1/conversations/:id          # Get chat
GET    /api/v1/conversations              # List chats
POST   /api/v1/messages                   # Send message
GET    /api/v1/messages/:id               # Get message
PUT    /api/v1/messages/:id               # Edit message
DELETE /api/v1/messages/:id               # Delete message
POST   /api/v1/reactions                  # Add reaction
WS     /ws                                # WebSocket (real-time)
```

### Search Service (search-service:8081)
```
GET    /health
GET    /api/v1/search/users
GET    /api/v1/search/posts
GET    /api/v1/search/hashtags
POST   /api/v1/search/clear-cache
```

---

## Common Commands

```bash
# Start infrastructure
cd /Users/proerror/Documents/nova
docker-compose up -d

# Build & run services
cd backend/user-service && cargo run
cd backend/messaging-service && cargo run
cd backend/search-service && cargo run

# Frontend dev
cd frontend && npm install && npm run dev

# Run tests
cargo test --all
./backend/search-service/test-fulltext-cache.sh

# Database migrations
psql $DATABASE_URL -f backend/migrations/023_message_search_index.sql

# Check service health
curl http://localhost:8080/api/v1/health

# Social graph backfill (PostgreSQL -> Neo4j)
NEO4J_ENABLED=true \
NEO4J_URI=bolt://localhost:7687 \
NEO4J_USER=neo4j \
NEO4J_PASSWORD=neo4j \
make graph-backfill

# Incremental backfill examples
# 1) Backfill last 60 minutes only
BACKFILL_LOOKBACK_MINUTES=60 make graph-backfill

# 2) Backfill since a fixed timestamp (RFC3339)
BACKFILL_SINCE="2025-10-24T00:00:00Z" make graph-backfill

# Apply Neo4j constraints/indexes (first time)
make neo4j-init

# Run social lightweight tests only
make test-social
curl http://localhost:8085/health
curl http://localhost:8081/health
```

---

## Current Feature: US3 Message Search

### What is it?
User Story 3 (Priority P2): "Users search messages by keywords, ranked by relevance and sorted by recency"

### Implementation
```
Message Flow:
  1. User sends message → messaging-service
  2. Message persisted → Kafka event (message_persisted)
  3. search-service consumes event → inserts into message_search_index
  4. PostgreSQL tsvector/tsquery creates searchable index
  5. User searches → GET /api/v1/search/messages?q=...
  6. Result cached in Redis (24h TTL)
```

### Status
- ✅ Schema complete
- ✅ Kafka integration done
- 🚀 API endpoint in progress
- 🚀 Integration tests needed
- 🚀 Frontend integration

### Key File
- `backend/migrations/023_message_search_index.sql` - Schema definition
- `backend/search-service/src/main.rs` - API implementation

---

## Architecture Decisions (Good Taste)

✅ **Single PostgreSQL DB** → Simplicity, no distributed transactions  
✅ **PostgreSQL tsvector** → No external dependency, built-in ranking  
✅ **Redis Pub/Sub + Kafka** → Fast intra-service (Redis) + durable inter-service (Kafka)  
✅ **E2E encryption at rest only** → Privacy without "searchable encryption"  
✅ **Axum for search** → Lightweight, async, I/O bound  

🟡 **User-service too large** → Consider splitting video to separate service  
🟡 **Manual migration ordering** → Could be fragile for concurrent dev  
🟡 **Integration tests ignored** → Should run in CI/CD pipeline  

---

## File Structure

```
nova/ (monorepo)
├── backend/
│   ├── user-service/        ← Auth, feed, videos
│   ├── messaging-service/   ← Real-time chat
│   ├── search-service/      ← Full-text search ⭐
│   ├── libs/crypto-core/    ← Shared encryption
│   ├── migrations/          ← Database schemas
│   └── Cargo.toml           ← Workspace config
├── frontend/                ← React 18 + TypeScript
├── ios/
│   ├── NovaSocial/          ← SwiftUI app
│   └── NovaSocialApp/       ← Production app
├── k8s/                     ← Kubernetes manifests
├── specs/                   ← Feature specifications
├── docs/                    ← Documentation
├── docker-compose.yml       ← Local dev stack
└── NOVA_PROJECT_ANALYSIS.md ← Full analysis (THIS FILE)
```

---

## Git Branches

| Branch | Purpose |
|--------|---------|
| `main` | Production (stable) |
| `develop/phase-7c` | Next phase development |
| `feature/US3-message-search-fulltext` | **Current branch** |
| `chore/docs-cleanup*` | Documentation cleanup |

---

## Resources

- **Full Analysis**: `/Users/proerror/Documents/nova/NOVA_PROJECT_ANALYSIS.md`
- **Specs**: `/Users/proerror/Documents/nova/specs/002-messaging-stories-system/`
- **Documentation**: `/Users/proerror/Documents/nova/docs/`
- **README**: `/Users/proerror/Documents/nova/README.md`

---

**Generated by**: Claude Code Analysis  
**Date**: 2025-10-24  
**Status**: ✅ Complete
