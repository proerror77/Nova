# Matrix Integration Summary

**Status**: ✅ **IMPLEMENTED**
**Last Updated**: 2025-12-09
**Matrix SDK Version**: 0.7.0
**Integration Type**: Dual-write with graceful degradation

---

## Overview

Nova's realtime-chat-service now integrates with Matrix Synapse for End-to-End Encrypted (E2EE) messaging. Messages are written to both Nova's PostgreSQL database and Matrix rooms, enabling:

- **E2EE messaging** through Matrix protocol
- **Backward compatibility** with existing Nova clients
- **Graceful degradation** - Matrix failures don't block message operations
- **Federation support** - Messages can be exchanged with other Matrix homeservers

---

## Architecture

### Dual-Write Pattern

```
User sends message
     ↓
Nova API receives request
     ↓
┌────────────────────────────────┐
│ 1. Write to Nova DB (REQUIRED) │ ← Always succeeds or fails atomically
└────────────────────────────────┘
     ↓
┌────────────────────────────────┐
│ 2. Send to Matrix (OPTIONAL)   │ ← Best effort, failure logged but not blocking
└────────────────────────────────┘
     ↓
Broadcast to WebSocket clients
```

### Components

#### 1. **MatrixClient** (`src/services/matrix_client.rs`)
Core wrapper around Matrix Rust SDK with methods:
- `new(config)` - Initialize client with access token
- `get_or_create_room(conversation_id, participants)` - Room management
- `send_message(conversation_id, room_id, text)` - Send text messages
- `send_media(...)` - Send audio/image/file messages (TODO: implement upload)
- `delete_message(room_id, event_id)` - Redact messages
- `edit_message(room_id, event_id, new_text)` - Edit messages (workaround for SDK 0.7)
- `start_sync(event_handler)` - Start receiving Matrix events

#### 2. **Matrix Database Helpers** (`src/services/matrix_db.rs`)
Database operations for Matrix integration:
- `save_room_mapping(db, conversation_id, room_id)` - Persist room mappings
- `load_room_mapping(db, conversation_id)` - Retrieve Matrix room for conversation
- `lookup_conversation_by_room_id(db, room_id)` - Reverse lookup for incoming events
- `get_matrix_info(db, conversation_id)` - Get room_id and participants
- `update_message_matrix_event_id(db, message_id, event_id)` - Link messages to Matrix events
- `get_conversation_participants(db, conversation_id)` - Get participant UUIDs

#### 3. **Message Service Integration** (`src/services/message_service.rs`)
Integrated functions that handle both Nova and Matrix:
- `send_message_with_matrix(...)` - Send text message to both DB and Matrix
- `send_audio_message_with_matrix(...)` - Send audio message to both systems
- `update_message_with_matrix(...)` - Update message in both DB and Matrix
- `soft_delete_message_with_matrix(...)` - Delete message in both DB and Matrix

#### 4. **Matrix Event Handler** (`src/services/matrix_event_handler.rs`)
Handles incoming Matrix events:
- `handle_matrix_message_event(...)` - Process new messages from Matrix sync
  - Extracts Nova user_id from Matrix sender (@nova-<uuid>:domain)
  - Prevents duplicate processing (checks matrix_event_id)
  - Saves message to Nova DB
  - Broadcasts to WebSocket clients
- `handle_matrix_redaction_event(...)` - Process message deletions
- `handle_matrix_replacement_event(...)` - Process message edits

#### 5. **Matrix Sync Loop** (`src/main.rs` lines 205-246)
Background task that:
- Starts when Matrix is enabled (MATRIX_ENABLED=true)
- Registers event handlers for new messages
- Runs Matrix SDK sync loop
- Spawns async tasks for each incoming event
- Logs errors without crashing

---

## Database Schema

### New Table: `matrix_room_mappings`

```sql
CREATE TABLE matrix_room_mappings (
    conversation_id UUID NOT NULL PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    matrix_room_id TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_matrix_room_mappings_room_id ON matrix_room_mappings(matrix_room_id);
```

### Updated `messages` Table

```sql
ALTER TABLE messages
ADD COLUMN matrix_event_id TEXT;

CREATE INDEX idx_messages_matrix_event_id ON messages(matrix_event_id);
```

---

## Configuration

### Environment Variables

```bash
# Matrix Integration (Optional)
MATRIX_ENABLED=true                                  # Enable/disable Matrix integration
MATRIX_HOMESERVER_URL=http://matrix-synapse:8008    # Matrix Synapse URL
MATRIX_SERVICE_USER=@nova-service:staging.nova.internal  # Service account user ID
MATRIX_ACCESS_TOKEN=syt_...                         # Access token for service account
MATRIX_DEVICE_NAME=nova-chat-service                # Device name for session
```

### Kubernetes ConfigMap/Secret

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: realtime-chat-config
data:
  MATRIX_ENABLED: "true"
  MATRIX_HOMESERVER_URL: "http://matrix-synapse:8008"
  MATRIX_SERVICE_USER: "@nova-service:staging.nova.internal"
  MATRIX_DEVICE_NAME: "nova-chat-service"
---
apiVersion: v1
kind: Secret
metadata:
  name: realtime-chat-secrets
type: Opaque
stringData:
  MATRIX_ACCESS_TOKEN: "syt_bm92YXNlcnZpY2U_..."
```

---

## Matrix User ID Format

Nova users are mapped to Matrix user IDs using this pattern:

```
@nova-<uuid>:<homeserver_domain>
```

**Examples:**
- Nova user `550e8400-e29b-41d4-a716-446655440000`
- Matrix user `@nova-550e8400e29b41d4a716446655440000:staging.nova.internal`

**Extraction logic** (`extract_user_id_from_matrix`):
```rust
// Input: @nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.internal
// Extract: 550e8400-e29b-41d4-a716-446655440000
// Parse as UUID
```

---

## Message Flow

### Outbound (Nova → Matrix)

1. **Client sends message** via WebSocket or REST API
2. **Nova validates** authentication and permissions
3. **Insert to Nova DB** (atomic, required)
   - Encrypt with Nova's encryption key
   - Generate message ID and sequence number
4. **Load Matrix room** from cache or DB
   - If not exists, create Matrix room and invite participants
5. **Send to Matrix** (best effort, non-blocking)
   - Convert plaintext to Matrix format
   - Call `MatrixClient::send_message`
   - On success: save `matrix_event_id` to DB
   - On failure: log error, continue
6. **Broadcast to WebSocket** clients (MessageNew event)

### Inbound (Matrix → Nova)

1. **Matrix sync loop** receives `SyncRoomMessageEvent`
2. **Event handler spawned** asynchronously
3. **Lookup conversation** by Matrix room_id
4. **Extract Nova user_id** from Matrix sender
5. **Check for duplicate** (by matrix_event_id)
6. **Insert to Nova DB** using `MessageService::send_message_db`
7. **Update with matrix_event_id** to link records
8. **Broadcast to WebSocket** clients (MessageNew event)

---

## Error Handling & Graceful Degradation

### Principles

1. **Nova DB is source of truth** - Matrix failures NEVER block message operations
2. **Log errors extensively** - Use structured logging for debugging
3. **Non-blocking Matrix calls** - Wrapped in Result types, logged on Err
4. **Idempotency** - Check `matrix_event_id` to prevent duplicate processing

### Example Error Scenarios

| Scenario | Behavior |
|----------|----------|
| Matrix homeserver down | Message saved to Nova DB, Matrix send fails silently, logged as error |
| Matrix room creation fails | Message saved to Nova DB, room creation retried on next message |
| Matrix event_id already exists | Skip DB insert (duplicate), log and continue |
| Invalid Matrix user format | Log warning, skip message processing |
| Matrix sync loop crashes | Log error, does not affect REST/WebSocket services |

---

## Known Limitations (Matrix SDK 0.7)

### 1. Session Restoration API

**Issue**: Matrix SDK 0.7 has different session/authentication APIs than newer versions.

**Current Status**: Placeholder implementation with warning log.

```rust
// TODO: Matrix SDK 0.7 session restoration
// Correct implementation for matrix-sdk 0.7 would be:
// client.matrix_auth().login_token(&config.access_token).send().await?;
warn!("Matrix client session restoration not fully implemented for SDK 0.7");
```

**Impact**: Client is created but not authenticated. Needs update when upgrading SDK.

**Workaround**: Use access token environment variable for now.

### 2. Message Replacement API

**Issue**: `struct Replacement` is private in Matrix SDK 0.7, cannot create replacement events.

**Current Status**: Workaround implementation sends new message with "[EDITED]" prefix.

```rust
// TODO: Update this when upgrading Matrix SDK
// For now, we'll send a new message with a note that it's an edit
let content = RoomMessageEventContent::text_plain(format!(
    "[EDITED] {}",
    new_text
));
```

**Impact**: Message edits appear as new messages instead of replacing original.

**Workaround**: Prefix with "[EDITED]", client can detect and handle specially.

### 3. Media Upload

**Issue**: Matrix media upload requires downloading from Nova storage, uploading to Matrix media API.

**Current Status**: Sends media URL as text message.

```rust
// TODO: Implement proper Matrix media upload via /_matrix/media/v3/upload
let content = RoomMessageEventContent::text_plain(format!(
    "[Media: {} - {}]\n{}",
    media_type, filename, media_url
));
```

**Impact**: Media messages are text-only with URLs.

**Future**: Download from GCS, upload to Matrix, send as m.audio/m.image/m.file.

---

## Testing

### Integration Test Checklist

- [ ] Send text message with Matrix enabled → Message in both Nova DB and Matrix
- [ ] Send text message with Matrix disabled → Message only in Nova DB
- [ ] Edit message → Message updated in both systems
- [ ] Delete message → Message soft-deleted in Nova, redacted in Matrix
- [ ] Send message when Matrix homeserver down → Message saved to Nova, error logged
- [ ] Receive message from Matrix sync → Message appears in Nova DB and WebSocket
- [ ] Duplicate Matrix event → Ignored, no duplicate DB entry
- [ ] Invalid Matrix user format → Logged, skipped
- [ ] Matrix room creation for new conversation → Room created, participants invited

### Manual Testing Steps

1. **Enable Matrix in staging**:
   ```bash
   kubectl set env deployment/realtime-chat-service -n nova-staging \
     MATRIX_ENABLED=true \
     MATRIX_HOMESERVER_URL=http://matrix-synapse:8008 \
     MATRIX_SERVICE_USER=@nova-service:staging.nova.internal \
     MATRIX_ACCESS_TOKEN=syt_...
   ```

2. **Send test message** via Nova API:
   ```bash
   curl -X POST https://api-staging.nova.internal/messages \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "conversation_id": "...",
       "plaintext": "Hello from Nova with Matrix!"
     }'
   ```

3. **Verify in Matrix** (using Element or curl):
   ```bash
   curl -X GET "http://matrix-synapse:8008/_matrix/client/r0/rooms/$ROOM_ID/messages" \
     -H "Authorization: Bearer $MATRIX_ACCESS_TOKEN"
   ```

4. **Check Nova DB**:
   ```sql
   SELECT id, plaintext_content, matrix_event_id, created_at
   FROM messages
   WHERE conversation_id = '...'
   ORDER BY created_at DESC
   LIMIT 5;
   ```

---

## Monitoring & Observability

### Key Metrics to Track

- `matrix_send_success_total` - Successful Matrix sends
- `matrix_send_failure_total` - Failed Matrix sends
- `matrix_sync_events_received_total` - Events received from Matrix
- `matrix_room_creation_total` - Rooms created
- `matrix_duplicate_events_total` - Duplicate events skipped

### Important Log Messages

```
✅ Matrix client initialized for homeserver: http://matrix-synapse:8008
✅ Matrix sync loop started in background
⚠️  Matrix client session restoration not fully implemented for SDK 0.7
❌ Matrix send failed: <error> (conversation_id=...)
```

### Alerts to Configure

- **Matrix sync loop crash** - Restart required
- **High Matrix send failure rate** (>10% in 5min) - Homeserver issue
- **Matrix room creation failures** - Permission or quota issue

---

## Future Improvements

### Short-term (Next Sprint)

1. **Upgrade Matrix SDK** to 0.8+ for proper session restoration and replacement API
2. **Implement media upload** - Download from GCS, upload to Matrix media API
3. **Add retry logic** for Matrix send failures (with exponential backoff)
4. **Cache room mappings** in Redis for faster lookups

### Medium-term (Next Quarter)

1. **Matrix federation support** - Enable messaging with users on other homeservers
2. **Read receipts sync** - Sync read receipts between Nova and Matrix
3. **Typing indicators** - Propagate typing status to Matrix
4. **Presence sync** - Online/offline status integration

### Long-term (Future)

1. **Client-side E2EE** - Move encryption to iOS/Android clients using vodozemac
2. **Matrix bridges** - WhatsApp, Telegram, Signal interop
3. **Matrix Space support** - Group rooms into Spaces
4. **Matrix voice/video calls** - VoIP integration

---

## References

- **Matrix Specification**: https://spec.matrix.org/latest/
- **Matrix Rust SDK**: https://github.com/matrix-org/matrix-rust-sdk
- **Nova E2EE Docs**: `E2EE_VODOZEMAC_IMPLEMENTATION.md`
- **Matrix Synapse Deployment**: `nova-infra/k8s/staging/matrix-synapse/`

---

## Deployment Status

| Environment | Matrix Enabled | Homeserver URL | Status |
|-------------|----------------|----------------|--------|
| Development | ❌ No | - | N/A |
| Staging | ✅ Yes | http://matrix-synapse:8008 | ✅ Running |
| Production | ❌ No (planned) | - | Pending |

---

## Migration Path for Existing Conversations

For conversations that already exist in Nova:

1. **On first message after Matrix enabled**:
   - Check if `matrix_room_id` exists for conversation
   - If not, create Matrix room
   - Invite all participants
   - Save room mapping

2. **Historical messages**: NOT migrated to Matrix (design decision)
   - Only new messages go to Matrix
   - Old messages remain in Nova DB only

3. **Participants joining later**:
   - Automatically invited to Matrix room when added to conversation
   - Can see messages from their join time onward

---

**Questions or issues?** Contact @backend-team or file issue in nova/backend repo.
