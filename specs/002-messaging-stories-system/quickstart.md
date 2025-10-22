# Phase 1: Quickstart Guide - Messaging + Stories System

**Date**: 2025-10-22 | **Status**: Complete | **Phase**: 1 (Design)

---

## Overview

This quickstart guide helps developers get started with Phase 7B development. All planning artifacts are complete and ready for Week 5 execution.

---

## Prerequisites

### System Requirements

- **OS**: macOS 12+, Linux (Ubuntu 20.04+), or Windows 11 WSL2
- **Rust**: 1.75+ (install via [rustup.rs](https://rustup.rs))
- **Node.js**: 18+ LTS
- **PostgreSQL**: 14+ (local or Docker)
- **Redis**: 7+ (local or Docker)
- **Elasticsearch**: 8+ (local or Docker)

### Development Tools

```bash
# macOS
brew install rust node postgresql redis elasticsearch
# or use Docker
docker-compose up -d postgres redis elasticsearch
```

---

## Project Structure Quick Reference

```
backend/user-service/
├── src/
│   ├── services/
│   │   ├── messaging/         # [NEW] Message encryption + queue
│   │   └── stories/           # [NEW] Story lifecycle + privacy
│   ├── db/
│   │   └── messaging_repo.rs  # [EXISTING] Message persistence
│   └── main.rs                # Add WebSocket route

frontend/
├── src/
│   ├── components/
│   │   ├── MessagingUI/       # [NEW] Conversation + message UI
│   │   └── StoriesUI/         # [NEW] Story + view UI
│   └── services/
│       ├── websocket/         # [NEW] WebSocket client
│       └── encryption/        # [NEW] E2E crypto client

specs/002-messaging-stories-system/
├── spec.md                    # ✅ Feature specification
├── plan.md                    # ✅ Implementation plan
├── research.md                # ✅ Phase 0 findings
├── data-model.md              # ✅ Database schema
├── contracts/                 # Phase 1 API specs
│   ├── messages-api.yaml      # REST API
│   ├── stories-api.yaml       # REST API
│   └── websocket-protocol.md  # WebSocket spec
└── team-assignments.md        # ✅ Team roles + SLAs
```

---

## Getting Started (Week 5, Day 1)

### 1. Clone & Setup Repository

```bash
cd /Users/proerror/Documents/nova

# Verify branches exist
git branch -a | grep -E "002-messaging|develop/phase-7b|feature/T21"

# Create local tracking branches for Week 5 feature branches
git fetch origin
git checkout feature/T211-messaging-model
git checkout feature/T212-messaging-api
# ... etc for T213, T214, T215
```

### 2. Read Planning Artifacts (1 hour)

Read in this order:
1. **README.md** - 5 min overview
2. **spec.md** - 15 min feature specification
3. **plan.md** - 15 min implementation timeline
4. **team-assignments.md** - 15 min your specific role
5. **research.md** - 10 min technical decisions

**Expected outcome**: Full understanding of Phase 7B scope, timeline, and your responsibilities.

### 3. Understand Data Model (30 min)

```bash
# Review data-model.md
# Focus sections:
# - Core Entities (10 users stories, 1:1 vs group)
# - Relationships (how entities connect)
# - Constraints (what's enforced at database level)
# - Partitioning (for message/story scale)
```

### 4. Setup Development Environment

```bash
# Backend setup
cd backend/user-service
cargo build  # Initial compile
cargo test   # Run existing tests

# Frontend setup
cd frontend
npm install
npm run dev  # Start dev server
```

### 5. Create Your Feature Branch

```bash
# Choose your task from team-assignments.md
# Example: Engineer B → T211 (Message Model + Encryption)

git checkout feature/T211-messaging-model
git pull origin feature/T211-messaging-model

# Create working branch off feature branch
git checkout -b work/T211-message-model-v1
```

---

## Development Workflow

### Daily Standup (09:00 UTC)

```
Topics:
- Progress against daily tasks (2 min)
- Blockers + dependencies (2 min)
- Help requests (1 min)
- Tech discussion if needed (10 min)

Slack: #phase-7b-messaging
```

### Code Review Process

**For Feature PRs** (T211-T215):
1. Self-review: Run tests, check code style
2. Create PR with description: motivation + testing approach
3. Tag Tech Lead (Engineer A) for review
4. Address feedback within 24 hours
5. Merge once approved

**Example PR Template**:
```markdown
## Motivation
Implements T211: Message Model + E2E Encryption

## Technical Changes
- [ ] Message struct with encryption fields
- [ ] TweetNaCl wrapper for encrypt/decrypt
- [ ] Offline queue for buffered messages
- [ ] 40+ unit tests

## Testing
- [ ] cargo test passes (160+ tests)
- [ ] Encryption roundtrip verified
- [ ] Queue ordering deterministic

## Performance
- [ ] No regressions vs baseline
- [ ] Encryption: <5ms per message
```

### Testing Requirements

**Unit Tests** (minimum):
- Encryption: 10+ tests for encrypt/decrypt
- Queueing: 15+ tests for queue operations
- Ordering: 10+ tests for message ordering
- Validation: 5+ tests for edge cases

**Running Tests**:
```bash
# Unit tests
cargo test --lib

# Integration tests
cargo test --test '*'

# Specific test
cargo test test_encryption_roundtrip

# With output
cargo test -- --nocapture
```

### Performance Validation

**For Week 6-7 (T211-T213)**:
```bash
# Build release binary
cargo build --release

# Run load tests
cargo test --release -- --nocapture load_test

# Benchmark specific functions
cargo bench message_encryption
```

---

## Common Development Tasks

### Adding a New Endpoint (T212: REST API)

```rust
// 1. Define request/response structs
#[derive(Serialize, Deserialize)]
pub struct SendMessageRequest {
    pub conversation_id: Uuid,
    pub content_encrypted: Vec<u8>,
    pub content_nonce: Vec<u8>,
}

// 2. Create handler function
async fn send_message(
    State(db): State<Arc<PgPool>>,
    Json(req): Json<SendMessageRequest>,
) -> Result<Json<MessageResponse>, AppError> {
    // ... implementation
}

// 3. Add route in main.rs
let app = Router::new()
    .route("/messages", post(send_message))
    .with_state(state);

// 4. Write tests
#[tokio::test]
async fn test_send_message() {
    // ...
}
```

### Implementing WebSocket Handler (T213)

```rust
// 1. Extract websocket upgrade
async fn websocket_handler(
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(handle_connection)
}

// 2. Handle connection
async fn handle_connection(socket: WebSocket) {
    let (mut sender, mut receiver) = socket.split();

    // Receive messages
    while let Some(msg) = receiver.next().await {
        // Broadcast to other clients
    }
}

// 3. Subscribe to Redis pub/sub
let mut pubsub = redis_client.get_async_pubsub();
pubsub.subscribe(&format!("conv:{conversation_id}")).await?;
```

### Adding Database Migration

```bash
# 1. Create migration file
touch backend/user-service/migrations/0001_create_messages.sql

# 2. Write SQL (CREATE TABLE, indexes, etc.)
# See data-model.md for schema

# 3. Run migration
cd backend/user-service
sqlx migrate run

# 4. Verify in database
psql -c "SELECT * FROM messages LIMIT 1;"
```

---

## Debugging Tips

### Database Debugging

```bash
# Connect to PostgreSQL
psql -h localhost -U postgres -d messaging_dev

# View messages table
SELECT id, conversation_id, sender_id, created_at, deleted_at
FROM messages
ORDER BY created_at DESC LIMIT 10;

# View conversations
SELECT id, type, member_count, last_message_at
FROM conversations
ORDER BY last_message_at DESC;
```

### Redis Debugging

```bash
# Connect to Redis CLI
redis-cli

# View keys
KEYS conversation:*
KEYS user:*:followers

# Get value
GET conversation:abc123:members

# Monitor in real-time
MONITOR
```

### WebSocket Debugging

```bash
# Use websocat (install: brew install websocat)
websocat ws://localhost:3000/ws

# Send test message
{"type":"message","conversation_id":"abc","content":"hello"}

# Listen for responses
```

### Rust Debugging

```bash
# Enable debug output
RUST_BACKTRACE=1 cargo run

# Verbose error messages
RUST_LOG=debug cargo test

# GDB debugger (macOS)
lldb target/debug/user_service
```

---

## Running Locally End-to-End

### Start Services (Docker)

```bash
# Start PostgreSQL, Redis, Elasticsearch
docker-compose up -d

# Verify connections
psql -h localhost -U postgres -c "SELECT version();"
redis-cli ping
curl localhost:9200
```

### Start Backend

```bash
cd backend/user-service

# Run migrations
sqlx migrate run

# Start server
cargo run --release
# Server runs on http://localhost:3000
```

### Start Frontend

```bash
cd frontend

# Development mode
npm run dev
# App runs on http://localhost:5173
```

### Test End-to-End

```bash
# Create conversation
curl -X POST http://localhost:3000/conversations \
  -H "Content-Type: application/json" \
  -d '{"type":"direct","member_ids":["user1","user2"]}'

# Send encrypted message
curl -X POST http://localhost:3000/messages \
  -H "Content-Type: application/json" \
  -d '{
    "conversation_id":"conv123",
    "content_encrypted":"..base64...",
    "content_nonce":"..base64..."
  }'

# Connect to WebSocket
websocat ws://localhost:3000/ws
```

---

## Documentation References

### Key Documents

| Document | Purpose | Location |
|----------|---------|----------|
| **spec.md** | Feature requirements | specs/002-messaging-stories-system/ |
| **plan.md** | Implementation timeline | specs/002-messaging-stories-system/ |
| **research.md** | Technology decisions | specs/002-messaging-stories-system/ |
| **data-model.md** | Database schema | specs/002-messaging-stories-system/ |
| **team-assignments.md** | Your role + tasks | specs/002-messaging-stories-system/ |

### External References

- [Tokio Async Runtime](https://tokio.rs)
- [Axum Web Framework](https://github.com/tokio-rs/axum)
- [TweetNaCl.js Documentation](https://tweetnacl.js.org/)
- [Elasticsearch Documentation](https://www.elastic.co/guide/index.html)
- [PostgreSQL JSON Functions](https://www.postgresql.org/docs/14/functions-json.html)

---

## Performance Targets & Monitoring

### SLA Targets (Week 6+)

| Metric | Target | How to Test |
|--------|--------|------------|
| Message encrypt/decrypt | <5ms | `cargo bench message_encryption` |
| WebSocket message broadcast | <50ms | Load test with 1000 concurrent |
| Search query | <200ms | Query on 1M+ messages |
| Story feed load | <100ms | Fetch 50 stories with privacy filter |
| Database query | <100ms | EXPLAIN ANALYZE on key queries |

### Monitoring Commands

```bash
# Watch database performance
EXPLAIN ANALYZE SELECT ... FROM messages WHERE conversation_id = '...';

# Monitor Redis memory
redis-cli INFO memory

# Check Elasticsearch health
curl localhost:9200/_cluster/health?pretty

# View application metrics (Prometheus)
curl localhost:9090/metrics
```

---

## Common Issues & Solutions

### Issue: "connection refused" on database

```bash
# Check PostgreSQL running
pg_isready -h localhost -p 5432

# Start in Docker if not running
docker-compose up -d postgres
```

### Issue: Compilation error on TweetNaCl import

```bash
# Update dependencies
cargo update

# Clean build
cargo clean
cargo build

# Check feature flags
# In Cargo.toml: sodiumoxide = { version = "0.2", features = ["serde"] }
```

### Issue: WebSocket connection drops

```bash
# Check heartbeat settings
# In code: Ping every 30 seconds
tokio::spawn(async {
    loop {
        tokio::time::sleep(Duration::from_secs(30)).await;
        let _ = ws.send(Message::Ping(vec![])).await;
    }
});
```

### Issue: Tests fail with "database already locked"

```bash
# Run tests single-threaded
cargo test -- --test-threads=1

# Or use separate test databases
# Configure in .env.test
DATABASE_URL=postgres://localhost/test_db
```

---

## Next Steps (Week 5)

1. **Day 1**: Read all planning artifacts + setup dev environment
2. **Days 1-2**: Phase 0 research tasks (if assigned)
3. **Days 3-5**: Phase 1 design work (schema design, API contracts)
4. **Week 6+**: Begin implementation (T211-T215)

---

## Getting Help

### Escalation Path

1. **Quick question**: Ask in #phase-7b-messaging Slack
2. **Blocker**: Mention Tech Lead (Engineer A) in Slack
3. **Red blocker**: Sync call within 4 hours
4. **Architecture question**: Discuss in weekly code review meeting

### Office Hours

- **Tech Lead (Engineer A)**: Available for 1:1s Mon-Fri, 10:00-11:00 UTC
- **Code Review**: Every PR reviewed within 24 hours

---

## Success Metrics for Week 5

By end of Week 5:
- ✅ All team members understand Phase 7B scope
- ✅ Development environment running locally
- ✅ Phase 0 research tasks complete
- ✅ Phase 1 design artifacts complete (data model, API specs)
- ✅ Ready to start T211-T215 implementation (Week 6)

