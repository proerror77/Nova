# Vodozemac E2EE Implementation Summary

**Date**: 2025-11-30
**Status**: Implementation Complete
**Library**: vodozemac 0.7 (Matrix.org's Olm/Megolm implementation)

---

## Overview

This document summarizes the complete end-to-end encryption (E2EE) implementation for Nova's realtime-chat-service using the vodozemac library.

### Key Principles

1. **True E2EE**: Server NEVER has access to plaintext or encryption keys
2. **Client-side encryption**: All encryption/decryption happens on client devices
3. **Forward secrecy**: Compromising current keys doesn't expose past messages
4. **Multi-device support**: Each device has its own cryptographic identity

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT DEVICE                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │ Olm Account │───▶│ Olm Session │───▶│ Megolm Outbound     │  │
│  │ (Identity)  │    │ (1:1 E2EE)  │    │ (Room Key Creator)  │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
│         │                  │                     │               │
│         ▼                  ▼                     ▼               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    LOCAL KEY STORAGE                         ││
│  │  (Encrypted with device-local master key)                   ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Encrypted blobs only
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SERVER                                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐  │
│  │ user_devices │   │ olm_accounts │   │ megolm_*_sessions  │  │
│  │ (public keys)│   │ (pickled,    │   │ (pickled,          │  │
│  │              │   │  encrypted)  │   │  encrypted)        │  │
│  └──────────────┘   └──────────────┘   └────────────────────┘  │
│         │                  │                     │               │
│         ▼                  ▼                     ▼               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    messages table                            ││
│  │  megolm_ciphertext (server cannot decrypt!)                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Files Created

### Database Migrations

| File | Description |
|------|-------------|
| `migrations/0010_e2ee_vodozemac_tables.sql` | Core E2EE tables (8 tables) |
| `migrations/0011_add_megolm_message_columns.sql` | Message table E2EE columns |

### Services

| File | Lines | Description |
|------|-------|-------------|
| `src/services/olm_service.rs` | ~450 | 1:1 encryption (Double Ratchet) |
| `src/services/megolm_service.rs` | ~500 | Group encryption (symmetric ratchet) |
| `src/services/e2ee_message_service.rs` | ~280 | E2EE message storage layer |

### API Layer

| File | Description |
|------|-------------|
| `src/handlers/e2ee.rs` | REST endpoints for key management |
| `src/websocket/message_types.rs` | WebSocket E2EE events |

---

## Database Schema

### Core Tables (Migration 0010)

```
user_devices          - Device registration with identity keys
olm_accounts          - Pickled Olm accounts (encrypted at rest)
olm_one_time_keys     - Pre-keys for session establishment
olm_sessions          - 1:1 encrypted channels between devices
megolm_outbound_sessions - Room encryption sessions (sender)
megolm_inbound_sessions  - Room decryption sessions (receiver)
to_device_messages    - Key sharing queue (Olm-encrypted)
room_key_history      - Historical keys for late joiners
```

### Message Table Extensions (Migration 0011)

```sql
-- New columns on messages table
sender_device_id      TEXT      -- Which device sent this
megolm_session_id     TEXT      -- Megolm session used
megolm_ciphertext     TEXT      -- Encrypted content (base64)
megolm_message_index  INTEGER   -- Ratchet position
encryption_version    INTEGER   -- 0=plain, 1=server, 2=E2EE
```

---

## API Reference

### REST Endpoints

```
POST /api/v1/e2ee/devices           - Register new device
POST /api/v1/e2ee/keys/upload       - Upload one-time keys
POST /api/v1/e2ee/keys/claim        - Claim OTK for session setup
POST /api/v1/e2ee/keys/query        - Query user's device keys
GET  /api/v1/e2ee/to-device         - Get pending key-share messages
DELETE /api/v1/e2ee/to-device/{id}  - Acknowledge key-share message
```

### WebSocket Events

**Inbound (Client → Server):**
```json
{"type": "get_to_device_messages", "device_id": "...", "since": "..."}
{"type": "ack_to_device_message", "message_id": "..."}
{"type": "request_room_keys", "conversation_id": "...", "session_id": "..."}
{"type": "share_room_key", "target_device_id": "...", "encrypted_key": "..."}
{"type": "send_e2ee_message", "conversation_id": "...", "session_id": "...", "ciphertext": "..."}
```

**Outbound (Server → Client):**
```json
{"type": "to_device_message", "sender_device_id": "...", "content": "..."}
{"type": "room_key_request", "requester_device_id": "...", "session_id": "..."}
{"type": "e2ee_message", "message_id": "...", "ciphertext": "...", "session_id": "..."}
{"type": "session_rotated", "room_id": "...", "new_session_id": "..."}
{"type": "otk_count_low", "device_id": "...", "remaining_count": 5}
```

---

## Encryption Flow

### 1:1 Messages (Olm)

```
Alice                          Server                          Bob
  │                              │                              │
  │ 1. Claim Bob's OTK          │                              │
  │ ─────────────────────────▶  │                              │
  │                              │                              │
  │ 2. Create Olm session        │                              │
  │    (X3DH-like)               │                              │
  │                              │                              │
  │ 3. Encrypt with Olm          │                              │
  │ ─────────────────────────▶  │  4. Store encrypted blob     │
  │                              │ ─────────────────────────▶   │
  │                              │                              │
  │                              │  5. Receive encrypted blob   │
  │                              │ ◀─────────────────────────   │
  │                              │                              │
  │                              │  6. Decrypt with Olm session │
```

### Group Messages (Megolm)

```
Alice                          Server                     Bob, Carol
  │                              │                              │
  │ 1. Create Megolm session     │                              │
  │    for room R                │                              │
  │                              │                              │
  │ 2. Share room key via Olm    │                              │
  │ ─────────────────────────▶  │ ─────────────────────────▶   │
  │                              │                              │
  │ 3. Encrypt message with      │                              │
  │    Megolm session            │                              │
  │ ─────────────────────────▶  │  4. Store ciphertext         │
  │                              │ ─────────────────────────▶   │
  │                              │                              │
  │                              │  5. Decrypt with shared key  │
```

---

## Environment Variables

```bash
# Required: 32-byte hex key for encrypting pickled crypto state
export OLM_ACCOUNT_KEY=$(openssl rand -hex 32)

# Example:
# OLM_ACCOUNT_KEY=a1b2c3d4e5f6...  (64 hex characters)
```

---

## Security Considerations

### What Server CAN See

- Public identity keys (Curve25519, Ed25519)
- Device metadata (device_id, device_name, last_seen)
- Message metadata (sender_id, conversation_id, timestamp)
- Encrypted ciphertext blobs
- Session IDs (but not session keys)

### What Server CANNOT See

- Message plaintext content
- Private keys
- Session keys (Megolm room keys)
- One-time key private parts

### Session Rotation

Megolm sessions are rotated when:
- Message count exceeds threshold (default: 1000)
- Session age exceeds threshold (default: 7 days)
- Membership changes (user leaves room)

---

## Client Implementation Guide

### 1. Device Registration

```typescript
// On first app launch or new device
const deviceId = generateUUID();
const response = await fetch('/api/v1/e2ee/devices', {
  method: 'POST',
  body: JSON.stringify({ device_id: deviceId, device_name: 'iPhone 15' })
});
const { identity_key, signing_key } = await response.json();
// Store locally for future use
```

### 2. Upload One-Time Keys

```typescript
// Keep pool of OTKs on server (recommended: 50+)
await fetch('/api/v1/e2ee/keys/upload', {
  method: 'POST',
  body: JSON.stringify({ count: 50 })
});
```

### 3. Establish Session

```typescript
// When sending first message to a user
const claimed = await fetch('/api/v1/e2ee/keys/claim', {
  method: 'POST',
  body: JSON.stringify({
    one_time_keys: { [targetUserId]: [targetDeviceId] }
  })
});
// Use claimed key to create Olm session
```

### 4. Send Encrypted Message

```typescript
// Get or create Megolm session for room
const session = await getMegolmSession(roomId);

// Encrypt message client-side
const ciphertext = session.encrypt(plaintextBytes);

// Send to server (server only sees ciphertext)
ws.send(JSON.stringify({
  type: 'send_e2ee_message',
  conversation_id: roomId,
  device_id: myDeviceId,
  session_id: session.sessionId,
  ciphertext: base64Encode(ciphertext),
  message_index: session.messageIndex
}));
```

---

## Testing

### Run Migrations

```bash
cd backend/realtime-chat-service
sqlx migrate run
```

### Integration Tests

```bash
# Requires DATABASE_URL and OLM_ACCOUNT_KEY
cargo test --test e2ee_integration
```

---

## Dependencies Added

```toml
# Cargo.toml additions
vodozemac = "0.7"       # Matrix Olm/Megolm implementation
aes-gcm = "0.10"        # Pickle encryption at rest
zeroize = "1.7"         # Secure memory zeroing
getrandom = "0.2"       # Cryptographic randomness
hex = "0.4"             # Hex encoding for keys
```

---

## Next Steps

1. **Client SDK**: Implement vodozemac bindings for iOS/Android
2. **Key Backup**: Add encrypted key backup to server
3. **Device Verification**: Implement SAS or QR code verification
4. **Cross-signing**: Implement user-level key verification
5. **Audit Logging**: Add compliance-friendly audit trail

---

## References

- [vodozemac crate](https://crates.io/crates/vodozemac)
- [Matrix Olm Specification](https://matrix.org/docs/spec/olm)
- [Matrix Megolm Specification](https://matrix.org/docs/spec/megolm)
- [Signal Protocol](https://signal.org/docs/)
