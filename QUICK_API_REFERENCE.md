# Nova Backend - Quick API Reference for Frontend & Mobile Teams

**Last Updated**: October 25, 2025

---

## Service Endpoints

```
User Service:      http://localhost:8080/api/v1
Messaging Service: http://localhost:8085
Search Service:    http://localhost:8081/api/v1
```

---

## Authentication

All authenticated endpoints require:
```
Authorization: Bearer <jwt_access_token>
```

### Get Tokens
```
POST /auth/login
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
→ {access_token, refresh_token, expires_in: 900}
```

### Refresh Tokens (when expired)
```
POST /auth/refresh
{"refresh_token": "..."}
→ {access_token, refresh_token}
```

---

## Most Common Endpoints

### Auth
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/auth/register` | Create account |
| POST | `/auth/login` | Get JWT tokens |
| POST | `/auth/verify-email` | Verify email address |
| POST | `/auth/refresh` | Get new access token |
| POST | `/auth/logout` | Revoke session |

### User Profile
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/users/me` | Get logged-in user |
| GET | `/users/{id}` | Get any public profile |
| PATCH | `/users/me` | Update profile |
| POST | `/users/{id}/follow` | Follow user |
| DELETE | `/users/{id}/follow` | Unfollow user |

### Feed
| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/feed?limit=20` | Get personalized feed |
| POST | `/feed/invalidate` | Clear feed cache |

### Posts
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/posts` | Create post |
| GET | `/posts/{id}` | Get post details |
| POST | `/posts/{id}/comments` | Add comment |
| GET | `/posts/{id}/comments` | List comments |
| POST | `/posts/{id}/like` | Like post |
| DELETE | `/posts/{id}/like` | Unlike post |

### Messages (Separate Service: port 8085)
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/conversations` | Start conversation |
| GET | `/conversations/{id}` | Get conversation |
| POST | `/conversations/{id}/messages` | Send message |
| GET | `/conversations/{id}/messages` | Get message history |
| POST | `/conversations/{id}/read` | Mark as read |
| WS | `/ws` | WebSocket (real-time) |

### Videos
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/videos/upload/init` | Start upload |
| PUT | `/uploads/{id}/chunks/{n}` | Upload chunk |
| POST | `/videos/upload/complete` | Finish upload |
| GET | `/videos/{id}` | Get video details |
| GET | `/videos/{id}/progress` | Check encoding status |
| POST | `/videos/{id}/like` | Like video |

### Streaming
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/streams` | Start live stream |
| GET | `/streams` | List live streams |
| GET | `/streams/{id}` | Get stream details |
| POST | `/streams/{id}/join` | Join stream |
| WS | `/ws/streams/{id}/chat` | Stream chat |

### Stories
| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/stories` | Create story |
| GET | `/stories/{id}` | Get story |
| DELETE | `/stories/{id}` | Delete story |
| PATCH | `/stories/{id}/privacy` | Update privacy |

---

## Error Codes

| Status | Code | Meaning |
|--------|------|---------|
| 200 | OK | Success |
| 201 | Created | Resource created |
| 204 | No Content | Success, no body |
| 400 | BadRequest | Invalid input |
| 401 | Unauthorized | Missing/invalid token |
| 403 | Forbidden | No permission |
| 404 | NotFound | Resource doesn't exist |
| 409 | Conflict | Duplicate (e.g., email taken) |
| 429 | TooManyRequests | Rate limited (100/15min) |
| 500 | Internal | Server error |

### Common Error Response
```json
{
  "error": "error_code",
  "message": "Human readable message",
  "details": "Optional additional info"
}
```

---

## Request/Response Examples

### Login → Get Feed → Get Post
```bash
# 1. Login
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"SecurePass123!"}'
# Response: {access_token: "eyJ...", refresh_token: "eyJ...", expires_in: 900}

# 2. Get Feed (using access_token from step 1)
curl -X GET "http://localhost:8080/api/v1/feed?limit=20" \
  -H "Authorization: Bearer eyJ..."
# Response: {posts: ["uuid1", "uuid2", ...], cursor: "...", has_more: true}

# 3. Get Post Details
curl -X GET "http://localhost:8080/api/v1/posts/uuid1" \
  -H "Authorization: Bearer eyJ..."
# Response: {id, user_id, caption, status, created_at, engagement: {views, likes, comments}}
```

### Upload Video (3 steps)
```bash
# 1. Initialize upload
curl -X POST http://localhost:8080/api/v1/videos/upload/init \
  -H "Authorization: Bearer eyJ..." \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "myvideo.mp4",
    "content_type": "video/mp4",
    "file_size": 52428800
  }'
# Response: {upload_session_id: "...", presigned_urls: [...], chunk_size: 5242880}

# 2. Upload each chunk
for chunk_index in {0..9}; do
  curl -X PUT "http://localhost:8080/api/v1/uploads/{upload_session_id}/chunks/${chunk_index}" \
    -H "Authorization: Bearer eyJ..." \
    --data-binary "@chunk_${chunk_index}.bin"
done

# 3. Complete upload
curl -X POST http://localhost:8080/api/v1/videos/upload/complete \
  -H "Authorization: Bearer eyJ..." \
  -H "Content-Type: application/json" \
  -d '{
    "upload_session_id": "...",
    "file_hash": "sha256_hash_here"
  }'
# Response: {video_id: "...", status: "processing"}
```

### Send Message with E2E Encryption
```bash
# 1. Get recipient's public key
curl -X GET http://localhost:8080/api/v1/users/{recipient_id}/public-key

# 2. Encrypt message client-side with recipient's public key
encrypted_content = encrypt_with_public_key(plaintext, public_key)
nonce = random_nonce()

# 3. Send encrypted message
curl -X POST "http://localhost:8085/conversations/{conversation_id}/messages" \
  -H "Authorization: Bearer eyJ..." \
  -H "Content-Type: application/json" \
  -d '{
    "plaintext": "Hello!",
    "idempotency_key": "optional_for_deduplication"
  }'
# Response: {id: "...", sequence_number: 42}
```

### Real-Time Messaging with WebSocket
```javascript
// Connect to messaging WebSocket
const ws = new WebSocket("ws://localhost:8085/ws");

// Authenticate
ws.onopen = () => {
  ws.send(JSON.stringify({
    type: "authenticate",
    token: "eyJ..."
  }));
};

// Subscribe to conversation
ws.send(JSON.stringify({
  type: "subscribe",
  conversation_id: "conversation-uuid"
}));

// Listen for incoming messages
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === "message") {
    console.log("New message:", msg);
  } else if (msg.type === "read_receipt") {
    console.log("User read message at:", msg.timestamp);
  }
};

// Send message
ws.send(JSON.stringify({
  type: "message",
  conversation_id: "conversation-uuid",
  text: "Hello there!"
}));

ws.close();
```

---

## Data Models (Quick Reference)

### User
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "username": "john_doe",
  "display_name": "John Doe",
  "bio": "Developer",
  "avatar_url": "https://...",
  "private_account": false,
  "created_at": "2025-10-25T10:30:45Z"
}
```

### Post
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "caption": "Text content",
  "status": "published",
  "content_type": "image",
  "created_at": "2025-10-25T10:30:45Z",
  "engagement": {
    "views": 1500,
    "likes": 120,
    "comments": 45
  }
}
```

### Message
```json
{
  "id": "uuid",
  "sender_id": "uuid",
  "plaintext": "Message text (decrypted on client)",
  "created_at": "2025-10-25T10:30:45Z"
}
```

### Video
```json
{
  "id": "uuid",
  "creator_id": "uuid",
  "title": "Video Title",
  "status": "published",
  "duration_seconds": 120,
  "hls_manifest_url": "https://...",
  "created_at": "2025-10-25T10:30:45Z"
}
```

### Stream
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "title": "Stream Title",
  "status": "live",
  "viewer_count": 250,
  "hls_url": "https://...",
  "rtmp_url": "rtmp://..."
}
```

---

## Pagination

### Offset-Based (Posts, Comments)
```
GET /posts/{id}/comments?limit=20&offset=0
→ {comments: [...], total_count: 50, limit: 20, offset: 0}

Next page: offset += limit
```

### Cursor-Based (Feed)
```
GET /feed?limit=20&cursor=<base64_encoded_offset>
→ {posts: [...], cursor: "...", has_more: true}

Next page: use cursor from response
```

---

## Rate Limiting

- **Global**: 100 requests per 15 minutes per IP/user
- **Response Header**: `X-RateLimit-Remaining: 99`
- **When Exceeded**: 429 status with retry-after header

```javascript
if (response.status === 429) {
  const retryAfter = response.headers['retry-after']; // seconds
  await sleep(retryAfter * 1000);
  // retry request
}
```

---

## WebSocket Connections

### Messaging WebSocket
```
ws://localhost:8085/ws
Authentication: JWT token required
Reconnect on disconnect for reliability
```

### Stream Chat WebSocket
```
ws://localhost:8080/ws/streams/{stream_id}/chat
Authentication: JWT token required
Auto-close when leaving stream
```

---

## Storage & Files

### Image Upload
1. Get presigned URL from `/posts/upload/init`
2. PUT image to presigned URL
3. POST to `/posts/upload/complete` with file hash

### Video Upload
1. GET presigned chunk URLs from `/videos/upload/init`
2. PUT each chunk to its URL
3. POST to `/videos/upload/complete` with full file hash

### S3 CDN Patterns
```
Avatars:   https://cdn.nova.local/avatars/{user_id}/...
Images:    https://cdn.nova.local/posts/{post_id}/...
Videos:    https://cdn.nova.local/videos/{video_id}/...
Streams:   https://cdn.nova.local/streams/{stream_id}/...
HLS:       https://cdn.nova.local/streams/{stream_id}/playlist.m3u8
RTMP:      rtmp://stream.nova.local/live
```

---

## Search

### Full-Text Search (PostgreSQL)
```
GET /search/users?q=john&limit=20
GET /search/posts?q=sunset&limit=20
GET /search/hashtags?q=travel&limit=20
```

### Trending
```
GET /trending               # All trending
GET /trending/videos        # Trending videos
GET /trending/posts         # Trending posts
GET /trending/streams       # Trending streams
GET /trending/categories    # Popular categories
```

---

## Development Tips

### Token Expiry Handling
```javascript
// When you get a 401, refresh token
if (response.status === 401) {
  const newTokens = await refreshToken(currentRefreshToken);
  localStorage.setItem('access_token', newTokens.access_token);
  localStorage.setItem('refresh_token', newTokens.refresh_token);
  // retry original request
}
```

### Offline Message Queue (Mobile)
```javascript
// Save unsent messages locally
if (!isOnline) {
  localQueue.push({conversation_id, message, timestamp});
} else {
  // Send queued messages when reconnected
  for (const item of localQueue) {
    await sendMessage(item);
  }
  localQueue = [];
}
```

### Idempotent Requests
```bash
# Use idempotency_key to prevent duplicates on retry
curl -X POST /conversations/{id}/messages \
  -H "Content-Type: application/json" \
  -d '{
    "plaintext": "Message",
    "idempotency_key": "unique-value-per-request"
  }'
```

### Cursor Pagination Example
```javascript
let cursor = null;
let hasMore = true;

while (hasMore) {
  const params = new URLSearchParams({limit: 20});
  if (cursor) params.append('cursor', cursor);
  
  const response = await fetch(`/feed?${params}`);
  const data = await response.json();
  
  posts.push(...data.posts);
  hasMore = data.has_more;
  cursor = data.cursor;
}
```

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Token expired or invalid | Call `/auth/refresh` with refresh_token |
| 403 Forbidden | Email not verified | Verify email first |
| 404 Not Found | Resource deleted or ID wrong | Check ID is correct UUID |
| 409 Conflict | Email/username taken | Use different email/username |
| 429 Too Many Requests | Rate limit exceeded | Wait before retrying |
| 500 Internal Error | Server bug | Contact support, check service status |

---

## Useful Endpoints for Testing

```bash
# Health check (no auth needed)
curl http://localhost:8080/api/v1/health

# Get JWKS public keys for token verification
curl http://localhost:8080/.well-known/jwks.json

# Check if search service is running
curl http://localhost:8081/health

# Prometheus metrics (user-service only)
curl http://localhost:8080/metrics
```

---

**For complete API documentation, see** `NOVA_API_REFERENCE.md`

