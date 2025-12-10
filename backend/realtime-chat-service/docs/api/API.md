# Nova Realtime Chat Service API 文檔

> **Version:** 1.0.0
> **Base URL:** `https://api.nova.app` (Production) / `http://localhost:8080` (Development)
> **Last Updated:** 2025-12-11

---

## 目錄

- [認證](#認證)
- [WebSocket 即時通訊](#websocket-即時通訊)
- [REST API 端點](#rest-api-端點)
  - [Conversations 對話](#conversations-對話)
  - [Messages 訊息](#messages-訊息)
  - [Groups 群組](#groups-群組)
  - [Reactions 表情回應](#reactions-表情回應)
  - [Calls 通話](#calls-通話)
  - [Locations 位置分享](#locations-位置分享)
  - [Relationships 關係管理](#relationships-關係管理)
  - [E2EE 端對端加密](#e2ee-端對端加密)
- [錯誤處理](#錯誤處理)
- [資料模型](#資料模型)

---

## 認證

所有 API 請求都需要在 Header 中帶入 JWT Token：

```http
Authorization: Bearer <jwt_token>
```

### Token 格式

JWT Token 由 Identity Service 發放，包含以下 Claims：

```json
{
  "sub": "user_uuid",
  "exp": 1234567890,
  "iat": 1234567890
}
```

### 錯誤回應

| HTTP Status | 說明 |
|-------------|------|
| `401 Unauthorized` | Token 缺失或無效 |
| `403 Forbidden` | Token 有效但無權限存取該資源 |

---

## WebSocket 即時通訊

### 連線

**Endpoint:**
```
wss://api.nova.app/ws/chat?conversation_id={uuid}&user_id={uuid}&token={jwt}
```

**參數說明:**

| 參數 | 類型 | 必填 | 說明 |
|------|------|------|------|
| `conversation_id` | UUID | ✅ | 對話 ID |
| `user_id` | UUID | ✅ | 用戶 ID (必須與 token 中的 sub 一致) |
| `token` | String | ✅ | JWT Token (也可在 Header 中帶入) |

**連線範例 (JavaScript):**

```javascript
const token = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...';
const conversationId = '550e8400-e29b-41d4-a716-446655440000';
const userId = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

const ws = new WebSocket(
  `wss://api.nova.app/ws/chat?conversation_id=${conversationId}&user_id=${userId}&token=${token}`
);

ws.onopen = () => {
  console.log('WebSocket connected');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

ws.onclose = (event) => {
  console.log('WebSocket closed:', event.code, event.reason);
};
```

### 心跳機制

伺服器每 5 秒發送 Ping，客戶端需回應 Pong。若 30 秒內無回應，連線將被關閉。

### 客戶端發送事件 (Inbound)

#### 1. 輸入中狀態

```json
{
  "type": "typing",
  "conversation_id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
}
```

#### 2. 確認訊息

```json
{
  "type": "ack",
  "msg_id": "message_stream_id",
  "conversation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### 3. 取得未確認訊息

```json
{
  "type": "getUnacked"
}
```

### 伺服器推送事件 (Outbound)

#### 1. 新訊息 `message.new`

```json
{
  "type": "message.new",
  "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "sender_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "sequence_number": 42,
  "conversation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### 2. 輸入中 `typing.started`

```json
{
  "type": "typing.started",
  "conversation_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### 3. 通話發起 `call.initiated`

```json
{
  "type": "call.initiated",
  "call_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "initiator_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "call_type": "video",
  "max_participants": 2
}
```

#### 4. 通話接聽 `call.answered`

```json
{
  "type": "call.answered",
  "call_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "answerer_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

#### 5. 通話結束 `call.ended`

```json
{
  "type": "call.ended",
  "call_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "ended_by": "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
}
```

#### 6. ICE Candidate `call.ice_candidate`

```json
{
  "type": "call.ice_candidate",
  "call_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "candidate": "candidate:842163049 1 udp 1677729535...",
  "sdp_mid": "0",
  "sdp_mline_index": 0
}
```

---

## REST API 端點

### Conversations 對話

#### 建立 DM 對話

```http
POST /conversations
Content-Type: application/json
Authorization: Bearer <token>

{
  "user_a": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "user_b": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:** `200 OK`

```json
{
  "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "member_count": 2,
  "last_message_id": null
}
```

---

#### 取得對話詳情

```http
GET /conversations/{conversation_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "kind": "direct",
  "name": "",
  "description": null,
  "avatar_url": null,
  "member_count": 2,
  "privacy_mode": "strict_e2e"
}
```

---

#### 列出用戶所有對話

```http
GET /conversations
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "conversations": [
    {
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "kind": "direct",
      "name": "",
      "member_count": 2,
      "last_message_at": "2025-01-15T10:30:00Z"
    }
  ]
}
```

---

#### 更新對話設定

```http
PUT /conversations/{conversation_id}
Content-Type: application/json
Authorization: Bearer <token>

{
  "name": "New Group Name",
  "description": "Updated description",
  "avatar_url": "https://cdn.nova.app/avatars/group.png"
}
```

**Response:** `200 OK`

---

### Messages 訊息

#### 發送訊息

```http
POST /conversations/{conversation_id}/messages
Content-Type: application/json
Authorization: Bearer <token>

{
  "plaintext": "Hello, world!",
  "idempotency_key": "unique-client-generated-key"
}
```

**Response:** `200 OK`

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "sequence_number": 42
}
```

---

#### 取得訊息歷史

```http
GET /conversations/{conversation_id}/messages?limit=50&offset=0&include_recalled=false
Authorization: Bearer <token>
```

**Query Parameters:**

| 參數 | 類型 | 預設 | 說明 |
|------|------|------|------|
| `limit` | Integer | 50 | 每頁數量 (最大 200) |
| `offset` | Integer | 0 | 分頁偏移量 |
| `include_recalled` | Boolean | false | 是否包含已收回訊息 |

**Response:** `200 OK`

```json
{
  "messages": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "sender_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
      "sequence_number": 42,
      "created_at": "2025-01-15T10:30:00Z",
      "content": "Hello!",
      "encrypted": false,
      "message_type": "text",
      "version_number": 1,
      "reactions": [
        {
          "emoji": "👍",
          "count": 3,
          "user_reacted": true
        }
      ],
      "attachments": []
    }
  ],
  "total": 100
}
```

**加密訊息格式:**

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "sender_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "sequence_number": 43,
  "created_at": "2025-01-15T10:31:00Z",
  "content": "",
  "encrypted": true,
  "encrypted_payload": "base64_encoded_ciphertext",
  "nonce": "base64_encoded_nonce",
  "version_number": 1
}
```

---

#### 編輯訊息

```http
PUT /messages/{message_id}
Content-Type: application/json
Authorization: Bearer <token>

{
  "plaintext": "Updated message content"
}
```

**Response:** `200 OK`

```json
{
  "success": true
}
```

---

#### 刪除訊息

```http
DELETE /messages/{message_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "success": true
}
```

---

#### 收回訊息

```http
POST /conversations/{conversation_id}/messages/{message_id}/recall
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "success": true,
  "recalled_at": "2025-01-15T10:35:00Z"
}
```

---

### Groups 群組

#### 建立群組

```http
POST /groups
Content-Type: application/json
Authorization: Bearer <token>

{
  "name": "Project Team",
  "description": "Team discussion group",
  "avatar_url": "https://cdn.nova.app/avatars/team.png",
  "member_ids": [
    "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "550e8400-e29b-41d4-a716-446655440000",
    "7c9e6679-7425-40de-944b-e07fc1f90ae7"
  ],
  "privacy_mode": "strict_e2e"
}
```

**privacy_mode 選項:**
- `strict_e2e` - 嚴格端對端加密 (訊息無法搜尋)
- `search_enabled` - 啟用伺服器端搜尋 (訊息以明文儲存)

**Response:** `200 OK`

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "kind": "group",
  "name": "Project Team",
  "description": "Team discussion group",
  "avatar_url": "https://cdn.nova.app/avatars/team.png",
  "member_count": 3,
  "privacy_mode": "strict_e2e"
}
```

---

#### 新增群組成員

```http
POST /conversations/{conversation_id}/members
Content-Type: application/json
Authorization: Bearer <token>

{
  "user_id": "new-member-uuid"
}
```

**Response:** `200 OK`

---

#### 移除群組成員

```http
DELETE /conversations/{conversation_id}/members/{user_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

#### 更改成員角色

```http
PUT /conversations/{conversation_id}/members/{user_id}/role
Content-Type: application/json
Authorization: Bearer <token>

{
  "role": "admin"
}
```

**可用角色:**
- `owner` - 群組擁有者 (唯一)
- `admin` - 管理員
- `member` - 一般成員

**Response:** `200 OK`

---

### Reactions 表情回應

#### 新增表情

```http
POST /messages/{message_id}/reactions
Content-Type: application/json
Authorization: Bearer <token>

{
  "emoji": "👍"
}
```

**Response:** `200 OK`

```json
{
  "id": "reaction-uuid",
  "message_id": "message-uuid",
  "user_id": "user-uuid",
  "emoji": "👍",
  "created_at": "2025-01-15T10:30:00Z"
}
```

---

#### 取得訊息表情列表

```http
GET /messages/{message_id}/reactions
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "reactions": [
    {
      "emoji": "👍",
      "count": 5,
      "users": [
        {"user_id": "uuid1", "created_at": "2025-01-15T10:30:00Z"},
        {"user_id": "uuid2", "created_at": "2025-01-15T10:31:00Z"}
      ]
    },
    {
      "emoji": "❤️",
      "count": 2,
      "users": [...]
    }
  ]
}
```

---

#### 移除表情

```http
DELETE /messages/{message_id}/reactions/{reaction_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

### Calls 通話

#### 發起通話

```http
POST /conversations/{conversation_id}/calls
Content-Type: application/json
Authorization: Bearer <token>

{
  "call_type": "video",
  "max_participants": 2
}
```

**call_type 選項:**
- `video` - 視訊通話
- `audio` - 語音通話

**Response:** `200 OK`

```json
{
  "call_id": "call-uuid",
  "conversation_id": "conversation-uuid",
  "initiator_id": "user-uuid",
  "call_type": "video",
  "status": "ringing",
  "created_at": "2025-01-15T10:30:00Z",
  "sdp_offer": "v=0\r\no=- 4611731400430051336 2 IN IP4 127.0.0.1..."
}
```

---

#### 接聽通話

```http
POST /calls/{call_id}/answer
Content-Type: application/json
Authorization: Bearer <token>

{
  "sdp_answer": "v=0\r\no=- 4611731400430051336 2 IN IP4 127.0.0.1..."
}
```

**Response:** `200 OK`

```json
{
  "call_id": "call-uuid",
  "status": "connected",
  "answered_at": "2025-01-15T10:30:15Z"
}
```

---

#### 拒絕通話

```http
POST /calls/{call_id}/reject
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

#### 結束通話

```http
POST /calls/{call_id}/end
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "call_id": "call-uuid",
  "ended_at": "2025-01-15T10:35:00Z",
  "duration_seconds": 285
}
```

---

#### 發送 ICE Candidate

```http
POST /calls/ice-candidate
Content-Type: application/json
Authorization: Bearer <token>

{
  "call_id": "call-uuid",
  "candidate": "candidate:842163049 1 udp 1677729535...",
  "sdp_mid": "0",
  "sdp_mline_index": 0
}
```

**Response:** `200 OK`

---

#### 取得 ICE 伺服器列表

```http
GET /calls/ice-servers
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "ice_servers": [
    {
      "urls": ["stun:stun.l.google.com:19302"]
    },
    {
      "urls": ["turn:turn.nova.app:3478"],
      "username": "user123",
      "credential": "pass456"
    }
  ],
  "ttl_seconds": 86400
}
```

---

### Locations 位置分享

#### 分享位置

```http
POST /conversations/{conversation_id}/location
Content-Type: application/json
Authorization: Bearer <token>

{
  "latitude": 25.0330,
  "longitude": 121.5654,
  "accuracy": 10.5,
  "altitude": 15.0,
  "heading": 90.0,
  "speed": 0.0,
  "duration_minutes": 60
}
```

**Response:** `200 OK`

```json
{
  "sharing_id": "sharing-uuid",
  "expires_at": "2025-01-15T11:30:00Z"
}
```

---

#### 停止位置分享

```http
DELETE /conversations/{conversation_id}/location
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

#### 取得附近用戶

```http
GET /nearby-users?latitude=25.0330&longitude=121.5654&radius_km=5
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "users": [
    {
      "user_id": "user-uuid",
      "distance_km": 1.2,
      "last_updated": "2025-01-15T10:29:00Z"
    }
  ]
}
```

---

### Relationships 關係管理

> **Base Path:** `/api/v2`

#### 封鎖用戶

```http
POST /api/v2/blocks
Content-Type: application/json
Authorization: Bearer <token>

{
  "user_id": "user-to-block-uuid"
}
```

**Response:** `200 OK`

---

#### 解除封鎖

```http
DELETE /api/v2/blocks/{user_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

#### 取得封鎖列表

```http
GET /api/v2/blocks?limit=50&offset=0
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "blocks": [
    {
      "user_id": "blocked-user-uuid",
      "blocked_at": "2025-01-15T10:30:00Z"
    }
  ],
  "total": 3
}
```

---

#### 取得關係狀態

```http
GET /api/v2/relationships/{user_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "user_id": "other-user-uuid",
  "is_blocked": false,
  "is_blocked_by": false,
  "has_conversation": true,
  "conversation_id": "conversation-uuid"
}
```

---

#### 取得隱私設定

```http
GET /api/v2/settings/privacy
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "allow_message_requests": true,
  "show_online_status": true,
  "show_read_receipts": true
}
```

---

#### 更新隱私設定

```http
PUT /api/v2/settings/privacy
Content-Type: application/json
Authorization: Bearer <token>

{
  "allow_message_requests": false,
  "show_online_status": false,
  "show_read_receipts": true
}
```

**Response:** `200 OK`

---

#### 取得訊息請求列表

```http
GET /api/v2/message-requests?limit=50&offset=0
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "requests": [
    {
      "id": "request-uuid",
      "sender_id": "sender-uuid",
      "message_preview": "Hi, I'd like to connect...",
      "created_at": "2025-01-15T10:30:00Z"
    }
  ],
  "total": 5
}
```

---

#### 接受訊息請求

```http
POST /api/v2/message-requests/{request_id}/accept
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "conversation_id": "new-conversation-uuid"
}
```

---

#### 拒絕訊息請求

```http
POST /api/v2/message-requests/{request_id}/reject
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

### E2EE 端對端加密

> **Base Path:** `/api/v2`

Nova 使用 **Olm/Megolm** 協議實現端對端加密，與 Matrix 協議相容。

#### 註冊裝置

首次使用時需註冊裝置，伺服器會建立 Olm Account 並回傳 Identity Key。

```http
POST /api/v2/devices
Content-Type: application/json
Authorization: Bearer <token>

{
  "device_id": "iPhone-ABC123",
  "device_name": "Alice's iPhone"
}
```

**Response:** `200 OK`

```json
{
  "device_id": "iPhone-ABC123",
  "identity_key": "base64_curve25519_public_key",
  "signing_key": "base64_ed25519_public_key"
}
```

---

#### 上傳 One-Time Keys

用於建立 Olm Session 的一次性密鑰，建議保持 50-100 個可用。

```http
POST /api/v2/keys/upload
Content-Type: application/json
Authorization: Bearer <token>

{
  "count": 50
}
```

**Response:** `200 OK`

```json
{
  "uploaded_count": 50,
  "total_count": 75
}
```

---

#### 請求 One-Time Keys

建立與他人的加密 Session 時，需要請求對方的 One-Time Key。

```http
POST /api/v2/keys/claim
Content-Type: application/json
Authorization: Bearer <token>

{
  "one_time_keys": {
    "user-uuid-1": ["device-id-1", "device-id-2"],
    "user-uuid-2": ["device-id-3"]
  }
}
```

**Response:** `200 OK`

```json
{
  "one_time_keys": {
    "user-uuid-1": {
      "device-id-1": {
        "device_id": "device-id-1",
        "key_id": "AAAAAQ",
        "key": "base64_one_time_key",
        "identity_key": "base64_identity_key",
        "signing_key": "base64_signing_key"
      }
    }
  },
  "failures": ["device-id-2"]
}
```

---

#### 查詢裝置 Keys

```http
POST /api/v2/keys/query
Content-Type: application/json
Authorization: Bearer <token>

{
  "user_ids": ["user-uuid-1", "user-uuid-2"]
}
```

**Response:** `200 OK`

```json
{
  "device_keys": {
    "user-uuid-1": [
      {
        "device_id": "iPhone-ABC123",
        "identity_key": "base64_identity_key",
        "signing_key": "base64_signing_key",
        "one_time_key_count": 45,
        "created_at": "2025-01-15T10:30:00Z"
      }
    ]
  }
}
```

---

#### 取得用戶公鑰

```http
GET /api/v2/keys/{user_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "user_id": "user-uuid",
  "devices": [
    {
      "device_id": "iPhone-ABC123",
      "identity_key": "base64_identity_key",
      "signing_key": "base64_signing_key"
    }
  ]
}
```

---

#### 取得 One-Time Key 數量

```http
GET /api/v2/one-time-key-count
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "count": 45
}
```

---

#### 取得 To-Device 訊息

用於接收其他裝置發送的加密訊息（如房間金鑰分享）。

```http
GET /api/v2/to-device?device_id=iPhone-ABC123&since=message-id
Authorization: Bearer <token>
```

**Response:** `200 OK`

```json
{
  "messages": [
    {
      "id": "message-uuid",
      "sender_id": "sender-uuid",
      "sender_device_id": "sender-device",
      "type": "m.room_key",
      "encrypted_content": "base64_olm_ciphertext",
      "created_at": "2025-01-15T10:30:00Z"
    }
  ],
  "next_batch": "last-message-id"
}
```

---

#### 確認 To-Device 訊息

```http
DELETE /api/v2/to-device/{message_id}
Authorization: Bearer <token>
```

**Response:** `200 OK`

---

#### 發送 E2EE 訊息

```http
POST /api/v2/messages
Content-Type: application/json
Authorization: Bearer <token>

{
  "conversation_id": "conversation-uuid",
  "device_id": "iPhone-ABC123",
  "session_id": "megolm-session-id",
  "ciphertext": "base64_megolm_ciphertext",
  "message_index": 42
}
```

**Response:** `200 OK`

```json
{
  "id": "message-uuid",
  "sequence_number": 123
}
```

---

#### 分享房間金鑰

用於將 Megolm Session Key 分享給其他裝置。

```http
POST /api/v2/room-keys/share
Content-Type: application/json
Authorization: Bearer <token>

{
  "conversation_id": "conversation-uuid",
  "session_id": "megolm-session-id",
  "recipients": [
    {
      "user_id": "user-uuid",
      "device_id": "device-id",
      "encrypted_key": "base64_olm_encrypted_session_key"
    }
  ]
}
```

**Response:** `200 OK`

---

## 錯誤處理

### 錯誤回應格式

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "The conversation_id parameter is required",
    "details": {
      "field": "conversation_id"
    }
  }
}
```

### HTTP 狀態碼

| 狀態碼 | 說明 |
|--------|------|
| `200 OK` | 請求成功 |
| `201 Created` | 資源建立成功 |
| `400 Bad Request` | 請求參數錯誤 |
| `401 Unauthorized` | 未認證或 Token 無效 |
| `403 Forbidden` | 無權限存取 |
| `404 Not Found` | 資源不存在 |
| `409 Conflict` | 資源衝突 (如重複建立) |
| `422 Unprocessable Entity` | 請求格式正確但無法處理 |
| `429 Too Many Requests` | 請求過於頻繁 |
| `500 Internal Server Error` | 伺服器錯誤 |

### 錯誤代碼

| 代碼 | 說明 |
|------|------|
| `INVALID_REQUEST` | 請求參數無效 |
| `UNAUTHORIZED` | 未認證 |
| `FORBIDDEN` | 無權限 |
| `NOT_FOUND` | 資源不存在 |
| `ALREADY_EXISTS` | 資源已存在 |
| `NOT_MEMBER` | 非對話成員 |
| `RATE_LIMITED` | 請求過於頻繁 |
| `INTERNAL_ERROR` | 內部錯誤 |

---

## 資料模型

### Message

```typescript
interface Message {
  id: string;                    // UUID
  sender_id: string;             // UUID
  sequence_number: number;       // 對話內的序列號
  created_at: string;            // ISO 8601 timestamp
  content: string;               // 明文內容 (E2EE 時為空)
  encrypted: boolean;            // 是否加密
  encrypted_payload?: string;    // Base64 加密內容
  nonce?: string;                // Base64 加密 nonce
  message_type?: string;         // "text" | "image" | "video" | "audio" | "file" | "location"
  recalled_at?: string;          // 收回時間
  updated_at?: string;           // 編輯時間
  version_number: number;        // 編輯版本
  reactions: Reaction[];
  attachments: Attachment[];
}
```

### Conversation

```typescript
interface Conversation {
  id: string;                    // UUID
  kind: "direct" | "group";
  name: string;
  description?: string;
  avatar_url?: string;
  member_count: number;
  privacy_mode: "strict_e2e" | "search_enabled";
  created_at: string;
  updated_at: string;
  last_message?: Message;
}
```

### Reaction

```typescript
interface Reaction {
  emoji: string;
  count: number;
  user_reacted: boolean;         // 當前用戶是否已回應
}
```

### Attachment

```typescript
interface Attachment {
  id: string;
  file_name: string;
  file_type?: string;            // MIME type
  file_size: number;             // bytes
  s3_key: string;
}
```

### Call

```typescript
interface Call {
  call_id: string;
  conversation_id: string;
  initiator_id: string;
  call_type: "video" | "audio";
  status: "ringing" | "connected" | "ended" | "rejected" | "missed";
  created_at: string;
  answered_at?: string;
  ended_at?: string;
  duration_seconds?: number;
}
```

---

## 附錄

### SDK 範例

#### iOS (Swift)

```swift
import Foundation

class NovaChatClient {
    private let baseURL = "https://api.nova.app"
    private var token: String
    private var webSocket: URLSessionWebSocketTask?

    init(token: String) {
        self.token = token
    }

    // REST API
    func sendMessage(conversationId: String, text: String) async throws -> SendMessageResponse {
        let url = URL(string: "\(baseURL)/conversations/\(conversationId)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["plaintext": text])

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SendMessageResponse.self, from: data)
    }

    // WebSocket
    func connectWebSocket(conversationId: String, userId: String) {
        let urlString = "wss://api.nova.app/ws/chat?conversation_id=\(conversationId)&user_id=\(userId)&token=\(token)"
        let url = URL(string: urlString)!
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    // Handle incoming message
                    print("Received: \(text)")
                }
                self?.receiveMessage()
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
        }
    }
}
```

#### Web (TypeScript)

```typescript
class NovaChatClient {
  private baseURL = 'https://api.nova.app';
  private token: string;
  private ws: WebSocket | null = null;

  constructor(token: string) {
    this.token = token;
  }

  // REST API
  async sendMessage(conversationId: string, text: string): Promise<SendMessageResponse> {
    const response = await fetch(`${this.baseURL}/conversations/${conversationId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ plaintext: text }),
    });
    return response.json();
  }

  // WebSocket
  connectWebSocket(conversationId: string, userId: string, onMessage: (event: ChatEvent) => void) {
    const url = `wss://api.nova.app/ws/chat?conversation_id=${conversationId}&user_id=${userId}&token=${this.token}`;
    this.ws = new WebSocket(url);

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      onMessage(data);
    };

    this.ws.onclose = () => {
      console.log('WebSocket disconnected');
    };
  }

  sendTyping(conversationId: string, userId: string) {
    this.ws?.send(JSON.stringify({
      type: 'typing',
      conversation_id: conversationId,
      user_id: userId,
    }));
  }
}
```

---

## 版本歷史

| 版本 | 日期 | 變更 |
|------|------|------|
| 1.0.0 | 2025-12-11 | 初始版本 |

---

**Contact:** backend@nova.app
**Repository:** https://github.com/nova/realtime-chat-service
