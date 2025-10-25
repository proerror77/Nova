# WebSocket API

Endpoint: `GET /ws`

Authentication: Bearer token (passed via `Authorization` header in initial HTTP upgrade or via `?token=` query parameter for dev only).

## Message Types

All frames are JSON objects with a `type` field.

### Client → Server

- type: `send`
  - conversation_id: UUID
  - content_encrypted: base64
  - content_nonce: base64
  - idempotency_key: UUID (optional)

- type: `typing`
  - conversation_id: UUID
  - is_typing: boolean

### Server → Client

- type: `message`
  - message: Message (summary payload)

- type: `ack`
  - idempotency_key: UUID
  - status: `accepted` | `duplicate`

- type: `typing`
  - conversation_id: UUID
  - user_id: UUID
  - is_typing: boolean

## Message Payload (summary)

```json
{
  "id": "a11c...",
  "conversation_id": "c02d...",
  "sender_id": "u77e...",
  "created_at": "2025-10-22T10:00:00Z",
  "reaction_count": 0
}
```

Notes:
- Strict E2E conversations are never decrypted server-side; content is opaque to server.
- Broadcast fanout uses Redis channels `conversation:{id}` for horizontal scale.

