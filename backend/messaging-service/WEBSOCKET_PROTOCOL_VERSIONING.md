# WebSocket Protocol Versioning Strategy

**Date**: October 25, 2025
**Status**: ✅ COMPLETE
**Compatibility**: Backward compatible

## Executive Summary

定义了Nova WebSocket协议的版本化方案，确保：
- ✅ 安全的协议升级
- ✅ 客户端向后兼容
- ✅ 版本协商机制
- ✅ 清晰的升级路径

---

## 1. Protocol Version Definition

### Current Version: 1.0

```
格式: MAJOR.MINOR
- MAJOR: 破坏性变更（不兼容的协议更改）
- MINOR: 非破坏性变更（新功能，向后兼容）
```

### Version History

| Version | Date | Status | Breaking Changes |
|---------|------|--------|------------------|
| 1.0 | 2025-10-25 | Current | Initial release |

---

## 2. Version Negotiation

### Connection Handshake

**Client → Server**:
```
WebSocket URL: ws://api.nova.local/ws?
  conversation_id=550e8400-e29b-41d4-a716-446655440000
  &user_id=660e8400-e29b-41d4-a716-446655440111
  &protocol_version=1.0
  &token=jwt_token_here
```

**Server Response** (First message):
```json
{
  "type": "protocol_handshake",
  "protocol_version": "1.0",
  "server_capabilities": {
    "max_payload_size": 1048576,
    "ping_interval_ms": 30000,
    "supported_events": [
      "typing",
      "message_ack",
      "user_online",
      "presence_update"
    ]
  },
  "timestamp": "2025-10-25T10:30:00Z"
}
```

---

## 3. Backward Compatibility Rules

### Rule 1: Never Remove Event Types
Once an event type is defined, it must never be removed. Deprecated events should be marked `deprecated: true` but continue functioning.

**Example**:
```json
{
  "type": "old_event",
  "deprecated": true,
  "replacement": "new_event",
  "message": "Use new_event instead. This will be removed in v2.0"
}
```

### Rule 2: Only Add Fields, Never Remove
New fields in events MUST be optional. Clients expecting older events continue working.

**Version 1.0 Event**:
```json
{
  "type": "Typing",
  "conversation_id": "uuid",
  "user_id": "uuid"
}
```

**Version 1.1 Enhancement** (backward compatible):
```json
{
  "type": "Typing",
  "conversation_id": "uuid",
  "user_id": "uuid",
  "is_mobile": false,  // ← NEW (optional)
  "typing_duration_ms": 500  // ← NEW (optional)
}
```

### Rule 3: Enum Values Are Immutable
Once an enum value is used, it must never change meaning. New values can be added.

**Version 1.0**:
```
message_type: 'text' | 'image' | 'video'
```

**Version 1.1** (acceptable):
```
message_type: 'text' | 'image' | 'video' | 'voice'  // NEW VALUE
```

**Version 1.1** (NOT acceptable):
```
message_type: 'text' | 'photo' | 'video'  // BREAKING: 'image' renamed
```

### Rule 4: Error Codes Are Versioned
New error codes can be added. Clients should handle unknown error codes gracefully.

```json
{
  "type": "error",
  "error_code": "RATE_LIMIT_EXCEEDED",
  "error_code_version": "1.0",
  "message": "You are sending messages too quickly",
  "retry_after_ms": 5000
}
```

---

## 4. Version Upgrade Path

### Client Perspective

**Step 1: Detect Server Version**
```typescript
// On connection
const handshake = await waitForHandshake();
const serverVersion = handshake.protocol_version;

// Compare with our min required version
if (compareVersions(serverVersion, "1.0") < 0) {
  console.error("Server too old, upgrade required");
  close();
}
```

**Step 2: Adapt to Server Capabilities**
```typescript
const capabilities = handshake.server_capabilities;
const supportsVoiceMessages = capabilities.supported_events.includes('voice_message');

if (!supportsVoiceMessages) {
  // Hide voice message button in UI
  disableVoiceMessaging();
}
```

### Server Perspective

**Version Negotiation Logic** (pseudocode):
```rust
async fn handle_websocket_upgrade(...) {
    let client_requested_version = query.protocol_version;
    let server_version = "1.0";

    // Check compatibility
    match client_requested_version {
        "1.0" => {
            // Exact match, proceed normally
            use_protocol_v1_0()
        }
        v if is_compatible(v, server_version) => {
            // Compatible version (future proofing)
            negotiate_compatible_version(v)
        }
        _ => {
            // Incompatible, reject
            reject_connection_with_version_mismatch(server_version)
        }
    }
}
```

---

## 5. Migration Scenarios

### Scenario A: New Optional Event (Minor Bump)

**Release Timeline**:
```
Version 1.0: Released (Typing event)
Version 1.1: Released
  - ADD: voice_typing event (optional)
  - Clients on 1.0 ignore unknown events
  - Clients on 1.1 support voice_typing
  - Fully backward compatible ✓
```

**Implementation**:
```rust
// In handlers.rs, when new feature lands
if should_broadcast_voice_typing(evt) {
    let voice_event = WsOutboundEvent::VoiceTyping { ... };
    broadcast(voice_event).await;
}

// Old v1.0 clients simply ignore this unknown event type
// v1.1 clients handle it
```

### Scenario B: Breaking Protocol Change (Major Bump)

**Example**: Change message compression from none → always gzip

**Release Plan**:
```
Announcement (Q1 2025):
  "Protocol v2.0 planned for Q3 2025"
  "Breaking change: Message compression"

Version 1.2-1.9 (6 months):
  - Add support for compressed messages as optional
  - Clients can opt-in with "supports_compression": true
  - Servers accept both compressed & uncompressed

Version 2.0 (Q3 2025):
  - Servers require compression
  - Mandatory client update
  - Support period: 3 months for old clients
  - After 3 months: Deprecated servers reject v1.x clients
```

**Migration Path**:
```
Old Client                Server              New Client
(v1.9)                    (v2.0)              (v2.0)
  |                         |                   |
  |--handshake v1.9-------->|                   |
  |                         |--REJECT---------->|
  |                    (upgrade required)       |
  |                         |                   |
  |                    [3-month grace period]   |
  |                         |                   |
  |  [After grace period]   |                   |
  |--handshake v1.9-------->|                   |
  |                         |--REJECT (EOL)--->|
```

---

## 6. Implementation Details

### Server: Version Compatibility Matrix

```rust
// src/websocket/version.rs

pub const PROTOCOL_VERSION: &str = "1.0";

pub struct VersionInfo {
    pub major: u32,
    pub minor: u32,
}

impl VersionInfo {
    pub fn from_string(v: &str) -> Result<Self> {
        let parts: Vec<&str> = v.split('.').collect();
        Ok(VersionInfo {
            major: parts[0].parse()?,
            minor: parts[1].parse()?,
        })
    }

    pub fn is_compatible(&self, server_version: &VersionInfo) -> bool {
        // Major must match, minor can be <= server
        self.major == server_version.major
            && self.minor <= server_version.minor
    }
}

#[test]
fn test_version_compatibility() {
    let server = VersionInfo { major: 1, minor: 0 };

    assert!(VersionInfo { major: 1, minor: 0 }.is_compatible(&server)); // exact
    assert!(!VersionInfo { major: 1, minor: 1 }.is_compatible(&server)); // too new
    assert!(!VersionInfo { major: 2, minor: 0 }.is_compatible(&server)); // major differ
}
```

### Server: Capability Advertisement

```rust
// src/websocket/capabilities.rs

pub fn get_server_capabilities() -> ServerCapabilities {
    ServerCapabilities {
        protocol_version: "1.0".to_string(),
        max_payload_size: 1024 * 1024,  // 1MB
        ping_interval_ms: 30000,
        supported_events: vec![
            "Typing".to_string(),
            "PresenceUpdate".to_string(),
            // Add new events here, old clients ignore them
        ],
        deprecated_events: vec![],
    }
}
```

### Client: Version Handling (TypeScript)

```typescript
// src/websocket/client.ts

class WebSocketClient {
  private serverVersion: string = "1.0";
  private capabilities: ServerCapabilities;

  async connect(url: string): Promise<void> {
    const ws = new WebSocket(url + "?protocol_version=1.0");

    ws.onopen = async () => {
      const handshake = await this.waitForHandshake();

      // Store server version
      this.serverVersion = handshake.protocol_version;
      this.capabilities = handshake.server_capabilities;

      // Validate compatibility
      if (!this.isCompatible()) {
        console.error("Server version incompatible");
        ws.close();
        throw new Error("Protocol mismatch");
      }
    };
  }

  private isCompatible(): boolean {
    const client = parseVersion("1.0");
    const server = parseVersion(this.serverVersion);

    return client.major === server.major &&
           client.minor <= server.minor;
  }

  onMessage(msg: Message) {
    const event = JSON.parse(msg.data);

    // Handle known events
    switch (event.type) {
      case "Typing":
        this.handleTyping(event);
        break;
      // ... other events

      default:
        // Gracefully ignore unknown event types
        // (client might be older than server)
        console.warn("Unknown event type", event.type);
    }
  }
}
```

---

## 7. Deprecation Policy

### Timeline for Deprecation

```
Announcement (Release N)
  ↓ (3 months)
v(N+1): Feature marked deprecated, still works
  ↓ (6 months)
v(N+2): Final warning, clients strongly urged to update
  ↓ (12 months)
v(N+3): Feature removed, EOL clients rejected
```

### Example: Deprecating Old Event Format

**v1.0**: Original event
```json
{
  "type": "TypingIndicator",
  "conversation_id": "...",
  "user_id": "..."
}
```

**v1.5**: New event (same functionality)
```json
{
  "type": "Typing",
  "conversation_id": "...",
  "user_id": "...",
  "deprecated_event_mapping": {
    "old_type": "TypingIndicator",
    "migration_guide": "https://..."
  }
}
```

**v2.0**: Old event removed
```
Only "Typing" event accepted
Old clients connecting get:
{
  "type": "error",
  "error_code": "PROTOCOL_VERSION_DEPRECATED",
  "message": "Please upgrade client to v2.0+"
}
```

---

## 8. Testing Strategy

### Unit Tests

```rust
#[cfg(test)]
mod version_tests {
    use super::*;

    #[test]
    fn test_exact_version_match() {
        let server = VersionInfo { major: 1, minor: 0 };
        let client = VersionInfo { major: 1, minor: 0 };
        assert!(client.is_compatible(&server));
    }

    #[test]
    fn test_minor_version_compatible() {
        let server = VersionInfo { major: 1, minor: 2 };
        let client = VersionInfo { major: 1, minor: 0 };
        assert!(client.is_compatible(&server));
    }

    #[test]
    fn test_major_version_incompatible() {
        let server = VersionInfo { major: 2, minor: 0 };
        let client = VersionInfo { major: 1, minor: 0 };
        assert!(!client.is_compatible(&server));
    }
}
```

### Integration Tests

```rust
#[tokio::test]
async fn test_handshake_version_negotiation() {
    let (mut ws, _) = connect_websocket("1.0").await;

    let msg = ws.next().await.unwrap().unwrap();
    let handshake: ProtocolHandshake = serde_json::from_str(&msg.to_text().unwrap()).unwrap();

    assert_eq!(handshake.protocol_version, "1.0");
    assert!(handshake.server_capabilities.supported_events.contains(&"Typing".to_string()));
}
```

---

## 9. Migration Checklist

### For Protocol v1.1 (Example)

- [ ] Add new event type to `WsOutboundEvent` enum
- [ ] Implement handler for new event
- [ ] Add to `server_capabilities.supported_events`
- [ ] Update documentation
- [ ] Add test case for new event
- [ ] Client library updates (optional, graceful degradation)
- [ ] Release notes mention backward compatibility
- [ ] Monitor for client version distribution

### For Protocol v2.0 (Breaking Change)

- [ ] Plan 6-month deprecation timeline
- [ ] Announce breaking change early
- [ ] Implement v1.x compatibility layer in v2.0 servers (3-month grace)
- [ ] Add clear error messages for old clients
- [ ] Provide migration guide
- [ ] Update all SDKs and examples
- [ ] Monitor adoption before EOL

---

## 10. Recovery Strategies

### Client Receives Unknown Event

```typescript
// Graceful degradation
onMessage(msg) {
  try {
    const event = JSON.parse(msg.data);
    if (eventHandlers[event.type]) {
      eventHandlers[event.type](event);
    } else {
      console.warn(`Unknown event type: ${event.type}, ignoring`);
      // Continue operating with existing functionality
    }
  } catch (e) {
    console.error("Failed to parse message", e);
  }
}
```

### Server Receives Unknown Field

```rust
// Ignore extra fields during deserialization
#[derive(Deserialize)]
pub struct WsInboundEvent {
    #[serde(rename = "type")]
    event_type: String,

    #[serde(flatten)]
    data: serde_json::Value,  // Capture unknown fields
}

// Server simply ignores unknown fields from old clients
```

---

## 11. Strict E2E Payload Fields

When a conversation is configured for `strict_e2e`, message-related events (`message.new`,
`message.audio_sent`, etc.) include additional optional fields:

| Field | Type | Notes |
|-------|------|-------|
| `encrypted` | boolean | `true` when the payload is encrypted |
| `encrypted_payload` | string (base64) | XSalsa20-Poly1305 ciphertext |
| `nonce` | string (base64) | 24-byte nonce paired with the ciphertext |

Clients should fall back to fetching the message via REST if these fields are absent.

---

## 12. Version Documentation

Each release MUST include:

1. **CHANGELOG.md**: List all protocol changes
2. **MIGRATION_GUIDE.md**: How to upgrade from previous version
3. **API_DOCS.md**: Updated event definitions
4. **COMPATIBILITY_MATRIX.md**: Which client versions work with which servers

---

## Summary: Protocol Guarantees

| Guarantee | v1.0 → v1.1 | v1.1 → v2.0 |
|-----------|------------|------------|
| Old clients work | ✅ Yes | ❌ No (major bump) |
| New events added | ✅ Ignored by old | ✅ Handled by new |
| New fields added | ✅ Optional | ✅ Optional |
| Error codes change | ❌ No | ⚠️ Can add new |
| Enum values removed | ❌ No | ⚠️ Only in major |

---

**Status**: ✅ Protocol versioning strategy defined and documented
