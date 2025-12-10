# E2EE Handlers Implementation Guide

## Overview

This document describes the E2EE REST API handlers implementation for the realtime-chat-service, providing Matrix-like key management endpoints adapted to our existing X25519 ECDH architecture.

## Architecture

### Design Decisions

**Matrix-Compatible API Surface**: The handlers provide a Matrix Olm/Megolm-inspired API, but adapted to our existing cryptographic primitives:

- **Identity Keys**: X25519 public keys (not Curve25519 Olm accounts)
- **One-Time Keys**: X25519 prekey bundles for asynchronous key agreement
- **Signing Keys**: Placeholder for future Ed25519 implementation
- **To-Device Messages**: Out-of-band encrypted signaling

**Integration with Existing Services**:

- Uses `E2eeService` from `/src/services/e2ee.rs`
- Follows project patterns: `AppState`, `User` guard, actix-web handlers
- Compatible with existing `device_keys` table

## File Structure

```
backend/realtime-chat-service/
├── src/
│   ├── handlers/
│   │   ├── mod.rs          # Handler module exports
│   │   └── e2ee.rs         # E2EE endpoints (NEW)
│   ├── services/
│   │   └── e2ee.rs         # E2EE service (EXISTING - needs enhancements)
│   └── main.rs             # Mount e2ee routes (needs update)
```

## API Endpoints

### 1. Device Registration

**POST** `/api/v1/e2ee/devices`

Registers a new device and generates X25519 keypair.

**Request**:
```json
{
  "device_id": "iPhone-ABC123",
  "device_name": "Alice's iPhone"
}
```

**Response**:
```json
{
  "device_id": "iPhone-ABC123",
  "identity_key": "base64_encoded_x25519_public_key",
  "signing_key": "base64_placeholder_for_ed25519"
}
```

**Implementation Status**: ✅ Complete (uses existing `E2eeService::generate_keypair()` and `store_device_key()`)

---

### 2. Upload One-Time Keys

**POST** `/api/v1/e2ee/keys/upload`

Generates ephemeral prekeys for asynchronous key agreement.

**Headers**:
```
X-Device-ID: iPhone-ABC123
```

**Request**:
```json
{
  "count": 50
}
```

**Response**:
```json
{
  "uploaded_count": 50,
  "total_count": 50
}
```

**Implementation Status**: ⚠️ Placeholder (needs `generate_one_time_keys()` in E2eeService)

---

### 3. Claim One-Time Keys

**POST** `/api/v1/e2ee/keys/claim`

Claims prekeys from target devices to establish sessions.

**Headers**:
```
X-Device-ID: iPhone-ABC123
```

**Request**:
```json
{
  "one_time_keys": {
    "user-uuid-1": ["device-1", "device-2"],
    "user-uuid-2": ["device-3"]
  }
}
```

**Response**:
```json
{
  "one_time_keys": {
    "user-uuid-1": {
      "device-1": {
        "device_id": "device-1",
        "key_id": "otk_123",
        "key": "base64_one_time_key",
        "identity_key": "base64_x25519_identity_key",
        "signing_key": "base64_placeholder"
      }
    }
  },
  "failures": ["device-2"]
}
```

**Implementation Status**: ⚠️ Partial (returns identity keys, needs `claim_one_time_key()`)

---

### 4. Query Device Keys

**POST** `/api/v1/e2ee/keys/query`

Discovers all devices for specified users.

**Request**:
```json
{
  "user_ids": ["user-uuid-1", "user-uuid-2"]
}
```

**Response**:
```json
{
  "device_keys": {
    "user-uuid-1": [
      {
        "device_id": "iPhone-ABC",
        "device_name": "Alice's iPhone",
        "identity_key": "base64_x25519_key",
        "signing_key": "base64_placeholder",
        "verified": false
      }
    ]
  }
}
```

**Implementation Status**: ⚠️ Placeholder (needs `get_all_device_keys()`)

---

### 5. Get To-Device Messages

**GET** `/api/v1/e2ee/to-device?limit=100`

Retrieves pending encrypted messages for this device.

**Headers**:
```
X-Device-ID: iPhone-ABC123
```

**Response**:
```json
{
  "messages": [
    {
      "id": "msg-uuid",
      "sender_user_id": "sender-uuid",
      "sender_device_id": "Android-XYZ",
      "message_type": "m.room_key",
      "content": "base64_encrypted_content",
      "created_at": "2025-11-30T12:00:00Z"
    }
  ],
  "next_batch": null
}
```

**Implementation Status**: ⚠️ Placeholder (needs to-device message storage)

---

### 6. Acknowledge To-Device Message

**DELETE** `/api/v1/e2ee/to-device/{message_id}`

Marks message as delivered and removes from queue.

**Response**: 204 No Content

**Implementation Status**: ⚠️ Placeholder (needs message deletion)

---

## Required Service Enhancements

### E2eeService Methods to Add

#### 1. One-Time Key Management

```rust
impl E2eeService {
    /// Generate and store one-time prekeys
    pub async fn generate_one_time_keys(
        &self,
        pool: &Pool<Postgres>,
        user_id: Uuid,
        device_id: &str,
        count: usize,
    ) -> Result<usize, AppError> {
        let mut keys_stored = 0;

        for _ in 0..count {
            let (public_key, _) = self.generate_keypair();
            let key_id = format!("otk_{}", Uuid::new_v4());

            sqlx::query(
                "INSERT INTO one_time_keys (user_id, device_id, key_id, public_key)
                 VALUES ($1, $2, $3, $4)
                 ON CONFLICT (user_id, device_id, key_id) DO NOTHING"
            )
            .bind(user_id)
            .bind(device_id)
            .bind(&key_id)
            .bind(BASE64.encode(&public_key))
            .execute(pool)
            .await?;

            keys_stored += 1;
        }

        Ok(keys_stored)
    }

    /// Get count of available one-time keys
    pub async fn get_one_time_key_count(
        &self,
        pool: &Pool<Postgres>,
        user_id: Uuid,
        device_id: &str,
    ) -> Result<i32, AppError> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM one_time_keys
             WHERE user_id = $1 AND device_id = $2 AND NOT claimed"
        )
        .bind(user_id)
        .bind(device_id)
        .fetch_one(pool)
        .await?;

        Ok(count as i32)
    }

    /// Claim a one-time key (atomic, single-use)
    pub async fn claim_one_time_key(
        &self,
        pool: &Pool<Postgres>,
        target_user_id: Uuid,
        target_device_id: &str,
        claiming_user_id: Uuid,
        claiming_device_id: &str,
    ) -> Result<(String, Vec<u8>), AppError> {
        // Atomic claim using UPDATE RETURNING with row-level locking
        let row = sqlx::query(
            "UPDATE one_time_keys
             SET claimed = TRUE,
                 claimed_by_user_id = $3,
                 claimed_by_device_id = $4,
                 claimed_at = NOW()
             WHERE id = (
                 SELECT id FROM one_time_keys
                 WHERE user_id = $1 AND device_id = $2 AND NOT claimed
                 ORDER BY created_at ASC
                 LIMIT 1
                 FOR UPDATE SKIP LOCKED
             )
             RETURNING key_id, public_key"
        )
        .bind(target_user_id)
        .bind(target_device_id)
        .bind(claiming_user_id)
        .bind(claiming_device_id)
        .fetch_optional(pool)
        .await?
        .ok_or_else(|| AppError::NotFound)?;

        let key_id: String = row.get("key_id");
        let public_key_b64: String = row.get("public_key");
        let public_key = BASE64.decode(&public_key_b64)
            .map_err(|e| AppError::Encryption(format!("Invalid key: {}", e)))?;

        Ok((key_id, public_key))
    }
}
```

#### 2. Device Key Queries

```rust
pub struct DeviceKeyRecord {
    pub device_id: String,
    pub device_name: Option<String>,
    pub public_key: Vec<u8>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl E2eeService {
    /// Get all devices for a user
    pub async fn get_all_device_keys(
        &self,
        pool: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<Vec<DeviceKeyRecord>, AppError> {
        let rows = sqlx::query(
            "SELECT device_id, device_name, public_key, created_at
             FROM device_keys
             WHERE user_id = $1
             ORDER BY created_at DESC"
        )
        .bind(user_id)
        .fetch_all(pool)
        .await?;

        let mut devices = Vec::new();
        for row in rows {
            let public_key_b64: String = row.get("public_key");
            let public_key = BASE64.decode(&public_key_b64)?;

            devices.push(DeviceKeyRecord {
                device_id: row.get("device_id"),
                device_name: row.get("device_name"),
                public_key,
                created_at: row.get("created_at"),
            });
        }

        Ok(devices)
    }
}
```

#### 3. To-Device Messaging

```rust
pub struct ToDeviceMessageRecord {
    pub id: Uuid,
    pub sender_user_id: Uuid,
    pub sender_device_id: String,
    pub message_type: String,
    pub content: Vec<u8>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl E2eeService {
    /// Store a to-device message
    pub async fn store_to_device_message(
        &self,
        pool: &Pool<Postgres>,
        sender_user_id: Uuid,
        sender_device_id: &str,
        recipient_user_id: Uuid,
        recipient_device_id: &str,
        message_type: &str,
        content: &[u8],
    ) -> Result<Uuid, AppError> {
        let id = Uuid::new_v4();

        sqlx::query(
            "INSERT INTO to_device_messages
             (id, sender_user_id, sender_device_id, recipient_user_id,
              recipient_device_id, message_type, content)
             VALUES ($1, $2, $3, $4, $5, $6, $7)"
        )
        .bind(id)
        .bind(sender_user_id)
        .bind(sender_device_id)
        .bind(recipient_user_id)
        .bind(recipient_device_id)
        .bind(message_type)
        .bind(content)
        .execute(pool)
        .await?;

        Ok(id)
    }

    /// Get to-device messages for a device
    pub async fn get_to_device_messages(
        &self,
        pool: &Pool<Postgres>,
        user_id: Uuid,
        device_id: &str,
        limit: i32,
    ) -> Result<Vec<ToDeviceMessageRecord>, AppError> {
        let rows = sqlx::query(
            "SELECT id, sender_user_id, sender_device_id, message_type,
                    content, created_at
             FROM to_device_messages
             WHERE recipient_user_id = $1 AND recipient_device_id = $2
             ORDER BY created_at ASC
             LIMIT $3"
        )
        .bind(user_id)
        .bind(device_id)
        .bind(limit)
        .fetch_all(pool)
        .await?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(ToDeviceMessageRecord {
                id: row.get("id"),
                sender_user_id: row.get("sender_user_id"),
                sender_device_id: row.get("sender_device_id"),
                message_type: row.get("message_type"),
                content: row.get("content"),
                created_at: row.get("created_at"),
            });
        }

        Ok(messages)
    }

    /// Mark messages as delivered (atomic delete)
    pub async fn mark_messages_delivered(
        &self,
        pool: &Pool<Postgres>,
        message_ids: &[Uuid],
    ) -> Result<(), AppError> {
        sqlx::query(
            "DELETE FROM to_device_messages WHERE id = ANY($1)"
        )
        .bind(message_ids)
        .execute(pool)
        .await?;

        Ok(())
    }
}
```

---

## Database Migration

Create `/backend/realtime-chat-service/migrations/XXX_e2ee_enhancements.sql`:

```sql
-- One-time keys for asynchronous key agreement
CREATE TABLE IF NOT EXISTS one_time_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    key_id TEXT NOT NULL UNIQUE,
    public_key TEXT NOT NULL,
    claimed BOOLEAN DEFAULT FALSE,
    claimed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    claimed_by_device_id TEXT,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_device_key UNIQUE(user_id, device_id, key_id)
);

CREATE INDEX idx_one_time_keys_device ON one_time_keys(user_id, device_id, claimed)
    WHERE NOT claimed;

CREATE INDEX idx_one_time_keys_created ON one_time_keys(created_at)
    WHERE NOT claimed;

-- To-device messages for out-of-band signaling
CREATE TABLE IF NOT EXISTS to_device_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_device_id TEXT NOT NULL,
    recipient_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_device_id TEXT NOT NULL,
    message_type TEXT NOT NULL,
    content BYTEA NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_to_device_recipient ON to_device_messages(
    recipient_user_id, recipient_device_id, created_at DESC
);

CREATE INDEX idx_to_device_created ON to_device_messages(created_at);

-- Add device_name to existing device_keys table
ALTER TABLE device_keys ADD COLUMN IF NOT EXISTS device_name TEXT;

-- Add index for device key lookups
CREATE INDEX IF NOT EXISTS idx_device_keys_user ON device_keys(user_id);

-- Cleanup policy: Auto-delete old claimed keys (retention: 30 days)
CREATE INDEX IF NOT EXISTS idx_one_time_keys_cleanup ON one_time_keys(claimed_at)
    WHERE claimed = TRUE;

-- Cleanup policy: Auto-delete old to-device messages (retention: 7 days)
-- (Should be implemented as a background job)
```

---

## Integration Steps

### 1. Update main.rs

```rust
// In main.rs, add:
mod handlers;

use handlers::e2ee;

// In configure_routes() or server setup:
.service(
    web::scope("/api/v1")
        .configure(e2ee::configure)
        // ... other routes
)
```

### 2. Update E2eeService

Add the methods documented above to `/src/services/e2ee.rs`.

### 3. Run Migration

```bash
cd backend/realtime-chat-service
sqlx migrate run
```

### 4. Update AppState (if needed)

If E2eeService isn't already in AppState, add it:

```rust
pub struct AppState {
    pub db: Pool<Postgres>,
    pub e2ee_service: Arc<E2eeService>,
    // ... other fields
}
```

---

## Security Considerations

### 1. Private Key Protection

**Current**: Secret keys encrypted at rest with master key in `E2eeService`

**Recommendation**: Use AWS KMS or HashiCorp Vault for master key storage

### 2. One-Time Key Claiming

**Implementation**: Atomic with `FOR UPDATE SKIP LOCKED` prevents double-claims

**Monitoring**: Track claim rate to detect DoS attacks

### 3. Device ID Validation

**Current**: Extracted from `X-Device-ID` header

**Hardening**: Consider JWT-bound device IDs to prevent spoofing

### 4. To-Device Message Limits

**Rate Limiting**: Implement per-device limits (e.g., 1000 messages/day)

**Size Limits**: Cap message content at 64KB

---

## Testing Plan

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_register_device() {
        // Test device registration returns valid X25519 keys
    }

    #[tokio::test]
    async fn test_upload_one_time_keys() {
        // Test key generation and storage
    }

    #[tokio::test]
    async fn test_claim_key_atomicity() {
        // Verify single-use guarantee under concurrent claims
    }

    #[tokio::test]
    async fn test_to_device_message_delivery() {
        // Test message queueing and retrieval
    }
}
```

### Integration Tests

```bash
# Register device
curl -X POST http://localhost:8080/api/v1/e2ee/devices \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"device_id": "test-device", "device_name": "Test Device"}'

# Upload keys
curl -X POST http://localhost:8080/api/v1/e2ee/keys/upload \
  -H "Authorization: Bearer $JWT" \
  -H "X-Device-ID: test-device" \
  -H "Content-Type: application/json" \
  -d '{"count": 10}'

# Query keys
curl -X POST http://localhost:8080/api/v1/e2ee/keys/query \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"user_ids": ["user-uuid"]}'
```

---

## Performance Considerations

### 1. Key Generation

- **Batch Generation**: Generate one-time keys in batches of 50-100
- **Background Job**: Pre-generate keys when count drops below threshold

### 2. Database Queries

- **Indexes**: All critical paths have covering indexes
- **Pagination**: Implement cursor-based pagination for to-device messages

### 3. Cleanup Jobs

```rust
// Background job to delete old claimed keys
async fn cleanup_old_keys(pool: &Pool<Postgres>) {
    sqlx::query(
        "DELETE FROM one_time_keys
         WHERE claimed = TRUE AND claimed_at < NOW() - INTERVAL '30 days'"
    )
    .execute(pool)
    .await
    .ok();
}

// Cleanup old to-device messages
async fn cleanup_old_messages(pool: &Pool<Postgres>) {
    sqlx::query(
        "DELETE FROM to_device_messages
         WHERE created_at < NOW() - INTERVAL '7 days'"
    )
    .execute(pool)
    .await
    .ok();
}
```

---

## Monitoring & Metrics

### Key Metrics

1. **Device Registration Rate**: `e2ee_device_registrations_total`
2. **One-Time Key Stock**: `e2ee_one_time_keys_available{user_id, device_id}`
3. **Key Claim Rate**: `e2ee_key_claims_total{success/failure}`
4. **To-Device Message Queue Depth**: `e2ee_to_device_messages_pending{user_id}`

### Alerts

- Key stock below 10 for any device
- Claim failure rate > 5%
- To-device queue depth > 1000

---

## Future Enhancements

### 1. Cross-Signing

Implement Ed25519 signing keys for device verification:

```rust
pub struct SigningKeys {
    pub master_key: [u8; 32],
    pub self_signing_key: [u8; 32],
    pub user_signing_key: [u8; 32],
}
```

### 2. Key Backup

Implement encrypted key backup using secret sharing:

```rust
POST /api/v1/e2ee/backup/keys
GET  /api/v1/e2ee/backup/keys/{version}
```

### 3. Device Verification

QR code-based device verification:

```rust
POST /api/v1/e2ee/devices/{device_id}/verify
```

---

## References

- **Matrix E2EE Spec**: https://spec.matrix.org/v1.5/client-server-api/#end-to-end-encryption
- **Signal Protocol**: https://signal.org/docs/
- **X25519**: RFC 7748 - Elliptic Curves for Security
- **NaCl Crypto**: https://nacl.cr.yp.to/
