# CallService Matrix VoIP Integration Plan

**Status**: 🚧 IN PROGRESS
**Version**: 1.0
**Date**: 2025-12-09

## Current State

`CallService` is a unit struct with static methods:
- `initiate_call()` - Creates call session in DB
- `answer_call()` - Adds participant, updates status
- `end_call()` - Marks call as ended
- Other methods for participant management, ICE candidates, etc.

**Limitation**: No access to MatrixVoipService or MatrixClient

## Integration Strategy

### Phase 1: Non-Breaking Additions (MVP) ✅ CURRENT

Add **optional** Matrix integration without breaking existing functionality:

1. **Keep existing static methods unchanged**
   - All current WebSocket-based signaling still works
   - Zero breaking changes to existing code

2. **Add new Matrix-aware methods**
   - `initiate_call_with_matrix()` - Dual-write to DB + Matrix
   - `answer_call_with_matrix()` - Dual-write to DB + Matrix
   - `end_call_with_matrix()` - Dual-write to DB + Matrix

3. **Database changes** (already done)
   - Added `matrix_invite_event_id` and `matrix_party_id` to `call_sessions`
   - Added `matrix_answer_event_id` and `matrix_party_id` to `call_participants`
   - Fields are **nullable** - existing calls don't break

### Phase 2: Refactor to Service Instance (Future)

Convert CallService to instance-based:

```rust
pub struct CallService {
    db: Pool<Postgres>,
    matrix_voip_service: Option<Arc<MatrixVoipService>>,
    matrix_client: Option<Arc<MatrixClient>>,
}

impl CallService {
    pub fn new(
        db: Pool<Postgres>,
        matrix_voip_service: Option<Arc<MatrixVoipService>>,
        matrix_client: Option<Arc<MatrixClient>>,
    ) -> Self {
        Self {
            db,
            matrix_voip_service,
            matrix_client,
        }
    }

    pub async fn initiate_call(&self, ...) -> Result<Uuid, AppError> {
        // DB operation
        let call_id = self.db_create_call(...).await?;

        // Matrix operation (if enabled)
        if let Some(matrix_service) = &self.matrix_voip_service {
            let event_id = matrix_service.send_invite(...).await?;
            self.db_update_matrix_event_id(call_id, event_id).await?;
        }

        Ok(call_id)
    }
}
```

**Breaking Change**: All callers need to instantiate CallService

## Phase 1 Implementation (Current)

### New Methods to Add

#### 1. `initiate_call_with_matrix()`

```rust
pub async fn initiate_call_with_matrix(
    db: &Pool<Postgres>,
    matrix_voip_service: &MatrixVoipService,
    matrix_client: &MatrixClient,
    conversation_id: Uuid,
    initiator_id: Uuid,
    initiator_sdp: &str,
    call_type: &str,
    max_participants: i32,
) -> Result<Uuid, AppError>
```

**Steps**:
1. Call existing `initiate_call()` to create DB record
2. Get Matrix room_id from conversation_id (via matrix_client)
3. Generate Matrix party_id: `format!("nova-{}", Uuid::new_v4())`
4. Send m.call.invite via MatrixVoipService
5. Update call_sessions with matrix_invite_event_id and matrix_party_id
6. Return call_id

#### 2. `answer_call_with_matrix()`

```rust
pub async fn answer_call_with_matrix(
    db: &Pool<Postgres>,
    matrix_voip_service: &MatrixVoipService,
    matrix_client: &MatrixClient,
    call_id: Uuid,
    answerer_id: Uuid,
    answer_sdp: &str,
) -> Result<Uuid, AppError>
```

**Steps**:
1. Get call's matrix_party_id from DB
2. Call existing `answer_call()` to add participant
3. Generate answerer's party_id: `format!("nova-{}", Uuid::new_v4())`
4. Send m.call.answer via MatrixVoipService
5. Update call_participants with matrix_answer_event_id and matrix_party_id
6. Return participant_id

#### 3. `end_call_with_matrix()`

```rust
pub async fn end_call_with_matrix(
    db: &Pool<Postgres>,
    matrix_voip_service: &MatrixVoipService,
    matrix_client: &MatrixClient,
    call_id: Uuid,
    reason: &str,
) -> Result<(), AppError>
```

**Steps**:
1. Get call's matrix_party_id from DB
2. Send m.call.hangup via MatrixVoipService
3. Call existing `end_call()` to update DB
4. Return Ok

### Matrix Party ID Format

`nova-{uuid}` where uuid is generated per-session:
- One party_id for call initiator (stored in call_sessions)
- One party_id per participant (stored in call_participants)

**Example**: `nova-550e8400-e29b-41d4-a716-446655440000`

### Error Handling

- **Matrix operation fails**: Log warning, continue with DB-only operation
- **DB operation fails**: Return error immediately (don't send Matrix events)
- **Principle**: Never fail user-facing operations due to Matrix issues

### Testing Strategy

1. Unit tests for new methods (mocked Matrix services)
2. Integration tests with test Matrix homeserver
3. Manual testing with Element client

## Database Schema (Already Implemented)

```sql
-- call_sessions
matrix_invite_event_id TEXT NULL
matrix_party_id VARCHAR(100) NULL

-- call_participants
matrix_answer_event_id TEXT NULL
matrix_party_id VARCHAR(100) NULL
```

## Future Enhancements (Phase 3+)

1. **ICE Candidate Relay**
   - Store candidates in DB or relay via WebSocket
   - Send via Matrix m.call.candidates

2. **Matrix Event Sync**
   - Listen to Matrix sync loop
   - Process incoming m.call.* events
   - Update DB and notify participants

3. **TURN/STUN Configuration**
   - Add configuration table
   - Pass TURN servers in m.call.invite

4. **Call Recording Metadata**
   - Store Matrix event IDs for audit trail
   - Enable Matrix-based call history

## Rollout Plan

1. ✅ Create MatrixVoipService and MatrixVoipEventHandler
2. ✅ Add database migration
3. ✅ Implement `*_with_matrix()` methods in CallService
4. ✅ Add VoipConfig for TURN/STUN integration
5. ✅ Register VoIP event handler (placeholder in SDK 0.7)
6. ✅ Create integration test structure
7. ✅ Implement `get_ice_servers` endpoint (using VoipConfig)
8. ⏳ Test with curl/postman
9. ⏳ Update routes to use Matrix methods (behind feature flag)
10. ⏳ Production rollout (opt-in initially)

## Current Status (2025-12-09)

**Phase 1 Implementation: COMPLETE ✅**

All core components implemented with SDK 0.7 workarounds:

### Implemented Components

1. **MatrixVoipService** (`src/services/matrix_voip_service.rs`)
   - `send_invite()`, `send_answer()`, `send_candidates()`, `send_hangup()`
   - Uses placeholder `send_custom_event()` for SDK 0.7
   - All methods compile and log correctly

2. **MatrixVoipEventHandler** (`src/handlers/matrix_voip_event_handler.rs`)
   - Parses m.call.invite, m.call.answer, m.call.candidates, m.call.hangup
   - Manual JSON deserialization for Raw<Value> events
   - Unit tests for event parsing

3. **CallService Integration** (`src/services/call_service.rs`)
   - `initiate_call_with_matrix()` - Lines 572-669
   - `answer_call_with_matrix()` - Lines 691-791
   - `end_call_with_matrix()` - Lines 809-890
   - Non-blocking error handling (Matrix failures don't break calls)

4. **Database Schema** (`migrations/0026_add_matrix_voip_fields.sql`)
   - `call_sessions`: matrix_invite_event_id, matrix_party_id
   - `call_participants`: matrix_answer_event_id, matrix_party_id
   - Indexed and constrained for consistency

5. **VoipConfig** (`src/config.rs`)
   - Aggregates ICE servers + Matrix config
   - `ice_servers_json()` for WebRTC configuration
   - Ready for TURN/STUN integration in m.call.invite

6. **Event Registration** (`src/services/matrix_client.rs`)
   - `register_voip_handler()` added (placeholder for SDK 0.7)
   - Documents SDK 0.16 upgrade path

7. **Integration Tests** (`tests/voip_integration_test.rs`)
   - Test structure for full VoIP flow
   - Tests marked as `#[ignore]` until database setup ready

### SDK 0.7 Limitations (Documented)

- **Event Sending**: Placeholder returns `$placeholder_{uuid}` instead of real Matrix events
- **Event Receiving**: Cannot hook into sync loop for custom event types
- **Workaround**: WebSocket signaling works independently; Matrix integration deferred

### Next Steps

1. **Upgrade to Matrix SDK 0.16** (requires sqlx 0.8 or workspace separation)
   - Enable real `send_custom_event()` using room.send_raw()
   - Enable real VoIP event receiving in sync loop
   - Test with actual Matrix homeserver

2. **Production Testing**
   - Setup test Matrix homeserver
   - Test call flow with Element client
   - Verify E2EE encryption works

3. **Route Integration** (Detailed Plan Below)
   - Add Matrix-enabled endpoints (e.g., `/calls/matrix/initiate`)
   - Feature flag for gradual rollout
   - Metrics and monitoring

## Matrix Route Integration Plan

### Current State (2025-12-09)

**Existing Routes** (`src/routes/calls.rs`):
- ✅ `/calls/initiate` - WebSocket-based call initiation
- ✅ `/calls/answer` - WebSocket-based call answer
- ✅ `/calls/end` - WebSocket-based call termination
- ✅ `/calls/ice-servers` - **NEW**: Returns TURN/STUN configuration from VoipConfig
- ✅ `/calls/join`, `/calls/leave`, `/calls/participants`, `/calls/history` - Other endpoints

**New Methods Available**:
- `CallService::initiate_call_with_matrix()` - Dual-write to DB + Matrix
- `CallService::answer_call_with_matrix()` - Dual-write to DB + Matrix
- `CallService::end_call_with_matrix()` - Dual-write to DB + Matrix

### Strategy: Gradual Migration with Feature Flags

#### Phase 1: Feature-Flagged Matrix Endpoints (Current Phase)

**Goal**: Add optional Matrix-enabled endpoints without breaking existing functionality

**Implementation Plan**:

1. **Add Feature Flag in Config** (`src/config.rs`)
   ```rust
   pub struct MatrixConfig {
       pub enabled: bool,  // Already exists
       pub voip_enabled: bool,  // NEW: Matrix VoIP signaling toggle
       // ... existing fields
   }
   ```

2. **Create Matrix-Specific Routes** (`src/routes/calls_matrix.rs` - NEW FILE)
   ```rust
   /// POST /calls/matrix/initiate - Initiate call with Matrix E2EE signaling
   #[post("/calls/matrix/initiate")]
   pub async fn initiate_call_matrix(
       state: web::Data<AppState>,
       user: User,
       req: web::Json<InitiateCallRequest>,
   ) -> Result<HttpResponse, AppError> {
       // Check if Matrix VoIP is enabled
       if !state.config.matrix.voip_enabled {
           return Err(AppError::Config("Matrix VoIP not enabled".into()));
       }

       let call_id = CallService::initiate_call_with_matrix(
           &state.db,
           &state.matrix_voip_service,
           &state.matrix_client,
           req.conversation_id,
           user.id,
           &req.sdp_offer,
           &req.call_type,
           req.max_participants.unwrap_or(4),
       ).await?;

       Ok(HttpResponse::Ok().json(InitiateCallResponse { call_id }))
   }

   /// POST /calls/matrix/answer
   /// POST /calls/matrix/end
   /// Similar structure as above
   ```

3. **Register Matrix Routes Conditionally** (`src/main.rs`)
   ```rust
   if config.matrix.voip_enabled {
       app = app.service(
           web::scope("/api")
               .service(routes::calls_matrix::initiate_call_matrix)
               .service(routes::calls_matrix::answer_call_matrix)
               .service(routes::calls_matrix::end_call_matrix)
       );
   }
   ```

#### Phase 2: Migrate Existing Endpoints (Future - After SDK 0.16 Upgrade)

**Goal**: Replace WebSocket-only endpoints with Matrix-aware versions

**Options**:

**Option A: Gradual Per-Endpoint Migration**
```rust
#[post("/calls/initiate")]
pub async fn initiate_call(
    state: web::Data<AppState>,
    user: User,
    req: web::Json<InitiateCallRequest>,
) -> Result<HttpResponse, AppError> {
    // Check if Matrix VoIP is available
    if state.config.matrix.voip_enabled {
        // Use Matrix-aware method
        CallService::initiate_call_with_matrix(...).await
    } else {
        // Fallback to WebSocket-only
        CallService::initiate_call(...).await
    }
}
```

**Option B: Client-Side Choice (Recommended)**
- Keep both `/calls/initiate` (WebSocket) and `/calls/matrix/initiate` (Matrix)
- Client chooses based on capabilities and preferences
- Allows A/B testing and gradual rollout
- Better for backward compatibility

#### Phase 3: Production Rollout

**Rollout Stages**:

1. **Internal Testing** (Week 1-2)
   - Enable `matrix.voip_enabled = true` in staging
   - Test with curl/Postman
   - Test with Element client (Matrix-to-Matrix calls)
   - Test with Nova client (Nova-to-Nova calls via Matrix)

2. **Beta Users** (Week 3-4)
   - Whitelist beta users for `/calls/matrix/*` endpoints
   - Collect metrics: success rate, latency, E2EE validation
   - Monitor logs for Matrix event errors

3. **Gradual Rollout** (Week 5+)
   - 10% traffic to Matrix endpoints
   - 50% traffic if success rate > 95%
   - 100% traffic if no issues after 2 weeks
   - Keep WebSocket signaling as fallback

### Metrics and Monitoring

**Key Metrics to Track**:

1. **Success Rates**
   - `matrix_call_initiate_success_rate` - % of successful Matrix invite sends
   - `matrix_call_answer_success_rate` - % of successful Matrix answer sends
   - `matrix_call_hangup_success_rate` - % of successful Matrix hangup sends

2. **Latency**
   - `matrix_call_setup_latency_ms` - Time from initiate to answer
   - `matrix_event_send_latency_ms` - Time to send Matrix events

3. **Fallback Usage**
   - `matrix_fallback_to_websocket_count` - How often Matrix fails and falls back

4. **Error Types**
   - `matrix_room_not_found_errors` - Room mapping issues
   - `matrix_send_event_errors` - Matrix API failures

### Testing Plan

**Unit Tests** (Already Implemented):
- `tests/voip_integration_test.rs` - Matrix VoIP flow tests
- Test Matrix event parsing, party ID format, etc.

**Integration Tests** (TODO):
1. **Matrix Homeserver Setup**
   - Run Synapse in Docker for testing
   - Create test accounts and rooms
   - Test E2EE encryption

2. **API Tests with Matrix**
   ```bash
   # Test ICE servers endpoint
   curl -H "Authorization: Bearer $TOKEN" \
        http://localhost:3000/api/calls/ice-servers

   # Test Matrix call initiation (once SDK 0.16 is ready)
   curl -X POST -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"conversation_id":"...", "sdp_offer":"..."}' \
        http://localhost:3000/api/calls/matrix/initiate
   ```

3. **Element Client Interop**
   - Initiate call from Nova → Receive in Element
   - Initiate call from Element → Receive in Nova
   - Verify SDP exchange, ICE candidates, hangup

### Blocked Until SDK 0.16 Upgrade

**Current Limitations** (SDK 0.7):
- ❌ Cannot send real Matrix VoIP events (placeholder only)
- ❌ Cannot receive Matrix VoIP events (sync loop limitation)
- ❌ No typed VoIP event structures

**Workaround**:
- Implement `/calls/ice-servers` now (already done ✅)
- Document Matrix route structure (this plan)
- Wait for SDK 0.16 upgrade to enable real Matrix signaling

## References

- Matrix VoIP Spec: https://spec.matrix.org/v1.1/client-server-api/#voice-over-ip
- MATRIX_VOIP_DESIGN.md - Overall architecture
- migration 0026_add_matrix_voip_fields.sql - Database schema
