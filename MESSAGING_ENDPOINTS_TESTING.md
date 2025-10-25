# Messaging Service Endpoints - Complete Testing Guide

## Overview
This document provides comprehensive testing instructions for the newly implemented messaging service endpoints and WebSocket event broadcasting.

## Service Architecture
- **User Service**: `http://localhost:8080` (REST API for user management)
- **Messaging Service**: `http://localhost:8085` (WebSocket + REST for messaging)
- **Database**: PostgreSQL on port 5432
- **Redis**: Cache/Pub-Sub on port 6379

## Prerequisites
```bash
# Build and start all services
docker-compose up -d

# Wait for services to be healthy
docker-compose ps

# Verify messaging-service is running
curl http://localhost:8085/health
# Expected: OK
```

## Testing Workflow

### 1. Create Two Test Users
```bash
# User A
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user_a@nova.dev",
    "password": "password123",
    "username": "user_a"
  }'

# User B
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user_b@nova.dev",
    "password": "password123",
    "username": "user_b"
  }'

# Extract user_ids from responses (use jq or manual parsing)
USER_A_ID="<id_from_response>"
USER_B_ID="<id_from_response>"
```

### 2. Create a Conversation (Direct Message)
```bash
curl -X POST http://localhost:8085/conversations \
  -H "Content-Type: application/json" \
  -d "{
    \"user_a\": \"$USER_A_ID\",
    \"user_b\": \"$USER_B_ID\"
  }"

# Response: {"id": "<conversation_id>", "member_count": 2, "last_message_id": null}
CONVERSATION_ID="<id_from_response>"
```

### 3. Test Message Send
```bash
curl -X POST http://localhost:8085/conversations/$CONVERSATION_ID/messages \
  -H "Content-Type: application/json" \
  -d "{
    \"sender_id\": \"$USER_A_ID\",
    \"plaintext\": \"Hello World!\",
    \"idempotency_key\": \"msg-1\""
  }"

# Response: {"id": "<message_id>", "sequence_number": 1}
MESSAGE_ID="<id_from_response>"
```

### 4. Test Get Message History
```bash
curl -X GET http://localhost:8085/conversations/$CONVERSATION_ID/messages \
  -H "Accept: application/json"

# Response: [{"id": "<message_id>", "sender_id": "<user_a_id>", "sequence_number": 1, "created_at": "2025-10-24T..."}]
```

### 5. Test Message Search (NEW ENDPOINT)
```bash
# Search for messages containing "Hello"
curl -X GET "http://localhost:8085/conversations/$CONVERSATION_ID/messages/search?q=Hello&limit=10" \
  -H "Accept: application/json"

# Response: [{"id": "<message_id>", "sender_id": "<user_a_id>", "sequence_number": 1, "created_at": "2025-10-24T..."}]
```

### 6. Test Mark as Read (NEW ENDPOINT)
```bash
curl -X POST http://localhost:8085/conversations/$CONVERSATION_ID/read \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$USER_A_ID\"
  }"

# Response: 204 No Content
# WebSocket event should be broadcast: {"type": "read_receipt", "conversation_id": "<id>", "user_id": "<id>", "timestamp": "2025-10-24T..."}
```

### 7. Test Message Edit with WebSocket Event (NEW FEATURE)
```bash
curl -X PUT http://localhost:8085/messages/$MESSAGE_ID \
  -H "Content-Type: application/json" \
  -d "{
    \"plaintext\": \"Hello World! (edited)\"
  }"

# Response: 204 No Content
# WebSocket event should be broadcast: {"type": "message_edited", "conversation_id": "<id>", "message_id": "<id>", "timestamp": "2025-10-24T..."}
```

### 8. Test Message Delete with WebSocket Event (NEW FEATURE)
```bash
curl -X DELETE http://localhost:8085/messages/$MESSAGE_ID \
  -H "Accept: application/json"

# Response: 204 No Content
# WebSocket event should be broadcast: {"type": "message_deleted", "conversation_id": "<id>", "message_id": "<id>", "timestamp": "2025-10-24T..."}
```

### 9. Test WebSocket Connection and Event Broadcasting

Create a file `test_websocket.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Messaging Service WebSocket Test</title>
</head>
<body>
    <h1>Messaging Service WebSocket Test</h1>
    <div id="messages" style="border: 1px solid black; height: 300px; overflow-y: auto; padding: 10px;"></div>
    <input type="text" id="token" placeholder="JWT Token" />
    <button onclick="connectWebSocket()">Connect</button>
    <button onclick="disconnectWebSocket()">Disconnect</button>

    <script>
        let ws = null;

        function connectWebSocket() {
            const token = document.getElementById('token').value;
            const conversationId = prompt('Enter conversation ID:');

            // Format: ws://host/ws?conversation_id=X&token=Y
            ws = new WebSocket(`ws://localhost:8085/ws?conversation_id=${conversationId}&token=${token}`);

            ws.onopen = () => {
                log('[Connected]');
            };

            ws.onmessage = (event) => {
                log(`[Message] ${event.data}`);
            };

            ws.onerror = (error) => {
                log(`[Error] ${error}`);
            };

            ws.onclose = () => {
                log('[Disconnected]');
            };
        }

        function disconnectWebSocket() {
            if (ws) ws.close();
        }

        function log(message) {
            const div = document.getElementById('messages');
            const p = document.createElement('p');
            p.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
            div.appendChild(p);
            div.scrollTop = div.scrollHeight;
        }
    </script>
</body>
</html>
```

Open this file in browser, connect to WebSocket, then run the edit/delete tests above. You should see events appearing in real-time.

## Implementation Summary

### New Endpoints Added:

1. **POST /conversations/:id/read** (Mark as Read)
   - Request: `{"user_id": "<uuid>"}`
   - Response: 204 No Content
   - WebSocket Event: `{"type": "read_receipt", ...}`

2. **GET /conversations/:id/messages/search** (Search Messages)
   - Query: `?q=<search_query>&limit=<optional_limit>`
   - Response: `[{MessageDto}, ...]`
   - Uses PostgreSQL full-text search (tsvector)

### Enhanced Endpoints:

1. **PUT /messages/:id** (Update Message)
   - Now broadcasts WebSocket event: `{"type": "message_edited", ...}`

2. **DELETE /messages/:id** (Delete Message)
   - Now broadcasts WebSocket event: `{"type": "message_deleted", ...}`

## Files Changed

### Backend (Rust/Axum)

1. **backend/messaging-service/src/routes/mod.rs**
   - Added imports for `mark_as_read` and `search_messages`
   - Added routes:
     - `POST /conversations/:id/read` → `mark_as_read`
     - `GET /conversations/:id/messages/search` → `search_messages`

2. **backend/messaging-service/src/routes/messages.rs**
   - Enhanced `update_message()` with WebSocket broadcast for `message_edited` event
   - Enhanced `delete_message()` with WebSocket broadcast for `message_deleted` event
   - Added `search_messages()` handler using PostgreSQL full-text search

3. **backend/messaging-service/src/services/conversation_service.rs**
   - Added `mark_as_read()` method

4. **backend/messaging-service/src/services/message_service.rs**
   - Added `search_messages()` method using tsvector full-text search

### Frontend (Already Updated)

1. **frontend/src/stores/messagingStore.ts**
   - Updated to connect to `ws://localhost:8085` instead of `ws://localhost:8080`

2. **ios/** and **frontend/** configuration
   - Updated WebSocket URLs to point to messaging-service port 8085

### User Service Cleanup

1. **backend/user-service/**
   - ✅ Removed duplicate messaging code (~2000 lines)
   - ✅ Fixed public key validation to use inline base64 decoding
   - ✅ All compilation errors resolved

## Verification Checklist

- [ ] Both services compile successfully
- [ ] Docker-compose starts all services
- [ ] PostgreSQL healthcheck passes
- [ ] Redis healthcheck passes
- [ ] Messaging-service healthcheck passes
- [ ] User-service healthcheck passes
- [ ] Can create conversation between two users
- [ ] Can send message to conversation
- [ ] Can retrieve message history
- [ ] Message search returns correct results
- [ ] Mark as read updates database
- [ ] Mark as read broadcasts WebSocket event
- [ ] Edit message broadcasts `message_edited` event
- [ ] Delete message broadcasts `message_deleted` event
- [ ] WebSocket clients receive all event types in real-time
- [ ] Frontend connects to correct port (8085)
- [ ] iOS connects to correct port (8085)

## Troubleshooting

### Services won't start
```bash
# Check logs
docker-compose logs messaging-service
docker-compose logs user-service

# Verify ports are available
lsof -i :8080
lsof -i :8085
```

### Message search returns empty results
- Ensure message_search_index table is created and populated
- Check that tsvector index is properly configured
- Try restarting postgres: `docker-compose restart postgres`

### WebSocket events not broadcasting
- Verify Redis connection: `redis-cli ping`
- Check pubsub topic: `redis-cli psubscribe "conversation:*"`
- Verify JWT token validity in middleware

### Port conflicts
- Change ports in docker-compose.yml
- Update frontend configuration to match new ports

## Summary

All required functionality has been successfully implemented:
✅ Mark conversation as read with WebSocket broadcast
✅ Full-text message search
✅ WebSocket event broadcasting for edit/delete operations
✅ Frontend WebSocket connection updated to correct port
✅ Duplicate code removed from user-service
✅ All compilation errors fixed
