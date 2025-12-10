# Matrix VoIP Integration Design

**Status**: 🚧 IN DEVELOPMENT (SDK 0.7 workaround)
**Version**: 1.1
**Last Updated**: 2025-12-09
**Matrix SDK**: 0.7.1 (downgraded from 0.16 due to libsqlite3-sys conflict)
**Target**: Full E2EE video/voice calling via Matrix

---

## ⚠️ IMPORTANT: SDK 0.7 Limitations

We are currently using Matrix SDK 0.7.1 instead of 0.16 due to an unresolved dependency conflict:
- matrix-sdk 0.16 requires libsqlite3-sys 0.35 (via matrix-sdk-sqlite)
- identity-service requires sqlx 0.7 which uses libsqlite3-sys 0.26
- Cargo does not allow linking two versions of the same native library

**Workarounds implemented**:
1. Manual VoIP event construction using JSON (no typed CallInviteEventContent)
2. Custom event sending via Matrix HTTP API (placeholder implementation)
3. Manual event parsing in event handlers

**Future upgrade path** (see bottom of document):
- Option A: Upgrade identity-service to sqlx 0.8+
- Option B: Separate realtime-chat-service into its own workspace
- Option C: Wait for Matrix SDK to remove hard sqlite dependency

---

## Overview

This document describes the integration of Matrix VoIP into Nova's realtime-chat-service, enabling End-to-End Encrypted (E2EE) video and voice calls through the Matrix protocol.

### Goals

1. ✅ **E2EE Calls** - All calls encrypted end-to-end via Matrix
2. ✅ **WebRTC Integration** - Leverage existing Nova WebRTC infrastructure
3. ✅ **Federation Support** - Calls work across Matrix homeservers
4. ✅ **Backward Compatibility** - Maintain existing call functionality during migration

### Non-Goals

- ❌ Breaking existing Nova WebRTC calls
- ❌ Immediate deprecation of Nova signaling
- ❌ Client-side changes (backend only for now)

---

## Matrix VoIP Event Types

### Core Events (MSC 2746)

Matrix VoIP uses the following event types for call signaling:

#### 1. `m.call.invite`

**Purpose**: Initiate a new call

**Content**:
```json
{
  "call_id": "unique-call-id",
  "party_id": "unique-party-id",
  "version": "1",
  "lifetime": 60000,
  "offer": {
    "type": "offer",
    "sdp": "v=0\r\no=- ... (WebRTC SDP)"
  },
  "invitee": "@user:homeserver" // Optional for 1:1 calls
}
```

#### 2. `m.call.answer`

**Purpose**: Accept an incoming call

**Content**:
```json
{
  "call_id": "unique-call-id",
  "party_id": "unique-party-id",
  "version": "1",
  "answer": {
    "type": "answer",
    "sdp": "v=0\r\no=- ... (WebRTC SDP)"
  }
}
```

#### 3. `m.call.candidates`

**Purpose**: Exchange ICE candidates

**Content**:
```json
{
  "call_id": "unique-call-id",
  "party_id": "unique-party-id",
  "version": "1",
  "candidates": [
    {
      "candidate": "candidate:... (ICE candidate)",
      "sdpMid": "0",
      "sdpMLineIndex": 0
    }
  ]
}
```

#### 4. `m.call.hangup`

**Purpose**: End a call

**Content**:
```json
{
  "call_id": "unique-call-id",
  "party_id": "unique-party-id",
  "version": "1",
  "reason": "user_hangup" // or "ice_failed", "invite_timeout", etc.
}
```

#### 5. `m.call.reject`

**Purpose**: Reject an incoming call (VoIP v1)

**Content**:
```json
{
  "call_id": "unique-call-id",
  "party_id": "unique-party-id",
  "version": "1"
}
```

---

## Architecture Design

### High-Level Flow

```
┌──────────────┐                    ┌──────────────┐
│  Nova Client │                    │  Nova Client │
│   (Alice)    │                    │    (Bob)     │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       │ 1. POST /calls/initiate           │
       ▼                                   │
┌─────────────────────────────────────────┴────┐
│         realtime-chat-service                │
│  ┌──────────────────────────────────────┐   │
│  │  CallService (existing)              │   │
│  └─────────┬────────────────────────────┘   │
│            │                                 │
│            ├─ 2. Store in Nova DB            │
│            │                                 │
│  ┌─────────▼────────────────────────────┐   │
│  │  MatrixVoipService (NEW)             │   │
│  │  - send_invite()                     │   │
│  │  - send_answer()                     │   │
│  │  - send_candidates()                 │   │
│  │  - send_hangup()                     │   │
│  └─────────┬────────────────────────────┘   │
│            │                                 │
│            ├─ 3. Send m.call.invite          │
│            │                                 │
└────────────┼─────────────────────────────────┘
             │
             ▼
    ┌────────────────┐
    │ Matrix Synapse │
    │   (E2EE VoIP)  │
    └────────┬───────┘
             │
             │ 4. Sync receives m.call.invite
             ▼
┌─────────────────────────────────────────────┐
│  MatrixVoipEventHandler (NEW)               │
│  - handle_call_invite()                     │
│  - handle_call_answer()                     │
│  - handle_call_candidates()                 │
│  - handle_call_hangup()                     │
└─────────┬───────────────────────────────────┘
          │
          │ 5. Broadcast via WebSocket
          ▼
    ┌──────────────┐
    │  Bob's WS    │
    └──────────────┘
```

### Component Breakdown

#### 1. **MatrixVoipService** (NEW)

**File**: `src/services/matrix_voip_service.rs`

**Responsibilities**:
- Send Matrix VoIP events (invite/answer/candidates/hangup)
- Map Nova call data to Matrix events
- Handle Matrix-specific call state

**Key Methods**:
```rust
pub struct MatrixVoipService {
    matrix_client: Arc<MatrixClient>,
}

impl MatrixVoipService {
    // Send call invite
    pub async fn send_invite(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        sdp_offer: &str,
        invitee: Option<&UserId>,
    ) -> Result<String, AppError>;

    // Send call answer
    pub async fn send_answer(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        sdp_answer: &str,
    ) -> Result<String, AppError>;

    // Send ICE candidates
    pub async fn send_candidates(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        candidates: Vec<IceCandidate>,
    ) -> Result<(), AppError>;

    // Send hangup
    pub async fn send_hangup(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        reason: &str,
    ) -> Result<(), AppError>;
}
```

#### 2. **MatrixVoipEventHandler** (NEW)

**File**: `src/services/matrix_voip_event_handler.rs`

**Responsibilities**:
- Handle incoming Matrix VoIP events from sync loop
- Update Nova call state
- Broadcast to WebSocket clients

**Key Methods**:
```rust
pub async fn handle_call_invite(
    db: &Pool<Postgres>,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    room: Room,
    event: CallInviteEvent,
) -> Result<(), AppError>;

pub async fn handle_call_answer(
    db: &Pool<Postgres>,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    room: Room,
    event: CallAnswerEvent,
) -> Result<(), AppError>;

pub async fn handle_call_candidates(
    db: &Pool<Postgres>,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    room: Room,
    event: CallCandidatesEvent,
) -> Result<(), AppError>;

pub async fn handle_call_hangup(
    db: &Pool<Postgres>,
    registry: &Arc<ConnectionRegistry>,
    redis: &Arc<RedisClient>,
    room: Room,
    event: CallHangupEvent,
) -> Result<(), AppError>;
```

#### 3. **CallService Integration** (MODIFIED)

**File**: `src/services/call_service.rs`

**Changes**:
- Add Matrix VoIP service dependency
- Send Matrix events alongside Nova WebSocket events
- Graceful degradation if Matrix fails

**Example**:
```rust
pub async fn initiate_call_with_matrix(
    db: &Pool<Postgres>,
    matrix_voip: Option<Arc<MatrixVoipService>>,
    conversation_id: Uuid,
    initiator_id: Uuid,
    sdp_offer: &str,
) -> Result<CallRow, AppError> {
    // 1. Create call in Nova DB (existing logic)
    let call = Self::initiate_call(db, conversation_id, initiator_id, sdp_offer).await?;

    // 2. Send Matrix m.call.invite (new)
    if let Some(voip) = matrix_voip {
        let room_id = get_or_create_room(db, conversation_id).await?;
        let party_id = format!("nova-{}", initiator_id);

        if let Err(e) = voip.send_invite(
            &room_id,
            call.id,
            &party_id,
            sdp_offer,
            None,
        ).await {
            tracing::error!(
                error = %e,
                call_id = %call.id,
                "Failed to send Matrix call invite"
            );
            // Continue - Matrix failure doesn't block call
        }
    }

    Ok(call)
}
```

---

## Database Schema Changes

### New Column: `calls.matrix_event_id`

```sql
ALTER TABLE calls
ADD COLUMN matrix_invite_event_id TEXT,
ADD COLUMN matrix_party_id TEXT;

CREATE INDEX idx_calls_matrix_invite_event_id ON calls(matrix_invite_event_id);
```

**Purpose**:
- Link Nova calls to Matrix VoIP events
- Enable lookup for incoming Matrix events
- Track party_id for session management

---

## WebSocket Event Extensions

### New Events

#### CallInviteViaMatrix
```json
{
  "type": "CallInviteViaMatrix",
  "call_id": "uuid",
  "conversation_id": "uuid",
  "initiator_id": "uuid",
  "sdp_offer": "...",
  "matrix_event_id": "...",
  "party_id": "..."
}
```

#### CallAnswerViaMatrix
```json
{
  "type": "CallAnswerViaMatrix",
  "call_id": "uuid",
  "participant_id": "uuid",
  "sdp_answer": "...",
  "matrix_event_id": "..."
}
```

#### CallCandidatesViaMatrix
```json
{
  "type": "CallCandidatesViaMatrix",
  "call_id": "uuid",
  "participant_id": "uuid",
  "candidates": [
    {
      "candidate": "...",
      "sdpMid": "0",
      "sdpMLineIndex": 0
    }
  ]
}
```

---

## Configuration

### Environment Variables

```bash
# Existing Matrix config
MATRIX_ENABLED=true
MATRIX_HOMESERVER_URL=http://matrix-synapse:8008
MATRIX_SERVICE_USER=@nova-service:staging.nova.internal
MATRIX_ACCESS_TOKEN=syt_...

# VoIP-specific config (NEW)
MATRIX_VOIP_ENABLED=true
MATRIX_VOIP_VERSION=1                # VoIP protocol version

# TURN/STUN servers (NEW)
TURN_SERVER_URL=turn:turn.nova.internal:3478
TURN_USERNAME=nova
TURN_PASSWORD=secret
STUN_SERVER_URL=stun:stun.nova.internal:3478
```

### Rust Config

```rust
#[derive(Clone, Debug)]
pub struct MatrixVoipConfig {
    pub enabled: bool,
    pub version: String,
    pub turn_url: Option<String>,
    pub turn_username: Option<String>,
    pub turn_password: Option<String>,
    pub stun_url: Option<String>,
}
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Create MatrixVoipService skeleton
- [ ] Implement send_invite(), send_answer()
- [ ] Add matrix_event_id to calls table
- [ ] Update CallService to call Matrix on initiate

### Phase 2: ICE & Hangup (Week 1-2)
- [ ] Implement send_candidates()
- [ ] Implement send_hangup()
- [ ] Handle ICE candidate collection from Nova

### Phase 3: Event Handling (Week 2)
- [ ] Create MatrixVoipEventHandler
- [ ] Register VoIP event handlers in sync loop
- [ ] Handle incoming m.call.invite
- [ ] Handle incoming m.call.answer
- [ ] Handle incoming m.call.candidates
- [ ] Handle incoming m.call.hangup

### Phase 4: TURN/STUN (Week 2-3)
- [ ] Implement TURN/STUN server configuration
- [ ] Return ICE servers in GET /calls/ice_servers
- [ ] Test NAT traversal

### Phase 5: Testing & Documentation (Week 3)
- [ ] Write integration tests
- [ ] Test 1:1 calls
- [ ] Test group calls (future)
- [ ] Update API documentation
- [ ] Create deployment guide

---

## API Changes

### No Breaking Changes

All existing endpoints remain functional. Matrix VoIP is opt-in via configuration.

### Enhanced Responses

#### POST /calls/initiate

**Before**:
```json
{
  "id": "uuid",
  "status": "ringing",
  "created_at": "..."
}
```

**After (with Matrix enabled)**:
```json
{
  "id": "uuid",
  "status": "ringing",
  "created_at": "...",
  "matrix": {
    "event_id": "$eventid",
    "party_id": "nova-uuid",
    "room_id": "!roomid:homeserver"
  }
}
```

---

## Testing Strategy

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    #[tokio::test]
    async fn test_send_invite_creates_matrix_event() {
        let voip = MatrixVoipService::new(mock_client());
        let result = voip.send_invite(...).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_handle_call_invite_creates_nova_call() {
        // Mock Matrix event
        let event = mock_call_invite_event();
        let result = handle_call_invite(..., event).await;
        assert!(result.is_ok());
    }
}
```

### Integration Tests

1. **End-to-End Call Flow**
   - Initiate call → Matrix invite sent
   - Answer call → Matrix answer sent
   - Exchange ICE → Matrix candidates sent
   - Hangup → Matrix hangup sent

2. **Matrix to Nova Flow**
   - Receive Matrix invite → Nova call created
   - Receive Matrix answer → Nova call answered
   - Receive Matrix hangup → Nova call ended

3. **Failure Scenarios**
   - Matrix homeserver down → Calls still work via WebSocket
   - Invalid Matrix event → Logged, ignored
   - Duplicate events → Idempotency check

---

## Security Considerations

### 1. E2EE Verification

- Matrix VoIP events are sent in E2EE rooms
- SDP and ICE candidates encrypted end-to-end
- No plaintext signaling exposed to homeserver

### 2. Access Control

- Verify caller is participant in conversation
- Reject calls from non-participants
- Rate limit call initiation

### 3. TURN/STUN Credentials

- Generate time-limited TURN credentials
- Rotate TURN passwords regularly
- Use different credentials per call

---

## Migration Strategy

### Dual-Mode Operation

During migration, support both Nova WebRTC and Matrix VoIP:

1. **Nova WebSocket (Legacy)**
   - Existing clients continue to work
   - Gradual deprecation over 6 months

2. **Matrix VoIP (New)**
   - New clients use Matrix signaling
   - E2EE benefits

3. **Bridge Mode**
   - Calls between old and new clients
   - Convert Matrix events to WebSocket and vice versa

---

## Performance Considerations

### 1. Event Throughput

- Matrix events sent asynchronously
- Don't block call initiation on Matrix send
- Queue ICE candidates, batch send

### 2. Database Load

- Index on matrix_event_id for fast lookups
- Cache room_id mappings in Redis

### 3. WebSocket Load

- Only broadcast to active participants
- Filter duplicate events

---

## Monitoring & Observability

### Metrics

```
matrix_voip_invite_sent_total
matrix_voip_invite_failed_total
matrix_voip_answer_received_total
matrix_voip_ice_candidates_sent_total
matrix_voip_hangup_sent_total
matrix_voip_call_duration_seconds
```

### Logs

```
INFO  matrix_voip.send_invite call_id=... room_id=... event_id=...
ERROR matrix_voip.send_failed call_id=... error=...
DEBUG matrix_voip.ice_candidate call_id=... candidate=...
```

---

## References

### Matrix Specifications
- [Matrix VoIP Specification](https://spec.matrix.org/latest/)
- [MSC 2746: Improved VoIP Signalling](https://github.com/matrix-org/matrix-spec-proposals/pull/2746)
- [MSC 3401: Group VoIP](https://github.com/matrix-org/matrix-spec-proposals/blob/matthew/group-voip/proposals/3401-group-voip.md)

### Matrix Rust SDK
- [matrix-sdk VoIP events](https://matrix-org.github.io/matrix-rust-sdk/matrix_sdk_base/ruma/events/call/index.html)
- [CallInviteEventContent](https://matrix-org.github.io/matrix-rust-sdk/matrix_sdk_base/ruma/events/call/invite/struct.CallInviteEventContent.html)
- [CallAnswerEventContent](https://matrix-org.github.io/matrix-rust-sdk/matrix_sdk_base/ruma/events/call/answer/struct.CallAnswerEventContent.html)

### WebRTC Resources
- [WebRTC Specification](https://www.w3.org/TR/webrtc/)
- [SDP Format](https://datatracker.ietf.org/doc/html/rfc4566)
- [ICE Protocol](https://datatracker.ietf.org/doc/html/rfc8445)

---

**Status**: Phase 1 in progress (SDK 0.7 workaround)
**Next Steps**: Complete send_custom_event() implementation

---

## SDK 0.16 Upgrade Path

### Problem Summary

**Root cause**: Native library linking conflict
- matrix-sdk 0.16 → matrix-sdk-sqlite 0.16 → rusqlite 0.37 → libsqlite3-sys 0.35
- identity-service → sqlx 0.7 → sqlx-sqlite 0.7 → libsqlite3-sys 0.26
- Cargo error: "Only one package in the dependency graph may specify the same links value"

**Why `default-features = false` doesn't help**:
- matrix-sdk 0.16's workspace structure automatically includes matrix-sdk-sqlite
- Even without the `sqlite` feature, the dependency is pulled in by e2e-encryption feature's conditional dependencies

### Option A: Upgrade sqlx to 0.8+ (Recommended)

**Pros**:
- Clean solution - resolves root cause
- sqlx 0.8 uses libsqlite3-sys 0.30+ (more compatible)
- Benefits all services with newer sqlx features

**Cons**:
- Requires testing all services using sqlx (identity-service, etc.)
- Migration effort: ~1-2 days
- Potential API breaking changes

**Steps**:
1. Update workspace Cargo.toml: `sqlx = { version = "0.8", features = [...] }`
2. Fix compilation errors in identity-service and other services
3. Run integration tests for all affected services
4. Update realtime-chat-service to matrix-sdk 0.16
5. Complete VoIP implementation with typed event APIs

### Option B: Separate realtime-chat-service workspace

**Pros**:
- Complete dependency isolation
- Can use any matrix-sdk version
- No impact on other services

**Cons**:
- Complicates CI/CD (multiple workspaces)
- Shared library versioning becomes manual
- Workspace benefits lost (unified dependency management)

**Steps**:
1. Create new Cargo.toml in realtime-chat-service root
2. Move shared libs to git submodules or published crates
3. Update CI/CD to build both workspaces
4. Update deployment scripts

### Option C: Wait for upstream fixes

**Pros**:
- Zero effort
- Clean long-term solution

**Cons**:
- Timeline uncertain
- Blocks VoIP development
- May never happen (sqlite is core to matrix-sdk)

**Tracking**:
- Matrix SDK issue: (to be filed)
- sqlx compatibility: (monitor releases)

### Current Workaround (SDK 0.7)

**What works**:
- E2EE messaging (existing functionality)
- Manual VoIP event construction (this PR)
- Basic Matrix sync

**What doesn't work**:
- Typed VoIP events (using JSON instead)
- Session restoration (documented TODO)
- Message editing (using "[EDITED]" prefix)

**Migration plan when upgrading**:
1. Replace manual JSON construction with typed events
2. Implement proper send_custom_event() using room.send()
3. Update event handlers to use typed parsing
4. Remove placeholder event IDs
5. Test full VoIP flow end-to-end

---

**Recommendation**: Upgrade to Option A (sqlx 0.8) after completing MVP with SDK 0.7
