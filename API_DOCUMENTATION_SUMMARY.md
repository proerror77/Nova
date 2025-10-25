# Nova Backend API Documentation - Summary

**Generated**: October 25, 2025  
**Scope**: Complete analysis of User Service, Messaging Service, and Search Service

---

## Overview

This documentation package provides comprehensive API references for the Nova social media platform backend, built with Rust microservices.

### Documentation Files

1. **`NOVA_API_REFERENCE.md`** (1,895 lines)
   - Complete technical API reference
   - All 100+ endpoints documented
   - Request/response examples for every endpoint
   - Error handling specifications
   - Data models with full details
   - WebSocket protocols
   - Environment configuration

2. **`QUICK_API_REFERENCE.md`** (350+ lines)
   - Quick reference for frontend & iOS teams
   - Common endpoints in table format
   - Copy-paste curl examples
   - Data model summaries
   - Practical development tips
   - Troubleshooting guide

---

## Service Architecture

### Three Microservices

| Service | Port | Framework | Purpose |
|---------|------|-----------|---------|
| **User Service** | 8080 | Actix-web | Auth, profiles, posts, feed, streaming, stories, videos |
| **Messaging Service** | 8085 | Axum | Real-time messaging, conversations, WebSocket |
| **Search Service** | 8081 | Axum | Full-text search (PostgreSQL) |

### Technology Stack
- **Language**: Rust 1.76+
- **Databases**: PostgreSQL 14+, Redis 7+
- **Message Queue**: Kafka (events, CDC)
- **Analytics**: ClickHouse
- **Vector Search**: Milvus
- **Graph DB**: Neo4j (optional)
- **Storage**: S3-compatible
- **Async Runtime**: Tokio

---

## Authentication & Security

### JWT Tokens
- **Access Token**: 15 minutes (RS256/RSA-2048)
- **Refresh Token**: 7 days
- **Public Keys**: Available at `/.well-known/jwks.json`
- **Algorithm**: RS256 (RSA signature) or HS256 (HMAC fallback)

### Message Encryption
- **Algorithm**: ChaCha20-Poly1305
- **Key Exchange**: RSA-2048
- **Per-Message Nonce**: 48-character hex string
- **Storage**: Encrypted plaintext + nonce

---

## API Endpoints Overview

### Authentication (8 endpoints)
- Register, Login, Verify Email
- Token Refresh, Logout
- 2FA (Enable, Confirm, Verify)
- OAuth (Apple, Google, Facebook)
- Password Reset

### User Management (10 endpoints)
- Get/Update Profile
- Follow/Block Users
- Get Followers/Following
- Public Key Management
- User Search

### Feed (2 endpoints)
- Get Personalized Feed (ClickHouse or timeline algo)
- Invalidate Feed Cache

### Posts (8 endpoints)
- Create, Get, Update, Delete
- Comments (Create, Update, Delete, List)
- Likes (Like, Unlike, Status, List)

### Messaging (10 endpoints)
- Conversations (Create, Get, List)
- Messages (Send, Get History, Update, Delete, Search)
- Read Receipts
- Message Reactions
- Group Management

### Videos (8 endpoints)
- Upload (Initialize, Chunk, Complete)
- Get Details, Progress, Processing
- Like, Share
- Similarity Search

### Stories (7 endpoints)
- Create, Get, List, Delete, Update Privacy
- Close Friends Management

### Streaming (8 endpoints)
- Create, List, Search, Get Details
- Join, Leave
- Analytics, Comments
- RTMP Auth/Webhooks

### Search (3 endpoints)
- User Search (Full-Text)
- Post Search (Full-Text)
- Hashtag Search

### Trending (5 endpoints)
- All Trending
- Videos, Posts, Streams
- Categories

### WebSocket (2 endpoints)
- Messaging WebSocket (Real-time)
- Stream Chat WebSocket

---

## Key Features Documented

### 1. Authentication Flow
```
Register → Verify Email → Login → Get Access/Refresh Tokens
→ Use Bearer token in Authorization header
→ When 401: Call /auth/refresh with refresh_token
```

### 2. Feed Generation
- **Algorithm Support**: ClickHouse (default) + Timeline fallback
- **Pagination**: Cursor-based (base64 encoded offsets)
- **Caching**: Redis cache with invalidation on follow/unfollow
- **Analytics**: Events sent to Kafka → ClickHouse

### 3. Real-Time Messaging
- **Transport**: WebSocket (Redis Pub/Sub for multi-instance)
- **Encryption**: E2E with RSA keys (ChaCha20-Poly1305)
- **Delivery**: Guaranteed with sequence numbers
- **Read Receipts**: Real-time via WebSocket broadcasts

### 4. Video Processing
- **Upload**: Resumable chunked uploads with presigned S3 URLs
- **Processing**: Queue-based with Kafka + job workers
- **HLS Streaming**: Adaptive bitrate (multiple quality levels)
- **Embedding**: Vector search via Milvus for similarity
- **Progress Tracking**: Real-time via polling endpoint

### 5. Live Streaming
- **RTMP Input**: Stream key authentication
- **HLS Output**: Multi-bitrate adaptive streaming
- **Chat**: WebSocket real-time comments
- **Viewers**: Real-time counter in Redis
- **Analytics**: Bitrate, quality, duration tracking

### 6. Search
- **Full-Text**: PostgreSQL tsvector + ranking
- **Caching**: Redis cache (24-hour TTL)
- **Hashtags**: Extracted from post captions
- **Trending**: Separate cache refresh jobs

---

## Response Format Consistency

### Success Response (200/201)
```json
{
  "id": "uuid",
  "field1": "value1",
  "field2": "value2",
  "created_at": "2025-10-25T10:30:45Z"
}
```

### Error Response
```json
{
  "error": "error_code",
  "message": "Human readable message",
  "details": "Optional additional context",
  "timestamp": "2025-10-25T10:30:45Z"
}
```

### Paginated Response
```json
{
  "items": [...],
  "total_count": 500,
  "limit": 20,
  "offset": 0
}
```

### Cursor-Paginated Response
```json
{
  "items": [...],
  "cursor": "base64_encoded_next_offset",
  "has_more": true,
  "total_count": 500
}
```

---

## Rate Limiting

- **Global Limit**: 100 requests per 15 minutes per IP/user
- **Response Header**: `X-RateLimit-Remaining: 99`
- **When Exceeded**: 429 status with `Retry-After` header
- **Strategy**: Token bucket algorithm in Redis

---

## Error Handling

### HTTP Status Codes
- **200**: Success
- **201**: Created
- **204**: No Content
- **400**: Bad Request
- **401**: Unauthorized (expired/invalid token)
- **403**: Forbidden (no permission)
- **404**: Not Found
- **409**: Conflict (duplicate email/username)
- **429**: Rate Limited
- **500**: Internal Server Error
- **503**: Service Unavailable

### Common Error Codes
```
AUTH_REQUIRED          - Missing JWT
INVALID_TOKEN          - Malformed JWT
USER_NOT_FOUND         - User doesn't exist
EMAIL_TAKEN            - Already registered
INVALID_PASSWORD       - Weak password
EMAIL_NOT_VERIFIED     - Verify first
ACCOUNT_LOCKED         - Too many failed logins
NOT_CONVERSATION_MEMBER - Not authorized
DATABASE_ERROR         - Query failed
VALIDATION_ERROR       - Invalid input
```

---

## Data Models (7 Core)

### 1. User
- Basic: id, email, username, password_hash
- Profile: display_name, bio, avatar_url, cover_photo_url, location
- Settings: private_account, email_verified, totp_enabled
- Metadata: created_at, updated_at, last_login_at, deleted_at

### 2. Post
- Content: id, user_id, caption, image_key, video_ids
- Status: status (published/draft/deleted), content_type (image/video/mixed)
- Metadata: created_at, updated_at, soft_delete
- Engagement: views, likes, comments (computed)

### 3. Conversation
- Type: direct or group
- Members: user list with roles (owner/admin/member)
- Messages: linked to messages table
- State: last_message_id, updated_at (for sorting)

### 4. Message
- Content: encrypted_content, nonce (ChaCha20-Poly1305)
- Metadata: sequence_number, created_at, edited_at, deleted_at
- Type: text or system
- Reactions: linked to reactions table

### 5. Video
- Content: title, description, s3_key
- Status: uploading → processing → published
- Streaming: hls_manifest_url, duration_seconds
- Visibility: public, friends, private
- Embedding: vector in Milvus for similarity

### 6. Stream
- Info: title, description, category
- Status: live or ended
- Access: rtmp_url, stream_key, hls_url
- Viewers: viewer_count (Redis), peak_viewers
- Quality: multiple bitrate levels

### 7. Story
- Content: media_url, caption
- Privacy: public, friends, close_friends, private
- Lifespan: created_at, expires_at (24 hours)
- Visibility: expires then auto-deleted

---

## WebSocket Protocols

### Messaging WebSocket (`ws://localhost:8085/ws`)
**Messages**:
- Type: "message" (client/server)
- Type: "read_receipt" (server)
- Type: "typing" (client)
- Type: "online_status" (server)

### Stream Chat WebSocket (`ws://localhost:8080/ws/streams/{id}/chat`)
**Messages**:
- Type: "message" (client sends, server broadcasts)
- Payload: comment object with id, stream_id, user_id, message, created_at

---

## Deployment & Configuration

### Environment Variables (30+ required)
```
APP_ENV                    - development|production
DATABASE_URL               - PostgreSQL connection
REDIS_URL                  - Redis connection
JWT_PRIVATE_KEY_PEM        - RSA private key
JWT_PUBLIC_KEY_PEM         - RSA public key
S3_BUCKET                  - AWS S3 bucket name
KAFKA_BROKERS              - Kafka broker list
CLICKHOUSE_URL             - Analytics database
MILVUS_ENABLED             - Vector search enabled
GRAPH_ENABLED              - Neo4j graph enabled
CORS_ALLOWED_ORIGINS       - CORS whitelist
SMTP_*                     - Email configuration
```

### Docker Deployment
- Dockerfile: Multi-stage build (builder + runtime)
- Docker Compose: All services + PostgreSQL + Redis
- Health Checks: Three probe types (general, readiness, liveness)

### Monitoring
- **Metrics**: Prometheus at `/metrics` (user-service)
- **Logging**: Structured JSON via `tracing` crate
- **Health**: `/health`, `/health/ready`, `/health/live`

---

## Integration Patterns

### 1. Authentication Flow
1. POST `/auth/login` → get tokens
2. Store access_token + refresh_token
3. Include `Authorization: Bearer <token>` in all requests
4. On 401: POST `/auth/refresh` → get new tokens
5. On token expiry (401): Automatic retry with fresh token

### 2. Feed Generation
1. GET `/feed?algo=ch&limit=20` → get post UUIDs
2. For each UUID: GET `/posts/{id}` → full details
3. Use `cursor` from response for pagination
4. POST `/feed/invalidate` when following/unfollowing

### 3. Message Encryption
1. GET `/users/{id}/public-key` → recipient's key
2. Client encrypts with recipient's public key
3. POST to `/conversations/{id}/messages` with plaintext
4. Server encrypts + stores with nonce
5. Recipient gets message, decrypts client-side

### 4. Video Upload
1. POST `/videos/upload/init` → get presigned URLs
2. Split file into chunks, upload each to S3
3. POST `/videos/upload/complete` with file hash
4. Poll GET `/videos/{id}/progress` until complete
5. GET `/videos/{id}/stream` for HLS manifest

### 5. Live Streaming
1. POST `/streams` → get RTMP URL + stream key
2. Broadcaster sends RTMP stream to URL
3. Server segments to HLS (multi-bitrate)
4. GET `/streams/{id}` → watch HLS stream
5. WS `/ws/streams/{id}/chat` → real-time chat

---

## Performance Characteristics

### Database
- **Connections**: 50 max (configurable)
- **Indices**: On all foreign keys + frequently queried fields
- **Migrations**: 40+ versions, auto-run on startup
- **Triggers**: Auto-update `updated_at` timestamps

### Caching
- **Feed Cache**: 2-hour TTL, invalidated on follow changes
- **Search Cache**: 24-hour TTL for queries
- **Session Cache**: In-memory Redis with 7-day TTL
- **User Cache**: Invalidated on profile updates

### Messaging
- **Sequence Numbers**: Prevent message duplication
- **Idempotency Keys**: Optional client-provided de-duplication
- **Read Receipts**: Real-time via WebSocket + Redis Pub/Sub

### Videos
- **Chunked Upload**: 5MB chunks, resumable
- **Processing**: Queue-based with retries
- **Storage**: S3 with CDN caching
- **Streaming**: Multi-bitrate HLS with adaptive selection

---

## Testing Endpoints

```bash
# Health (no auth)
curl http://localhost:8080/api/v1/health

# JWKS public keys
curl http://localhost:8080/.well-known/jwks.json

# Metrics
curl http://localhost:8080/metrics

# Search health
curl http://localhost:8081/health

# Messaging health
curl http://localhost:8085/health
```

---

## Common Integration Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 on every request | Token expired | Implement token refresh logic |
| 429 Too Many Requests | Rate limit hit | Add exponential backoff retry |
| Messages not received | WebSocket disconnected | Implement auto-reconnect with exponential backoff |
| Videos stuck "processing" | Transcoding failure | Check Kafka consumer logs, retry manually |
| Feed always empty | No followed users | Follow some accounts first |
| Search returns nothing | Cache not warmed | Wait 5 seconds, try again |

---

## Best Practices for Clients

### Security
1. Store tokens in secure storage (httpOnly cookies web, Keychain iOS)
2. Never log sensitive data
3. Validate SSL certificates
4. Implement token rotation
5. Use HTTPS only in production

### Performance
1. Implement pagination with cursors
2. Cache responses locally (especially posts, profiles)
3. Batch requests when possible
4. Use debouncing for search queries
5. Lazy-load images with thumbnails

### Reliability
1. Implement exponential backoff retries
2. Queue failed requests offline
3. Validate idempotency keys
4. Handle network timeouts gracefully
5. Monitor token expiration

### User Experience
1. Show loading states during requests
2. Implement pull-to-refresh for feeds
3. Show "typing" indicators in chat
4. Sync offline changes when reconnected
5. Provide helpful error messages

---

## File Organization

```
NOVA_API_REFERENCE.md          - Complete technical reference (1,895 lines)
QUICK_API_REFERENCE.md         - Quick guide for teams (350+ lines)
API_DOCUMENTATION_SUMMARY.md   - This file

backend/
├── user-service/src/
│   ├── handlers/              - 25+ HTTP request handlers
│   ├── models/                - 20+ Rust structs
│   ├── services/              - Business logic
│   └── middleware/            - Auth, CORS, rate limiting
├── messaging-service/src/
│   ├── routes/                - 10+ REST endpoints
│   ├── websocket/             - WebSocket protocol
│   └── services/              - Encryption, storage
├── search-service/src/
│   ├── routes/                - Full-text search
│   └── handlers/              - Search business logic
└── migrations/                - 40+ SQL migration files
```

---

## Next Steps for Integration

### Frontend Team
1. Review `QUICK_API_REFERENCE.md`
2. Implement token refresh logic
3. Set up API client with base URL routing
4. Test auth flow
5. Implement offline queue for messages

### iOS Team
1. Review messaging encryption details
2. Implement E2E decryption on client
3. Set up WebSocket reconnection
4. Implement local message queue
5. Test video upload with chunking

### Backend Team
1. Review service dependencies
2. Check database migration status
3. Verify environment variables
4. Monitor health endpoints
5. Test rate limiting behavior

---

## Document Maintenance

**Last Updated**: October 25, 2025  
**Rust Version**: 1.76+  
**PostgreSQL Version**: 14+  
**Redis Version**: 7+

---

## Support & Resources

- **API Health**: Check `/health` endpoints
- **JWKS Endpoint**: `/.well-known/jwks.json`
- **Metrics**: Prometheus at `/metrics`
- **Logs**: Structured JSON via tracing
- **Status**: GitHub Actions CI/CD

---

**Generated from**: Complete source code analysis of 3 Rust microservices, 40+ database migrations, 100+ REST endpoints, 2 WebSocket protocols, and 20+ core data models.

