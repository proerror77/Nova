# Messaging API Reference

Version: 1.0
Base URL: `https://api.nova.app/api/v1`
Authentication: JWT Bearer Token

## Overview

Private messaging API for 1:1 and group conversations with end-to-end encryption. All message content is encrypted client-side; the server only routes ciphertext.

**Key Features**:
- Direct (1:1) and group conversations
- End-to-end encryption (E2E)
- Real-time delivery via WebSocket
- Read receipts and typing indicators
- Cursor-based pagination

---

## Authentication

All API endpoints require authentication via JWT token in the `Authorization` header:

```http
Authorization: Bearer <your-jwt-token>
```

**Error Responses**:
- `401 Unauthorized`: Missing or invalid token
- `403 Forbidden`: User not authorized for this resource

---

## Conversations

### Create Conversation

Create a new conversation (1:1 or group).

**Endpoint**: `POST /conversations`

**Request Body**:
```json
{
  "type": "direct",  // or "group"
  "name": "Team Chat",  // Required for groups, null for direct
  "participant_ids": ["uuid-1", "uuid-2"]  // Array of user IDs to add
}
```

**Response** (201 Created):
```json
{
  "id": "conv-uuid",
  "type": "direct",
  "name": null,
  "created_by": "current-user-uuid",
  "created_at": "2025-10-19T12:00:00Z",
  "updated_at": "2025-10-19T12:00:00Z",
  "members": [
    {
      "user_id": "user-uuid-1",
      "username": "alice",
      "role": "owner",
      "joined_at": "2025-10-19T12:00:00Z"
    },
    {
      "user_id": "user-uuid-2",
      "username": "bob",
      "role": "member",
      "joined_at": "2025-10-19T12:00:00Z"
    }
  ]
}
```

**Validation Rules**:
- Direct conversations: Exactly 2 participants (creator + 1 other)
- Group conversations: Must have a name (max 255 chars)
- Participant IDs must be valid users
- Creator automatically becomes `owner`

**Idempotency**:
- For direct conversations: If a conversation already exists between the same two users, returns the existing conversation (200 OK)
- For group conversations: Always creates a new conversation

**Error Responses**:
- `400 Bad Request`: Invalid input (e.g., missing name for group, invalid participant IDs)
- `404 Not Found`: Participant user not found

---

### List Conversations

Get current user's conversations.

**Endpoint**: `GET /conversations`

**Query Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `limit` | integer | No | 20 | Items per page (max 100) |
| `offset` | integer | No | 0 | Pagination offset |
| `archived` | boolean | No | false | Include archived conversations |

**Example Request**:
```http
GET /conversations?limit=20&offset=0&archived=false
```

**Response** (200 OK):
```json
{
  "conversations": [
    {
      "id": "conv-uuid",
      "type": "direct",
      "name": null,
      "last_message": {
        "id": "msg-uuid",
        "sender_id": "user-uuid-1",
        "encrypted_content": "base64-ciphertext",
        "nonce": "base64-nonce",
        "created_at": "2025-10-19T12:30:00Z"
      },
      "unread_count": 3,
      "updated_at": "2025-10-19T12:30:00Z",
      "is_muted": false,
      "is_archived": false
    }
  ],
  "total": 42,
  "limit": 20,
  "offset": 0
}
```

**Sorting**:
- Conversations are sorted by `updated_at` (most recent first)
- `updated_at` is automatically updated when a new message is sent (via database trigger)

**Performance**:
- P95 latency: <150ms
- Uses optimized query with `LEFT JOIN LATERAL` for last_message

---

### Get Conversation

Get details of a specific conversation.

**Endpoint**: `GET /conversations/:conversation_id`

**Response** (200 OK):
```json
{
  "id": "conv-uuid",
  "type": "group",
  "name": "Team Chat",
  "created_by": "user-uuid-1",
  "created_at": "2025-10-19T10:00:00Z",
  "updated_at": "2025-10-19T12:30:00Z",
  "members": [
    {
      "user_id": "user-uuid-1",
      "username": "alice",
      "role": "owner",
      "joined_at": "2025-10-19T10:00:00Z"
    },
    {
      "user_id": "user-uuid-2",
      "username": "bob",
      "role": "member",
      "joined_at": "2025-10-19T10:05:00Z"
    }
  ]
}
```

**Error Responses**:
- `403 Forbidden`: User is not a member of this conversation
- `404 Not Found`: Conversation does not exist

---

### Update Conversation Settings

Update current user's settings for a conversation (mute, archive).

**Endpoint**: `PATCH /conversations/:conversation_id/settings`

**Request Body**:
```json
{
  "is_muted": true,
  "is_archived": false
}
```

**Response** (200 OK):
```json
{
  "is_muted": true,
  "is_archived": false
}
```

**Notes**:
- Both fields are optional; only provided fields are updated
- Settings are per-user (other members' settings are not affected)

---

### Add Group Members

Add members to a group conversation (owner/admin only).

**Endpoint**: `POST /conversations/:conversation_id/members`

**Request Body**:
```json
{
  "user_ids": ["user-uuid-3", "user-uuid-4"]
}
```

**Response** (200 OK):
```json
{
  "added_members": [
    {
      "user_id": "user-uuid-3",
      "username": "charlie",
      "role": "member",
      "joined_at": "2025-10-19T13:00:00Z"
    }
  ]
}
```

**Side Effects**:
- System message is sent: "Alice added Charlie to the group"
- Group encryption key is regenerated and distributed to all members (future feature)

**Error Responses**:
- `400 Bad Request`: Cannot add members to direct conversations
- `403 Forbidden`: Only owner/admin can add members
- `404 Not Found`: User not found

---

### Remove Group Member

Remove a member from a group conversation (owner/admin only, or self).

**Endpoint**: `DELETE /conversations/:conversation_id/members/:user_id`

**Response** (204 No Content)

**Authorization**:
- User can always remove themselves
- Only owner/admin can remove other members

**Side Effects**:
- System message is sent: "Alice removed Charlie" or "Charlie left the conversation"
- Group encryption key is regenerated (future feature)

**Error Responses**:
- `403 Forbidden`: User is not owner/admin and trying to remove someone else
- `404 Not Found`: Member not found

---

## Messages

### Send Message

Send a new message to a conversation.

**Endpoint**: `POST /messages`

**Request Body**:
```json
{
  "conversation_id": "conv-uuid",
  "encrypted_content": "base64-ciphertext",
  "nonce": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",  // 32 chars (24 bytes base64)
  "message_type": "text"  // or "system"
}
```

**Response** (201 Created):
```json
{
  "id": "msg-uuid",
  "conversation_id": "conv-uuid",
  "sender_id": "current-user-uuid",
  "encrypted_content": "base64-ciphertext",
  "nonce": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
  "message_type": "text",
  "created_at": "2025-10-19T13:05:00Z"
}
```

**Validation**:
- `encrypted_content`: Must be valid base64
- `nonce`: Must be exactly 32 characters (24 bytes base64-encoded)
- `message_type`: Must be "text" or "system"
- User must be a member of the conversation

**Side Effects**:
- Message published to Redis Pub/Sub: `conversation:{id}:messages`
- WebSocket server broadcasts to all online members
- `conversations.updated_at` is updated (via database trigger)

**Performance**:
- P95 latency: <200ms (including WebSocket broadcast)

**Error Responses**:
- `400 Bad Request`: Invalid encrypted_content or nonce
- `403 Forbidden`: User is not a member of the conversation

---

### Get Message History

Get message history for a conversation.

**Endpoint**: `GET /conversations/:conversation_id/messages`

**Query Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `limit` | integer | No | 50 | Items per page (max 100) |
| `before` | UUID | No | null | Cursor (message_id) for pagination |

**Example Request**:
```http
GET /conversations/conv-uuid/messages?limit=50&before=msg-uuid-50
```

**Response** (200 OK):
```json
{
  "messages": [
    {
      "id": "msg-uuid-1",
      "sender_id": "user-uuid-1",
      "encrypted_content": "base64-ciphertext",
      "nonce": "base64-nonce",
      "message_type": "text",
      "created_at": "2025-10-19T12:00:00Z"
    }
  ],
  "has_more": true,
  "next_cursor": "msg-uuid-50"
}
```

**Pagination**:
- Uses cursor-based pagination (more efficient than offset)
- Messages are sorted by `created_at DESC` (newest first)
- `before` cursor: Returns messages created before this message
- `next_cursor`: Use this value in the next request's `before` parameter

**Performance**:
- P95 latency: <100ms (50 messages)

**Error Responses**:
- `403 Forbidden`: User is not a member of the conversation
- `404 Not Found`: Cursor message not found

---

### Mark as Read

Mark messages as read in a conversation.

**Endpoint**: `POST /conversations/:conversation_id/read`

**Request Body**:
```json
{
  "message_id": "msg-uuid"
}
```

**Response** (200 OK):
```json
{
  "conversation_id": "conv-uuid",
  "last_read_message_id": "msg-uuid",
  "last_read_at": "2025-10-19T13:10:00Z"
}
```

**Side Effects**:
- Updates `conversation_members.last_read_message_id` and `last_read_at`
- Publishes read receipt event to Redis Pub/Sub: `conversation:{id}:read`
- WebSocket broadcasts to sender's devices (shows double checkmark)

**Error Responses**:
- `400 Bad Request`: Message does not belong to this conversation
- `403 Forbidden`: User is not a member of the conversation
- `404 Not Found`: Message not found

---

## WebSocket API

Real-time message delivery and typing indicators.

### Connection

**URL**: `wss://api.nova.app/ws?token=<jwt_token>`

**Authentication**: JWT token passed as query parameter (WebSocket doesn't support custom headers).

**Connection Established**:
```json
{
  "type": "connection.established",
  "data": {
    "user_id": "current-user-uuid",
    "connection_id": "conn-uuid"
  }
}
```

**Auto-Subscription**:
- Server automatically subscribes user to all their conversations
- Listens to: `conversation:{id}:messages`, `conversation:{id}:typing`, `conversation:{id}:read`

---

### Events: Server → Client

#### New Message

```json
{
  "type": "message.new",
  "data": {
    "id": "msg-uuid",
    "conversation_id": "conv-uuid",
    "sender_id": "user-uuid-1",
    "encrypted_content": "base64-ciphertext",
    "nonce": "base64-nonce",
    "message_type": "text",
    "created_at": "2025-10-19T13:15:00Z"
  }
}
```

**Client Action**:
1. Decrypt `encrypted_content` using `nonce` and sender's public key
2. Display plaintext in UI
3. Update conversation list (move to top)

---

#### Typing Indicator

```json
{
  "type": "typing.indicator",
  "data": {
    "conversation_id": "conv-uuid",
    "user_id": "user-uuid-1",
    "username": "alice",
    "is_typing": true
  }
}
```

**Client Action**:
- If `is_typing: true`: Show "Alice is typing..." in UI
- If `is_typing: false`: Hide typing indicator

---

#### Read Receipt

```json
{
  "type": "message.read",
  "data": {
    "conversation_id": "conv-uuid",
    "user_id": "user-uuid-2",
    "last_read_message_id": "msg-uuid"
  }
}
```

**Client Action**:
- Update UI to show double checkmark for read messages
- In 1:1 conversation: "Read"
- In group conversation: "Read by 3 people" (clickable to show list)

---

### Events: Client → Server

#### Typing Start

```json
{
  "type": "typing.start",
  "data": {
    "conversation_id": "conv-uuid"
  }
}
```

**Server Behavior**:
- Stores typing status in Redis with 3-second TTL
- Broadcasts `typing.indicator` event to other members

---

#### Typing Stop

```json
{
  "type": "typing.stop",
  "data": {
    "conversation_id": "conv-uuid"
  }
}
```

**Server Behavior**:
- Removes typing status from Redis
- Broadcasts `typing.indicator` with `is_typing: false`

**Note**: Typing status auto-expires after 3 seconds if client doesn't send `typing.stop`.

---

## Encryption

### Overview

All message content is encrypted client-side using **TweetNaCl** (NaCl = Networking and Cryptography Library).

- **Algorithm**: XSalsa20-Poly1305 (authenticated encryption)
- **Key Exchange**: X25519 Diffie-Hellman
- **Key Length**: 32 bytes (256 bits)
- **Nonce Length**: 24 bytes (192 bits)

### Key Management

#### 1. Identity Keys

Each user generates a long-term identity key pair:

```swift
import TweetNacl

let keyPair = NaclBox.keyPair()
let publicKey = keyPair.publicKey.base64EncodedString()  // Upload to server
let secretKey = keyPair.secretKey  // Store in Keychain, NEVER upload
```

**Upload Public Key**:
```http
POST /users/me/public-key
Content-Type: application/json

{
  "public_key": "base64-encoded-32-bytes"
}
```

#### 2. Session Keys (1:1 Conversations)

Use Diffie-Hellman to compute shared secret:

```swift
// Get recipient's public key
GET /users/:user_id/public-key

// Compute shared secret
let sharedSecret = NaclBox.before(
    publicKey: recipientPublicKey,
    secretKey: mySecretKey
)
```

#### 3. Group Keys

Group creator generates a shared symmetric key:

```swift
let groupKey = NaclSecretBox.key()  // 32 random bytes

// Encrypt group key for each member
for member in members {
    let encryptedKey = NaclBox.box(
        message: groupKey,
        nonce: NaclBox.nonce(),
        publicKey: member.publicKey,
        secretKey: mySecretKey
    )

    // Send to member (out of scope for Phase 1)
}
```

### Encrypting a Message

```swift
// 1. Get session key / group key
let key = getSessionKey(conversationId: conversationId)

// 2. Generate unique nonce
let nonce = NaclBox.nonce()  // 24 random bytes

// 3. Encrypt plaintext
let plaintext = "Hello, World!".data(using: .utf8)!
let ciphertext = NaclBox.box(
    message: plaintext,
    nonce: nonce,
    sharedSecret: key
)

// 4. Send to server
POST /messages
{
  "conversation_id": "conv-uuid",
  "encrypted_content": ciphertext.base64EncodedString(),
  "nonce": nonce.base64EncodedString()
}
```

### Decrypting a Message

```swift
// 1. Receive message from WebSocket
receiveMessage { message in
    let ciphertext = Data(base64Encoded: message.encrypted_content)!
    let nonce = Data(base64Encoded: message.nonce)!

    // 2. Get session key
    let key = getSessionKey(conversationId: message.conversation_id)

    // 3. Decrypt
    let plaintext = NaclBox.open(
        ciphertext: ciphertext,
        nonce: nonce,
        sharedSecret: key
    )

    // 4. Display
    let text = String(data: plaintext, encoding: .utf8)!
    displayMessage(text)
}
```

---

## Error Handling

### Standard Error Response

```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "Nonce must be exactly 32 characters",
    "details": {
      "field": "nonce",
      "value_length": 16
    }
  }
}
```

### Error Codes

| HTTP Status | Error Code | Description |
|-------------|------------|-------------|
| 400 | `INVALID_INPUT` | Request validation failed |
| 401 | `UNAUTHORIZED` | Missing or invalid JWT token |
| 403 | `FORBIDDEN` | User not authorized for this resource |
| 404 | `NOT_FOUND` | Resource does not exist |
| 409 | `CONFLICT` | Resource already exists (idempotency) |
| 429 | `RATE_LIMITED` | Too many requests |
| 500 | `INTERNAL_ERROR` | Server error |
| 503 | `SERVICE_UNAVAILABLE` | Server overloaded or maintenance |

---

## Rate Limiting

**Global Limit**: 100 requests per minute per user

**Headers**:
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1634678400
```

**429 Response**:
```json
{
  "error": {
    "code": "RATE_LIMITED",
    "message": "Too many requests. Retry after 60 seconds.",
    "retry_after": 60
  }
}
```

---

## Pagination

### Offset-Based (Conversations)

```http
GET /conversations?limit=20&offset=40
```

**Response**:
```json
{
  "conversations": [...],
  "total": 100,
  "limit": 20,
  "offset": 40
}
```

### Cursor-Based (Messages)

```http
GET /conversations/conv-uuid/messages?limit=50&before=msg-uuid-50
```

**Response**:
```json
{
  "messages": [...],
  "has_more": true,
  "next_cursor": "msg-uuid-100"
}
```

**Advantages of Cursor-Based**:
- Consistent results (no duplicates/skips when data changes)
- Better performance for large datasets
- Works well with time-based ordering

---

## Performance Targets

| Operation | P95 Latency | Throughput |
|-----------|-------------|------------|
| Send Message | <200ms | 100 msg/s |
| List Conversations | <150ms | - |
| Message History | <100ms | - |
| WebSocket Push | <50ms | - |

---

## Changelog

### v1.0 (2025-10-19)
- Initial API design
- Conversations CRUD
- Message sending/receiving
- WebSocket events
- E2E encryption support

---

## Support

For API issues or questions:
- **Documentation**: https://docs.nova.app/messaging
- **Support**: support@nova.app
- **Status Page**: https://status.nova.app
