# Nova Backend API Documentation Index

Generated: October 25, 2025

---

## Documentation Files

### For Frontend & Mobile Teams (START HERE)
```
📄 QUICK_API_REFERENCE.md (516 lines)
   ├─ Service endpoints overview
   ├─ Authentication patterns
   ├─ Most common 50 endpoints in table format
   ├─ Copy-paste curl examples
   ├─ Error codes quick reference
   ├─ Data model summaries
   ├─ Pagination patterns
   ├─ WebSocket quick start
   ├─ Development tips & best practices
   └─ Troubleshooting guide

   👉 USE THIS IF: You're implementing client code and need quick answers
   💾 SIZE: ~350 KB
   ⏱️ READ TIME: 15-20 minutes
```

### For Complete Technical Reference
```
📄 NOVA_API_REFERENCE.md (1,895 lines)
   ├─ Complete service architecture
   ├─ All 100+ REST endpoints documented
   ├─ Request/response examples for every endpoint
   ├─ Detailed JWT & security implementation
   ├─ E2E message encryption specs
   ├─ Data models (7 core models)
   ├─ Error handling specifications
   ├─ WebSocket protocol details
   ├─ Rate limiting strategy
   ├─ Deployment & configuration (30+ env vars)
   ├─ Integration patterns (5 detailed)
   ├─ Performance characteristics
   └─ Best practices & troubleshooting

   👉 USE THIS IF: You need deep technical details or implementing backend integrations
   💾 SIZE: ~33 MB
   ⏱️ READ TIME: 45-60 minutes
```

### For Overview & Summary
```
📄 API_DOCUMENTATION_SUMMARY.md (557 lines)
   ├─ Service architecture overview
   ├─ Technology stack
   ├─ Endpoint categories summary
   ├─ Key features overview
   ├─ Response format patterns
   ├─ Rate limiting & error handling summary
   ├─ Data models overview (7 core)
   ├─ WebSocket protocols summary
   ├─ Deployment checklist
   ├─ Integration patterns summary
   ├─ Performance characteristics
   ├─ Common issues & solutions
   ├─ Best practices checklist
   └─ Next steps for each team

   👉 USE THIS IF: You need a high-level overview or are planning integration
   💾 SIZE: ~15 KB
   ⏱️ READ TIME: 15 minutes
```

---

## Quick Navigation by Role

### Frontend Engineer
1. Start: `QUICK_API_REFERENCE.md` (Authentication, Feed, Posts sections)
2. Reference: `NOVA_API_REFERENCE.md` (User Service API section)
3. Troubleshoot: Jump to "Troubleshooting" in QUICK_API_REFERENCE.md

**Key Sections**:
- Authentication → User Service API → Feed Endpoints
- Error handling → HTTP Status Codes
- WebSocket protocols → Messaging WebSocket
- Development tips → Token expiry handling

### iOS Developer
1. Start: `QUICK_API_REFERENCE.md` (Full document, focus on encryption)
2. Reference: `NOVA_API_REFERENCE.md` (Messaging Service API, End-to-End Encryption)
3. Deep dive: `API_DOCUMENTATION_SUMMARY.md` (Message Encryption pattern)

**Key Sections**:
- Authentication → OAuth Integration (Apple sign-in)
- Messaging Service API → Send Message → E2E Encryption
- WebSocket protocols → Messaging WebSocket
- Development tips → Offline message queue
- Video endpoints → Video Upload

### Backend Engineer
1. Start: `API_DOCUMENTATION_SUMMARY.md` (Full overview)
2. Reference: `NOVA_API_REFERENCE.md` (All services)
3. Implement: Cross-reference with source code in `backend/`

**Key Sections**:
- Service architecture
- Data models (all 7)
- Deployment & configuration
- Integration patterns
- Performance characteristics
- Environment variables (30+)

### DevOps/Deployment
1. Start: `API_DOCUMENTATION_SUMMARY.md` (Deployment section)
2. Reference: `NOVA_API_REFERENCE.md` (Deployment & Configuration)
3. Monitor: Health check endpoints

**Key Sections**:
- Deployment & Configuration
- Environment variables (all required)
- Docker deployment
- Health checks (3 types)
- Monitoring & metrics

### QA/Testing
1. Start: `QUICK_API_REFERENCE.md` (Error codes, testing endpoints)
2. Reference: `NOVA_API_REFERENCE.md` (Error handling section)
3. Tools: `QUICK_API_REFERENCE.md` (Testing endpoints at bottom)

**Key Sections**:
- Error codes reference
- Common integration issues
- Testing endpoints
- Rate limiting behavior
- WebSocket connections

---

## Service Quick Reference

### User Service (Port 8080)
```
Base: http://localhost:8080/api/v1

Auth              POST /auth/login, /auth/register, /auth/refresh
User Profile      GET /users/me, GET /users/{id}, PATCH /users/me
Relationships     POST /users/{id}/follow, DELETE /users/{id}/follow
Feed              GET /feed
Posts             POST /posts, GET /posts/{id}, Like/Comment
Videos            POST /videos/upload/init, GET /videos/{id}
Stories           POST /stories, GET /stories/{id}
Streaming         POST /streams, GET /streams, WS /ws/streams/{id}/chat
Search            GET /search/users, /search/posts
Trending          GET /trending, /trending/videos
```

### Messaging Service (Port 8085)
```
Base: http://localhost:8085

Conversations     POST /conversations, GET /conversations/{id}
Messages          POST /conversations/{id}/messages
Message History   GET /conversations/{id}/messages
Reactions         POST /messages/{id}/reactions
WebSocket         WS /ws
```

### Search Service (Port 8081)
```
Base: http://localhost:8081/api/v1

Full-Text         GET /search/users, /search/posts, /search/hashtags
Cache             POST /search/clear-cache
```

---

## Endpoint Categories & Count

| Category | Count | Key Endpoints |
|----------|-------|---------------|
| Authentication | 8 | register, login, refresh, verify-email, 2fa |
| User Management | 10 | profiles, follow, block, search, public-key |
| Feed | 2 | feed, invalidate |
| Posts | 8 | create, comments, likes |
| Messaging | 10 | conversations, messages, reactions, groups |
| Videos | 8 | upload, progress, similar, like, share |
| Stories | 7 | create, privacy, close-friends |
| Streaming | 8 | create, list, join, analytics, comments |
| Search | 3 | users, posts, hashtags |
| Trending | 5 | all, videos, posts, streams, categories |
| **WebSocket** | 2 | messaging, stream-chat |
| **Health** | 3 | general, readiness, liveness |
| **TOTAL** | **94+** | Complete REST + WebSocket |

---

## Data Models Reference

```
User             → id, email, username, display_name, bio, avatar
Post             → id, caption, image_key, status, engagement
Conversation     → id, type (direct/group), members, messages
Message          → id, encrypted_content, nonce, sequence_number
Video            → id, title, s3_key, hls_manifest_url, status
Stream           → id, title, rtmp_url, hls_url, viewer_count
Story            → id, media_url, privacy, expires_at
```

---

## Authentication Flows

### Standard Login
```
1. POST /auth/login → {access_token, refresh_token}
2. Store tokens securely
3. Use Authorization: Bearer <token> in requests
4. When 401: POST /auth/refresh → new tokens
```

### 2FA
```
1. POST /auth/2fa/enable → {temp_session_id, qr_code, secret, backup_codes}
2. POST /auth/2fa/confirm → confirm TOTP
3. User scans QR or enters secret manually
4. On login: POST /auth/2fa/verify → {access_token, refresh_token}
```

### OAuth (Apple/Google/Facebook)
```
1. Get oauth_token from provider
2. POST /auth/oauth/authorize → {access_token, refresh_token}
```

---

## WebSocket Quick Start

### Messaging WebSocket
```javascript
const ws = new WebSocket("ws://localhost:8085/ws");
ws.onopen = () => ws.send(JSON.stringify({
  type: "authenticate",
  token: "jwt_token"
}));
ws.onmessage = (e) => console.log(JSON.parse(e.data));
```

### Stream Chat WebSocket
```javascript
const ws = new WebSocket("ws://localhost:8080/ws/streams/stream-uuid/chat");
// Include JWT in query param or auth header
```

---

## Error Handling Patterns

### HTTP Status Codes
```
200 OK              ✓ Success
201 Created         ✓ Resource created
204 No Content      ✓ Success, no body
400 Bad Request     ✗ Invalid input
401 Unauthorized    ✗ Invalid/expired token
403 Forbidden       ✗ No permission
404 Not Found       ✗ Resource doesn't exist
409 Conflict        ✗ Duplicate (email, username)
429 Too Many Requests ✗ Rate limited
500 Internal Error  ✗ Server error
```

### Error Response Format
```json
{
  "error": "error_code",
  "message": "Human readable message",
  "details": "Optional additional info"
}
```

---

## Rate Limiting

- **Limit**: 100 requests per 15 minutes per IP/user
- **Headers**: `X-RateLimit-Remaining`, `Retry-After`
- **Strategy**: Token bucket algorithm in Redis
- **When Hit**: 429 status code

---

## Environment Variables (Key)

```
Database              DATABASE_URL, DATABASE_MAX_CONNECTIONS
Redis                 REDIS_URL
JWT                   JWT_PRIVATE_KEY_PEM, JWT_PUBLIC_KEY_PEM
Security              JWT_ACCESS_TOKEN_EXPIRY, JWT_REFRESH_TOKEN_EXPIRY
Email                 SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD
Storage               S3_BUCKET, S3_REGION, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY
Messaging             KAFKA_BROKERS, KAFKA_EVENTS_TOPIC
Analytics             CLICKHOUSE_URL, CLICKHOUSE_DATABASE
Vector Search         MILVUS_ENABLED, MILVUS_HOST, MILVUS_PORT
Graph (Optional)      GRAPH_ENABLED, GRAPH_NEO4J_URI
CORS                  CORS_ALLOWED_ORIGINS
```

---

## Testing Endpoints

```bash
# No authentication required
curl http://localhost:8080/api/v1/health

# Public key for token verification
curl http://localhost:8080/.well-known/jwks.json

# Prometheus metrics
curl http://localhost:8080/metrics

# Service health checks
curl http://localhost:8081/health      # Search
curl http://localhost:8085/health      # Messaging
```

---

## Common Integration Scenarios

### Scenario 1: User Registration & Login
Files: QUICK_API_REFERENCE.md (Auth section)
Steps: Register → Verify Email → Login → Store Tokens

### Scenario 2: Create & Share Post
Files: QUICK_API_REFERENCE.md (Posts section)
Steps: POST /posts → GET /feed → Share via messaging

### Scenario 3: Real-Time Messaging
Files: QUICK_API_REFERENCE.md (WebSocket) + NOVA_API_REFERENCE.md (E2E Encryption)
Steps: Get public key → Encrypt → Send → Receive → Decrypt

### Scenario 4: Video Upload & Streaming
Files: QUICK_API_REFERENCE.md (Video section)
Steps: Init upload → Upload chunks → Complete → Poll progress → Stream HLS

### Scenario 5: Live Streaming with Chat
Files: QUICK_API_REFERENCE.md (Streaming) + NOVA_API_REFERENCE.md (Stream Chat WebSocket)
Steps: Create stream → Get RTMP → Broadcast → Join stream → Chat via WebSocket

---

## Performance Tips

1. **Pagination**: Use cursor-based (base64 offsets) for infinite scroll
2. **Caching**: Cache feeds locally, invalidate on follow/unfollow
3. **Images**: Lazy-load with thumbnails, use CDN
4. **WebSocket**: Reconnect with exponential backoff
5. **Batch**: Group multiple requests when possible
6. **Rate Limit**: Implement exponential backoff on 429

---

## Documentation Maintenance

- **Last Updated**: October 25, 2025
- **Rust Version**: 1.76+
- **PostgreSQL**: 14+
- **Redis**: 7+
- **Total Lines**: 2,968 lines
- **Total Size**: ~58 KB

---

## Related Files in Repository

```
backend/
├── user-service/
│   ├── src/handlers/        ← HTTP handlers (25+)
│   ├── src/models/          ← Rust structs (20+)
│   └── src/services/        ← Business logic
├── messaging-service/
│   ├── src/routes/          ← REST routes (10+)
│   └── src/websocket/       ← WebSocket handlers
├── search-service/
│   └── src/                 ← Full-text search
└── migrations/              ← SQL schemas (40+)

frontend/
└── src/                     ← TypeScript/React code

ios/
└── Network/                 ← Swift networking code
```

---

## Quick Links

- **Start Here (Teams)**: `QUICK_API_REFERENCE.md`
- **Complete Reference**: `NOVA_API_REFERENCE.md`
- **Overview**: `API_DOCUMENTATION_SUMMARY.md`
- **Source Code**: `/Users/proerror/Documents/nova/backend/`

---

## Support

- **Health Status**: `/api/v1/health`
- **Metrics**: `/metrics` (user-service only)
- **Public Keys**: `/.well-known/jwks.json`
- **Rate Limit Headers**: Check response headers

---

**Total Documentation**: 2,968 lines covering 94+ endpoints, 7 core data models, 3 microservices, 2 WebSocket protocols, and complete deployment guide.

