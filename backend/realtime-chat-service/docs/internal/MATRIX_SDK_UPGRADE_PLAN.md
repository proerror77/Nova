# Matrix SDK Upgrade Plan: 0.7 → 0.16

**Date**: 2025-12-09
**Status**: Planning Phase
**Blocker**: sqlx 0.7 ↔ Matrix SDK 0.16 libsqlite3-sys conflict

---

## Problem Analysis

### Current State

- **realtime-chat-service**: Uses Matrix SDK 0.7 + sqlx 0.7
- **Entire workspace**: All services use sqlx 0.7 (workspace.dependencies)
- **Conflict**: Matrix SDK 0.16 requires libsqlite3-sys 0.35, but sqlx 0.7 uses 0.26

### Impact

Upgrading Matrix SDK to 0.16 requires ONE of:

1. **Upgrade all services to sqlx 0.8** (workspace-wide breaking change)
2. **Use Cargo patch to force libsqlite3-sys version** (risky, may cause runtime issues)
3. **Separate realtime-chat-service into its own workspace** (architectural change)

---

## Strategy Comparison

### Option A: Workspace-Wide sqlx 0.8 Upgrade ⚠️

**Pros**:
- Clean resolution, no version conflicts
- Brings latest sqlx features (query builder improvements, better error messages)

**Cons**:
- **Breaks 10+ services** simultaneously
- Requires testing all services (identity, content, social, media, notification, search, etc.)
- Migration guide needed for breaking API changes
- High risk for production stability

**Breaking Changes in sqlx 0.8**:
- Pool configuration API changed
- Query macro improvements may require syntax updates
- Migration runner changes

**Estimated Effort**: 2-3 weeks (full regression testing)

---

### Option B: Cargo Patch for libsqlite3-sys ⚠️

**Pros**:
- Isolated to realtime-chat-service
- No changes to other services
- Quick implementation

**Cons**:
- **Risky**: sqlx 0.7 may break with libsqlite3-sys 0.35
- May cause runtime crashes or subtle bugs
- Not officially supported configuration

**Implementation**:

```toml
# In workspace root Cargo.toml
[patch.crates-io]
libsqlite3-sys = { version = "0.35" }
```

**Testing Required**:
- All sqlx queries in realtime-chat-service
- Connection pooling stability
- Migration runner
- Production load testing

**Estimated Effort**: 3-5 days (thorough testing)

---

### Option C: Separate Workspace for realtime-chat-service ✅ RECOMMENDED

**Pros**:
- **Zero risk to other services**
- Full freedom to use Matrix SDK 0.16 + sqlx 0.8
- Clear separation of concerns (E2EE messaging is unique)
- Can move fast without workspace-wide coordination

**Cons**:
- Requires restructuring build system
- Shared libraries need to be duplicated or versioned separately
- Slightly more complex CI/CD setup

**Architecture**:

```
nova/backend/
├── Cargo.toml (main workspace - sqlx 0.7)
│   ├── identity-service/
│   ├── content-service/
│   ├── social-service/
│   ├── ...
│   └── libs/ (shared libs on sqlx 0.7)
│
└── realtime-chat-service/ (SEPARATE workspace - sqlx 0.8)
    ├── Cargo.toml (independent)
    ├── src/
    ├── tests/
    └── libs/ (local copies or git submodules)
```

**Shared Libraries Strategy**:

1. **Duplicate for now** (libs/error-types, libs/grpc-metrics, etc.)
   - Copy into realtime-chat-service/libs/
   - Accept temporary duplication

2. **Future**: Move to published crates or git dependencies
   - Publish to private registry
   - Use git dependencies with version tags

**Estimated Effort**: 1 week (restructure + testing)

---

## Recommended Approach: Option C (Phased)

### Phase 1: Prepare Separation (1-2 days)

1. **Audit shared library dependencies**
   ```bash
   cd realtime-chat-service
   grep "path = \"../libs/" Cargo.toml
   ```

2. **Copy required shared libraries locally**
   ```bash
   mkdir realtime-chat-service/libs
   cp -r ../libs/error-types realtime-chat-service/libs/
   cp -r ../libs/grpc-metrics realtime-chat-service/libs/
   # ... other required libs
   ```

3. **Update Cargo.toml paths**
   ```toml
   error-types = { path = "libs/error-types" }  # Changed from "../libs/..."
   ```

4. **Test compilation**
   ```bash
   cd realtime-chat-service
   cargo check
   ```

### Phase 2: Upgrade Matrix SDK + sqlx (2-3 days)

1. **Update Cargo.toml**
   ```toml
   matrix-sdk = { version = "0.16", features = ["e2e-encryption", "sso-login"] }
   sqlx = { version = "0.8", features = ["runtime-tokio-rustls", "postgres", "macros", "uuid", "chrono", "migrate"] }
   ```

2. **Fix API breaking changes** (documented below)

3. **Update VoIP implementation**
   - Replace placeholder `send_custom_event()` with real implementation
   - Enable VoIP event receiving in sync loop

4. **Test thoroughly**
   - Unit tests
   - Integration tests with Matrix homeserver
   - Load testing

### Phase 3: CI/CD Updates (1 day)

1. **Update GitHub Actions**
   - Add separate build job for realtime-chat-service
   - Update deployment scripts

2. **Update Docker builds**
   - Separate Dockerfile or multi-stage build
   - Update docker-compose.yml

3. **Update monitoring**
   - Ensure metrics still work with separated service

---

## Matrix SDK 0.7 → 0.16 Breaking Changes

### 1. Client Creation

**0.7**:
```rust
let client = Client::builder()
    .homeserver_url(&config.homeserver_url)
    .build()
    .await?;
```

**0.16**:
```rust
use matrix_sdk::Client;

let client = Client::builder()
    .homeserver_url(&config.homeserver_url)
    .build()
    .await?;
```

*(API mostly the same, but import paths changed)*

### 2. Session Restoration

**0.7** (broken in our code):
```rust
// TODO: Not implemented correctly in 0.7
warn!("Matrix client session restoration not fully implemented");
```

**0.16**:
```rust
use matrix_sdk::matrix_auth::MatrixSession;

client.matrix_auth()
    .restore_session(session)
    .await?;
```

### 3. Event Handling

**0.7** (limited):
```rust
client.add_event_handler(|ev: SyncRoomMessageEvent, room: Room| {
    // Only works for built-in event types
});
```

**0.16** (full support):
```rust
use matrix_sdk::ruma::events::AnySyncMessageLikeEvent;

client.add_event_handler(|ev: AnySyncMessageLikeEvent, room: Room| async move {
    match ev.event_type().as_str() {
        "m.call.invite" => handle_invite(ev, room).await,
        "m.call.answer" => handle_answer(ev, room).await,
        _ => {}
    }
});
```

### 4. Custom Event Sending

**0.7** (placeholder):
```rust
async fn send_custom_event(&self, room_id: &RoomId, event_type: &str, content: Value) -> Result<String> {
    // Placeholder implementation
    Ok(format!("$placeholder_{}", Uuid::new_v4()))
}
```

**0.16** (real implementation):
```rust
use matrix_sdk::ruma::events::AnyMessageLikeEventContent;

async fn send_custom_event(&self, room_id: &RoomId, event_type: &str, content: Value) -> Result<String> {
    let room = self.client.get_room(room_id).ok_or(AppError::NotFound)?;

    let raw_content = Raw::from_json(serde_json::to_value(&content)?);
    let response = room.send_raw(event_type, raw_content).await?;

    Ok(response.event_id.to_string())
}
```

### 5. Sync Settings

**0.7**:
```rust
use matrix_sdk::config::SyncSettings;

let settings = SyncSettings::default()
    .timeout(std::time::Duration::from_secs(30));
```

**0.16**:
```rust
use matrix_sdk::config::SyncSettings;

let settings = SyncSettings::new()
    .timeout(std::time::Duration::from_secs(30));
```

---

## Testing Strategy

### Unit Tests

- [x] VoIP event parsing (already passing in 0.7)
- [ ] Real Matrix event sending (SDK 0.16)
- [ ] Real Matrix event receiving (SDK 0.16)
- [ ] Session restoration
- [ ] Room creation

### Integration Tests

1. **Matrix Homeserver Setup**
   ```bash
   docker run -d \
     --name synapse \
     -p 8008:8008 \
     matrixdotorg/synapse:latest
   ```

2. **Test Scenarios**
   - Create account
   - Login with access token
   - Create E2EE room
   - Send m.call.invite
   - Receive m.call.answer
   - Verify encryption keys

3. **Element Client Interop**
   - Initiate call from Nova → Receive in Element
   - Initiate call from Element → Receive in Nova
   - Verify SDP exchange
   - Test ICE candidates
   - Test hangup

### Load Testing

- 100 concurrent calls
- 1000 messages/second
- Connection pool stability
- Memory leak detection

---

## Rollout Plan

### Week 1: Preparation

- [ ] Audit shared library dependencies
- [ ] Copy libraries to realtime-chat-service/libs/
- [ ] Update Cargo.toml paths
- [ ] Test current build (pre-upgrade)

### Week 2: Upgrade Execution

- [ ] Upgrade Matrix SDK to 0.16
- [ ] Upgrade sqlx to 0.8
- [ ] Fix API breaking changes
- [ ] Implement real VoIP event sending/receiving
- [ ] Update tests

### Week 3: Testing & Validation

- [ ] Unit tests passing
- [ ] Integration tests with Synapse
- [ ] Element client interop
- [ ] Load testing
- [ ] Security audit

### Week 4: Production Deployment

- [ ] Staging deployment
- [ ] Beta user testing
- [ ] Gradual rollout (10% → 50% → 100%)
- [ ] Monitor metrics

---

## Risks & Mitigation

### Risk 1: Shared Library Version Drift

**Risk**: Local copies diverge from main workspace

**Mitigation**:
- Document which version was copied
- Plan to extract to published crates in Q1 2026
- Regular sync checks

### Risk 2: API Incompatibilities

**Risk**: Matrix SDK 0.16 API changes break existing code

**Mitigation**:
- Thorough testing before merge
- Feature flag for Matrix VoIP (can disable if issues)
- Rollback plan ready

### Risk 3: Production Stability

**Risk**: New bugs in production

**Mitigation**:
- Extensive staging testing
- Gradual rollout
- Real-time monitoring
- Immediate rollback capability

---

## Decision

**Proceeding with Option C: Separate Workspace**

**Rationale**:
- Lowest risk to other services
- Enables Matrix VoIP features without blocking
- Clear architectural boundary for E2EE service
- Can move fast independently

**Next Step**: Begin Phase 1 (Preparation)

---

## References

- [Matrix SDK 0.16 Migration Guide](https://github.com/matrix-org/matrix-rust-sdk/releases/tag/matrix-sdk-0.16.0)
- [sqlx 0.8 Changelog](https://github.com/launchbadge/sqlx/blob/main/CHANGELOG.md)
- [CALL_SERVICE_MATRIX_INTEGRATION.md](./CALL_SERVICE_MATRIX_INTEGRATION.md)
