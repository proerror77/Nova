# Nova Backend API Reference

**Version**: 0.1.0  
**Last Updated**: October 25, 2025  
**Format**: RESTful + WebSocket

---

## Table of Contents

1. [Service Overview](#service-overview)
2. [Authentication & Security](#authentication--security)
3. [Error Handling](#error-handling)
4. [User Service API](#user-service-api)
5. [Messaging Service API](#messaging-service-api)
6. [Search Service API](#search-service-api)
7. [Data Models](#data-models)
8. [WebSocket Protocols](#websocket-protocols)
9. [Deployment & Configuration](#deployment--configuration)

---

## Service Overview

### Architecture

Nova backend is a microservices architecture built with Rust, organized into three main services:

| Service | Port | Framework | Database | Purpose |
|---------|------|-----------|----------|---------|
| **User Service** | 8080 | Actix-web | PostgreSQL + Redis | Auth, profiles, posts, feed, streaming, stories, videos |
| **Messaging Service** | 8085 | Axum | PostgreSQL + Redis | Real-time messaging, conversations, WebSocket |
| **Search Service** | 8081 | Axum | PostgreSQL + Redis | Full-text search (users, posts, hashtags) |

### Technology Stack

- **Language**: Rust 1.76+
- **Async Runtime**: Tokio
- **Databases**: PostgreSQL 14+ (primary), Redis 7+ (cache/realtime)
- **Messaging**: Kafka (events, CDC)
- **Storage**: S3-compatible (images, videos)
- **Vector DB**: Milvus (video embeddings)
- **Analytics**: ClickHouse (feed ranking, events)
- **Caching**: Redis (sessions, cache)
- **Monitoring**: Prometheus + Grafana

---

## Authentication & Security

### JWT Token Structure

All authenticated endpoints require JWT Bearer tokens in the `Authorization` header:

```
Authorization: Bearer <jwt_token>
```

**Token Claims**:
```json
{
  "sub": "user-uuid",           // Subject: User ID
  "exp": 1735689600,             // Expiration timestamp
  "iat": 1735603200,             // Issued at timestamp
  "aud": "nova-app",             // Audience
  "iss": "nova-auth-service"     // Issuer
}
```

**Token Types**:
- **Access Token**: Short-lived (15 minutes)
- **Refresh Token**: Long-lived (7 days)

### Key Rotation

JWT signing uses RSA-256 (RS256) by default:
- Public Key: Retrieved from `/.well-known/jwks.json`
- Private Key: Stored in environment (`JWT_PRIVATE_KEY_PEM`)

### End-to-End Encryption (Messaging)

Messages are encrypted with ChaCha20-Poly1305:
- Each message has a unique nonce (48-character hex string)
- Plaintext is encrypted before storage
- Decryption happens on client side with sender's public key

---

## Error Handling

### Standard Error Response Format

All errors follow this structure:

```json
{
  "error": "error_code",
  "message": "Human-readable error message",
  "details": "Optional additional context",
  "timestamp": "2025-10-25T10:30:45Z"
}
```

### HTTP Status Codes

| Code | Meaning | Example |
|------|---------|---------|
| 200 | OK | Successful request |
| 201 | Created | Resource successfully created |
| 204 | No Content | Success with no response body |
| 400 | Bad Request | Invalid request parameters |
| 401 | Unauthorized | Missing or invalid JWT token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource not found |
| 409 | Conflict | Duplicate resource (e.g., user already exists) |
| 429 | Too Many Requests | Rate limit exceeded (100 req/15min per IP) |
| 500 | Internal Server Error | Server-side error |
| 503 | Service Unavailable | Database/external service down |

### Error Code Reference

```
AUTH_REQUIRED        - Missing JWT token
INVALID_TOKEN       - Malformed or expired token
USER_NOT_FOUND      - User ID doesn't exist
EMAIL_TAKEN         - Email already registered
INVALID_PASSWORD    - Password doesn't meet requirements
EMAIL_NOT_VERIFIED  - Email verification required
ACCOUNT_LOCKED      - Too many failed login attempts
CONVERSATION_NOT_FOUND - Conversation ID invalid
NOT_CONVERSATION_MEMBER - User not in conversation
DATABASE_ERROR      - Database operation failed
VALIDATION_ERROR    - Input validation failed
```

---

## User Service API

**Base URL**: `http://localhost:8080/api/v1`

### Health Checks

#### Get Health Status
```
GET /health
```

**Response** (200 OK):
```json
{
  "status": "healthy",
  "version": "0.1.0",
  "database": "connected",
  "redis": "connected",
  "timestamp": "2025-10-25T10:30:45Z"
}
```

#### Readiness Probe (Kubernetes)
```
GET /health/ready
```

#### Liveness Probe (Kubernetes)
```
GET /health/live
```

---

### Authentication Endpoints

#### Register New User
```
POST /auth/register
Content-Type: application/json
```

**Request**:
```json
{
  "email": "user@example.com",
  "username": "john_doe",
  "password": "SecurePass123!"
}
```

**Response** (201 Created):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "username": "john_doe",
  "message": "Registration successful. Please verify your email."
}
```

**Errors**: 400 (validation), 409 (email/username taken)

#### Login
```
POST /auth/login
Content-Type: application/json
```

**Request**:
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

**Errors**: 401 (invalid credentials), 403 (account locked/email not verified)

#### Refresh Access Token
```
POST /auth/refresh
Content-Type: application/json
```

**Request**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

**Errors**: 401 (invalid/expired refresh token)

#### Verify Email
```
POST /auth/verify-email
Content-Type: application/json
```

**Request**:
```json
{
  "token": "email_verification_token_from_email"
}
```

**Response** (200 OK):
```json
{
  "message": "Email verified successfully",
  "email_verified": true
}
```

#### Dev Verify Email (Development Only)
```
POST /auth/dev-verify
Content-Type: application/json
```

**Note**: Only available when `APP_ENV != production`

**Request**:
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000"
}
```
Or:
```json
{
  "email": "user@example.com"
}
```

#### Logout
```
POST /auth/logout
Authorization: Bearer <token>
```

**Response** (204 No Content)

#### Forgot Password
```
POST /auth/forgot-password
Content-Type: application/json
```

**Request**:
```json
{
  "email": "user@example.com"
}
```

**Response** (200 OK):
```json
{
  "message": "Password reset link sent to your email"
}
```

#### Reset Password
```
POST /auth/reset-password
Content-Type: application/json
```

**Request**:
```json
{
  "token": "password_reset_token",
  "password": "NewSecurePass123!"
}
```

**Response** (200 OK):
```json
{
  "message": "Password reset successfully"
}
```

### Two-Factor Authentication (2FA)

#### Enable 2FA
```
POST /auth/2fa/enable
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "password": "current_password"
}
```

**Response** (200 OK):
```json
{
  "temp_session_id": "temp_session_uuid",
  "qr_code": "<svg>QR Code SVG</svg>",
  "secret": "BASE32ENCODEDSECRET",
  "backup_codes": ["BACKUP-CODE-1", "BACKUP-CODE-2", ...],
  "expires_in": 600
}
```

#### Confirm 2FA
```
POST /auth/2fa/confirm
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "temp_session_id": "temp_session_uuid",
  "code": "123456"
}
```

**Response** (200 OK):
```json
{
  "message": "2FA enabled successfully",
  "two_fa_enabled": true
}
```

#### Verify 2FA Code
```
POST /auth/2fa/verify
Content-Type: application/json
```

**Request**:
```json
{
  "session_id": "temporary_session_id",
  "code": "123456"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

### OAuth Integration

#### Authorize
```
POST /auth/oauth/authorize
Content-Type: application/json
```

**Request**:
```json
{
  "provider": "apple",
  "token": "oauth_token_from_provider"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 900
}
```

**Supported Providers**: `apple`, `google`, `facebook`

#### Link OAuth Provider
```
POST /auth/oauth/link
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "provider": "apple",
  "token": "oauth_token"
}
```

#### Unlink OAuth Provider
```
DELETE /auth/oauth/link/{provider}
Authorization: Bearer <token>
```

---

### User Profile Endpoints

#### Get Current User
```
GET /users/me
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "john_doe",
  "email": "user@example.com",
  "display_name": "John Doe",
  "bio": "Software developer",
  "avatar_url": "https://cdn.example.com/avatars/user-123.jpg",
  "cover_photo_url": "https://cdn.example.com/covers/user-123.jpg",
  "location": "San Francisco, CA",
  "private_account": false,
  "created_at": "2025-01-15T08:30:00Z"
}
```

#### Get User Profile (Public)
```
GET /users/{user_id}
```

**Note**: Public endpoint, no auth required

**Response** (200 OK):
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "john_doe",
  "display_name": "John Doe",
  "bio": "Software developer",
  "avatar_url": "https://cdn.example.com/avatars/user-123.jpg",
  "cover_photo_url": "https://cdn.example.com/covers/user-123.jpg",
  "location": "San Francisco, CA",
  "private_account": false,
  "created_at": "2025-01-15T08:30:00Z"
}
```

#### Update User Profile
```
PATCH /users/me
Authorization: Bearer <token>
Content-Type: application/json
```

**Request** (all fields optional):
```json
{
  "display_name": "John D.",
  "bio": "Developer & Designer",
  "avatar_url": "https://cdn.example.com/new-avatar.jpg",
  "cover_photo_url": "https://cdn.example.com/new-cover.jpg",
  "location": "San Jose, CA",
  "private_account": true
}
```

**Response** (200 OK): Updated user object

#### Get User's Public Key
```
GET /users/{user_id}/public-key
```

**Response** (200 OK):
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhk...",
  "created_at": "2025-01-15T08:30:00Z"
}
```

#### Upsert My Public Key
```
PUT /users/me/public-key
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhk..."
}
```

**Response** (200 OK): Public key object

---

### Relationship Endpoints

#### Follow User
```
POST /users/{user_id}/follow
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "status": "followed"
}
```

**Errors**: 404 (user not found), 400 (cannot follow self)

#### Unfollow User
```
DELETE /users/{user_id}/follow
Authorization: Bearer <token>
```

**Response** (204 No Content)

#### Block User
```
POST /users/{user_id}/block
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "status": "blocked"
}
```

#### Unblock User
```
DELETE /users/{user_id}/block
Authorization: Bearer <token>
```

**Response** (204 No Content)

#### Get User's Followers
```
GET /users/{user_id}/followers?limit=20&offset=0
```

**Response** (200 OK):
```json
{
  "followers": [
    {
      "id": "uuid",
      "username": "follower1",
      "display_name": "Follower One",
      "avatar_url": "https://..."
    }
  ],
  "total_count": 100,
  "limit": 20,
  "offset": 0
}
```

#### Get User's Following
```
GET /users/{user_id}/following?limit=20&offset=0
```

**Response** (200 OK): Similar structure to followers

---

### Feed Endpoints

#### Get Personalized Feed
```
GET /feed?algo=ch&limit=20&cursor=base64_encoded_offset
Authorization: Bearer <token>
```

**Query Parameters**:
- `algo`: `"ch"` (ClickHouse, default) or `"time"` (timeline)
- `limit`: 1-100, default 20
- `cursor`: Optional base64-encoded offset for pagination

**Response** (200 OK):
```json
{
  "posts": [
    "post-uuid-1",
    "post-uuid-2"
  ],
  "cursor": "base64_encoded_next_offset",
  "has_more": true,
  "total_count": 500
}
```

#### Invalidate Feed Cache
```
POST /feed/invalidate
Authorization: Bearer <token>
```

**Response** (204 No Content)

---

### Post Endpoints

#### Create Post with Media
```
POST /posts
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "caption": "Amazing sunset!",
  "image_ids": ["presigned_upload_id_1"],
  "video_ids": []
}
```

**Response** (201 Created):
```json
{
  "id": "post-uuid",
  "user_id": "user-uuid",
  "caption": "Amazing sunset!",
  "content_type": "image",
  "status": "published",
  "created_at": "2025-10-25T10:30:45Z"
}
```

#### Get Post
```
GET /posts/{post_id}
Authorization: Bearer <token>
```

**Response** (200 OK): Post object with engagement metrics

#### Create Comment
```
POST /posts/{post_id}/comments
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "text": "Great post!"
}
```

**Response** (201 Created):
```json
{
  "id": "comment-uuid",
  "post_id": "post-uuid",
  "user_id": "user-uuid",
  "text": "Great post!",
  "created_at": "2025-10-25T10:30:45Z"
}
```

#### Get Comments
```
GET /posts/{post_id}/comments?limit=20&offset=0
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "comments": [...],
  "total_count": 50,
  "limit": 20,
  "offset": 0
}
```

#### Update Comment
```
PATCH /comments/{comment_id}
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "text": "Updated comment"
}
```

**Response** (200 OK): Updated comment object

#### Delete Comment
```
DELETE /comments/{comment_id}
Authorization: Bearer <token>
```

**Response** (204 No Content)

#### Like Post
```
POST /posts/{post_id}/like
Authorization: Bearer <token>
```

**Response** (201 Created):
```json
{
  "status": "liked"
}
```

#### Unlike Post
```
DELETE /posts/{post_id}/like
Authorization: Bearer <token>
```

**Response** (204 No Content)

#### Check Like Status
```
GET /posts/{post_id}/like/status
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "liked": true,
  "like_count": 50
}
```

#### Get Post Likes
```
GET /posts/{post_id}/likes?limit=20&offset=0
Authorization: Bearer <token>
```

**Response** (200 OK): List of users who liked

---

### Video Endpoints

#### Video Upload Initialize
```
POST /videos/upload/init
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "filename": "my_video.mp4",
  "content_type": "video/mp4",
  "file_size": 52428800
}
```

**Response** (200 OK):
```json
{
  "upload_session_id": "session-uuid",
  "presigned_urls": [
    {
      "chunk_index": 0,
      "url": "https://s3.example.com/...",
      "expires_at": "2025-10-25T11:30:45Z"
    }
  ],
  "chunk_size": 5242880
}
```

#### Upload Video Chunk
```
PUT /uploads/{upload_id}/chunks/{chunk_index}
Authorization: Bearer <token>
```

**Body**: Raw binary video chunk

**Response** (200 OK):
```json
{
  "chunk_index": 0,
  "status": "uploaded"
}
```

#### Complete Video Upload
```
POST /videos/upload/complete
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "upload_session_id": "session-uuid",
  "file_hash": "sha256_hash_of_complete_file"
}
```

**Response** (200 OK):
```json
{
  "video_id": "video-uuid",
  "status": "processing",
  "message": "Video queued for processing"
}
```

#### Get Video Details
```
GET /videos/{video_id}
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "id": "video-uuid",
  "creator_id": "user-uuid",
  "title": "My Amazing Video",
  "description": "A description of the video",
  "status": "published",
  "duration_seconds": 120,
  "visibility": "public",
  "s3_key": "videos/user-uuid/video-uuid.mp4",
  "hls_manifest_url": "https://cdn.example.com/videos/.../playlist.m3u8",
  "created_at": "2025-10-25T10:30:45Z",
  "updated_at": "2025-10-25T10:35:00Z",
  "engagement": {
    "views": 1500,
    "likes": 120,
    "comments": 45,
    "shares": 10
  }
}
```

#### Get Video Processing Progress
```
GET /videos/{video_id}/progress
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "video_id": "video-uuid",
  "status": "processing",
  "progress_percent": 45,
  "current_stage": "transcoding",
  "estimated_completion": "2025-10-25T10:45:00Z"
}
```

#### Like Video
```
POST /videos/{video_id}/like
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "status": "liked"
}
```

#### Share Video
```
POST /videos/{video_id}/share
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "share_type": "messaging"
}
```

**Response** (200 OK): Share confirmation

#### Get Similar Videos
```
GET /videos/{video_id}/similar?limit=10
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "videos": [
    {
      "id": "similar-video-uuid",
      "title": "Similar video title",
      "thumbnail_url": "https://...",
      "similarity_score": 0.87
    }
  ]
}
```

---

### Stories Endpoints

#### Create Story
```
POST /stories
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "media_url": "https://cdn.example.com/story-123.jpg",
  "caption": "Check this out!",
  "privacy": "public"
}
```

**Response** (201 Created):
```json
{
  "id": "story-uuid",
  "user_id": "user-uuid",
  "media_url": "https://...",
  "privacy": "public",
  "created_at": "2025-10-25T10:30:45Z",
  "expires_at": "2025-10-26T10:30:45Z"
}
```

#### Get Story
```
GET /stories/{story_id}
Authorization: Bearer <token>
```

#### List User's Stories
```
GET /stories/user/{user_id}
Authorization: Bearer <token>
```

#### Delete Story
```
DELETE /stories/{story_id}
Authorization: Bearer <token>
```

#### Update Story Privacy
```
PATCH /stories/{story_id}/privacy
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "privacy": "close_friends"
}
```

#### Add Close Friend
```
POST /stories/close-friends/{friend_id}
Authorization: Bearer <token>
```

#### Remove Close Friend
```
DELETE /stories/close-friends/{friend_id}
Authorization: Bearer <token>
```

#### List Close Friends
```
GET /stories/close-friends
Authorization: Bearer <token>
```

---

### Streaming Endpoints

#### Create Stream
```
POST /streams
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "title": "Live Gaming Session",
  "description": "Playing Elden Ring",
  "category": "gaming",
  "is_private": false
}
```

**Response** (201 Created):
```json
{
  "id": "stream-uuid",
  "user_id": "user-uuid",
  "title": "Live Gaming Session",
  "status": "live",
  "rtmp_url": "rtmp://stream.example.com/live",
  "stream_key": "secure_stream_key_uuid",
  "hls_url": "https://cdn.example.com/streams/stream-uuid/playlist.m3u8",
  "created_at": "2025-10-25T10:30:45Z"
}
```

#### List Live Streams
```
GET /streams?page=1&limit=20&category=gaming
```

**Query Parameters**:
- `page`: Page number (default: 1)
- `limit`: Results per page (default: 20)
- `category`: Optional category filter

**Response** (200 OK):
```json
{
  "streams": [
    {
      "id": "stream-uuid",
      "user_id": "user-uuid",
      "title": "Stream Title",
      "viewer_count": 250,
      "category": "gaming",
      "thumbnail_url": "https://...",
      "hls_url": "https://...",
      "created_at": "2025-10-25T10:30:45Z"
    }
  ],
  "total_count": 500,
  "page": 1,
  "limit": 20
}
```

#### Search Streams
```
GET /streams/search?q=gaming&limit=10
```

#### Get Stream Details
```
GET /streams/{stream_id}
```

#### Join Stream
```
POST /streams/{stream_id}/join
Authorization: Bearer <token>
```

#### Leave Stream
```
POST /streams/{stream_id}/leave
Authorization: Bearer <token>
```

#### Get Stream Analytics
```
GET /streams/{stream_id}/analytics
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "stream_id": "stream-uuid",
  "total_viewers": 1000,
  "peak_viewers": 2500,
  "duration_seconds": 3600,
  "average_bitrate": 5000,
  "quality_levels": ["720p", "480p", "360p"],
  "avg_quality_watched": "480p"
}
```

#### Post Stream Comment
```
POST /streams/{stream_id}/comments
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "message": "Great stream!"
}
```

#### Get Stream Comments
```
GET /streams/{stream_id}/comments?limit=50
```

---

### Discover Endpoints

#### Get Suggested Users
```
GET /discover/suggested-users?limit=20
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
{
  "suggestions": [
    {
      "id": "user-uuid",
      "username": "suggested_user",
      "display_name": "Suggested User",
      "avatar_url": "https://...",
      "mutual_followers": 5,
      "reason": "Followed by John Doe"
    }
  ]
}
```

---

### Search Endpoints

#### Search Users
```
GET /search/users?q=john&limit=20
```

**Query Parameters**:
- `q`: Search query
- `limit`: Max results (default: 20)

**Response** (200 OK):
```json
{
  "query": "john",
  "results": [
    {
      "id": "user-uuid",
      "username": "john_doe",
      "email": "john@example.com",
      "created_at": "2025-01-15T08:30:00Z"
    }
  ],
  "count": 5
}
```

---

### Trending Endpoints

#### Get Trending Content
```
GET /trending
```

#### Get Trending Videos
```
GET /trending/videos?limit=20
```

#### Get Trending Posts
```
GET /trending/posts?limit=20
```

#### Get Trending Streams
```
GET /trending/streams?limit=20
```

#### Get Trending Categories
```
GET /trending/categories
```

---

### Events Endpoint (Analytics)

#### Ingest Event
```
POST /events
Content-Type: application/json
```

**Request**:
```json
{
  "event_type": "video_viewed",
  "user_id": "user-uuid",
  "object_id": "video-uuid",
  "metadata": {
    "duration_watched": 60,
    "quality": "720p"
  },
  "timestamp": "2025-10-25T10:30:45Z"
}
```

**Response** (202 Accepted)

---

## Messaging Service API

**Base URL**: `http://localhost:8085`

### REST Endpoints

#### Create Conversation
```
POST /conversations
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "user_a": "uuid-of-first-user",
  "user_b": "uuid-of-second-user"
}
```

**Response** (200 OK):
```json
{
  "id": "conversation-uuid",
  "member_count": 2,
  "last_message_id": "message-uuid"
}
```

#### Get Conversation
```
GET /conversations/{conversation_id}
Authorization: Bearer <token>
```

**Response** (200 OK): Conversation object

#### Send Message
```
POST /conversations/{conversation_id}/messages
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "plaintext": "Hello there!",
  "idempotency_key": "optional-unique-key"
}
```

**Response** (200 OK):
```json
{
  "id": "message-uuid",
  "sequence_number": 42
}
```

#### Get Message History
```
GET /conversations/{conversation_id}/messages?limit=50
Authorization: Bearer <token>
```

**Response** (200 OK):
```json
[
  {
    "id": "message-uuid",
    "sender_id": "user-uuid",
    "sequence_number": 1,
    "created_at": "2025-10-25T10:30:45Z"
  }
]
```

#### Search Messages
```
GET /conversations/{conversation_id}/messages/search?q=hello
Authorization: Bearer <token>
```

#### Update Message
```
PUT /messages/{message_id}
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "plaintext": "Updated message"
}
```

#### Delete Message
```
DELETE /messages/{message_id}
Authorization: Bearer <token>
```

#### Mark Conversation as Read
```
POST /conversations/{conversation_id}/read
Authorization: Bearer <token>
```

#### Add Message Reaction
```
POST /messages/{message_id}/reactions
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "emoji": "👍"
}
```

#### Get Message Reactions
```
GET /messages/{message_id}/reactions
Authorization: Bearer <token>
```

#### Remove Reaction
```
DELETE /messages/{message_id}/reactions/{user_id}
Authorization: Bearer <token>
```

#### Add Group Member
```
POST /conversations/{conversation_id}/members
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "user_id": "user-uuid",
  "role": "member"
}
```

#### Remove Group Member
```
DELETE /conversations/{conversation_id}/members/{user_id}
Authorization: Bearer <token>
```

#### Update Member Role
```
PUT /conversations/{conversation_id}/members/{user_id}
Authorization: Bearer <token>
Content-Type: application/json
```

**Request**:
```json
{
  "role": "admin"
}
```

---

## Search Service API

**Base URL**: `http://localhost:8081`

### Health Check

```
GET /health
```

### Search Endpoints

#### Search Users (Full-Text)
```
GET /api/v1/search/users?q=john&limit=20
```

#### Search Posts (Full-Text)
```
GET /api/v1/search/posts?q=sunset&limit=20
```

Uses PostgreSQL `tsvector` for full-text search with ranking.

#### Search Hashtags
```
GET /api/v1/search/hashtags?q=travel&limit=20
```

#### Clear Search Cache
```
POST /api/v1/search/clear-cache
```

---

## Data Models

### Core Models

#### User
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "username": "john_doe",
  "email_verified": true,
  "is_active": true,
  "display_name": "John Doe",
  "bio": "Software developer",
  "avatar_url": "https://cdn.example.com/avatars/user.jpg",
  "cover_photo_url": "https://cdn.example.com/covers/user.jpg",
  "location": "San Francisco",
  "private_account": false,
  "totp_enabled": false,
  "created_at": "2025-01-15T08:30:00Z",
  "updated_at": "2025-01-15T08:30:00Z",
  "last_login_at": "2025-10-25T10:30:00Z"
}
```

#### Post
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "caption": "Post caption",
  "image_key": "s3-key",
  "image_sizes": {
    "small": "image-small.jpg",
    "medium": "image-medium.jpg",
    "large": "image-large.jpg"
  },
  "status": "published",
  "content_type": "image",
  "created_at": "2025-10-25T10:30:45Z",
  "updated_at": "2025-10-25T10:30:45Z"
}
```

#### Conversation
```json
{
  "id": "uuid",
  "conversation_type": "direct",
  "name": null,
  "created_by": "uuid",
  "member_count": 2,
  "last_message_id": "uuid",
  "created_at": "2025-10-25T10:30:45Z",
  "updated_at": "2025-10-25T10:30:45Z"
}
```

#### Message
```json
{
  "id": "uuid",
  "conversation_id": "uuid",
  "sender_id": "uuid",
  "encrypted_content": "base64_encrypted_content",
  "nonce": "hex_nonce",
  "message_type": "text",
  "created_at": "2025-10-25T10:30:45Z",
  "edited_at": null,
  "deleted_at": null
}
```

#### Video
```json
{
  "id": "uuid",
  "creator_id": "uuid",
  "title": "Video Title",
  "description": "Video description",
  "status": "published",
  "duration_seconds": 120,
  "s3_key": "videos/user-uuid/video-uuid.mp4",
  "hls_manifest_url": "https://cdn.example.com/videos/.../playlist.m3u8",
  "visibility": "public",
  "content_type": "original",
  "created_at": "2025-10-25T10:30:45Z"
}
```

#### Stream
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "title": "Stream Title",
  "description": "Stream Description",
  "status": "live",
  "category": "gaming",
  "is_private": false,
  "rtmp_url": "rtmp://stream.example.com/live",
  "stream_key": "secure_key",
  "hls_url": "https://cdn.example.com/streams/.../playlist.m3u8",
  "viewer_count": 250,
  "created_at": "2025-10-25T10:30:45Z"
}
```

#### Story
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "media_url": "https://cdn.example.com/stories/story-123.jpg",
  "caption": "Story caption",
  "privacy": "public",
  "created_at": "2025-10-25T10:30:45Z",
  "expires_at": "2025-10-26T10:30:45Z"
}
```

---

## WebSocket Protocols

### Messaging Service WebSocket

**Endpoint**: `ws://localhost:8085/ws`

**Authentication**: JWT Bearer token in query parameter or header

**Message Format** (Client → Server):
```json
{
  "type": "message",
  "conversation_id": "uuid",
  "text": "Message content",
  "idempotency_key": "optional"
}
```

**Broadcast Format** (Server → Clients):
```json
{
  "type": "message",
  "conversation_id": "uuid",
  "message": {
    "id": "uuid",
    "sender_id": "uuid",
    "sequence_number": 42
  }
}
```

**Read Receipt Format**:
```json
{
  "type": "read_receipt",
  "conversation_id": "uuid",
  "user_id": "uuid",
  "timestamp": "2025-10-25T10:30:45Z"
}
```

### Stream Chat WebSocket

**Endpoint**: `ws://localhost:8080/ws/streams/{stream_id}/chat`

**Authentication**: JWT Bearer token required

**Client Message Format**:
```json
{
  "type": "message",
  "text": "Great stream!"
}
```

**Server Broadcast Format**:
```json
{
  "comment": {
    "id": "uuid",
    "stream_id": "uuid",
    "user_id": "uuid",
    "message": "Great stream!",
    "created_at": "2025-10-25T10:30:45Z"
  }
}
```

---

## Deployment & Configuration

### Environment Variables

```bash
# Application
APP_ENV=production                          # development|production
APP_HOST=0.0.0.0
APP_PORT=8080

# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/nova
DATABASE_MAX_CONNECTIONS=50
DATABASE_POOL_IDLE_TIMEOUT=30

# Redis
REDIS_URL=redis://:password@localhost:6379

# JWT & Security
JWT_PRIVATE_KEY_PEM=-----BEGIN RSA PRIVATE KEY-----\n...
JWT_PUBLIC_KEY_PEM=-----BEGIN PUBLIC KEY-----\n...
JWT_ACCESS_TOKEN_EXPIRY=900                  # 15 minutes in seconds
JWT_REFRESH_TOKEN_EXPIRY=604800              # 7 days in seconds

# SMTP (Email)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-specific-password
SMTP_FROM_EMAIL=noreply@nova.app

# S3 Storage
S3_BUCKET=nova-media
S3_REGION=us-east-1
S3_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
S3_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
S3_ENDPOINT=https://s3.amazonaws.com

# Kafka (Events)
KAFKA_BROKERS=localhost:9092
KAFKA_EVENTS_TOPIC=nova-events
KAFKA_CDC_TOPIC=cdc

# ClickHouse (Analytics)
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_DATABASE=nova
CLICKHOUSE_USERNAME=default
CLICKHOUSE_PASSWORD=
CLICKHOUSE_TIMEOUT_MS=5000

# Milvus (Vector Search)
MILVUS_ENABLED=false
MILVUS_HOST=localhost
MILVUS_PORT=19530
MILVUS_DATABASE=nova

# Neo4j (Graph)
GRAPH_ENABLED=false
GRAPH_NEO4J_URI=neo4j://localhost:7687
GRAPH_NEO4J_USER=neo4j
GRAPH_NEO4J_PASSWORD=password

# CORS
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:3001

# Rate Limiting
RATE_LIMIT_MAX_REQUESTS=100
RATE_LIMIT_WINDOW_SECONDS=900

# Logging
RUST_LOG=info,actix_web=debug,sqlx=debug
```

### Docker Deployment

**Single Service (User Service)**:
```bash
docker build -t nova-user-service:latest -f backend/Dockerfile ./backend
docker run -p 8080:8080 --env-file .env nova-user-service:latest
```

**Messaging Service**:
```bash
docker build -t nova-messaging-service:latest -f backend/Dockerfile.messaging ./backend
docker run -p 8085:8085 --env-file .env nova-messaging-service:latest
```

**Docker Compose (All Services)**:
```bash
docker-compose up -d
```

### Health Checks

All services expose health endpoints for Kubernetes:
- `GET /health` - General health
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe

### Rate Limiting

Global rate limit: 100 requests per 15 minutes per IP/user

### Monitoring

- **Metrics**: Prometheus at `/metrics` (user-service only)
- **Logs**: Structured JSON logs via `tracing` crate
- **Traces**: OpenTelemetry support (optional)

---

## Common Integration Patterns

### Login Flow
1. POST `/auth/login` → Get access_token & refresh_token
2. Store tokens securely (localStorage in web, Keychain/Keystore in mobile)
3. Include `Authorization: Bearer <access_token>` in all subsequent requests
4. On token expiry (401), POST `/auth/refresh` with refresh_token
5. GET `/users/me` to fetch current user profile

### Message Encryption Flow (E2E)
1. GET `/users/{user_id}/public-key` for recipient
2. Client encrypts message with recipient's public key
3. POST message with encrypted_content + nonce
4. Recipient gets message via WebSocket
5. Client decrypts with their private key

### Video Upload Flow
1. POST `/videos/upload/init` → Get presigned URLs & chunk_size
2. Split file into chunks, upload each with PUT `/uploads/{upload_id}/chunks/{index}`
3. POST `/videos/upload/complete` with file_hash
4. Poll GET `/videos/{video_id}/progress` until status = "published"

### Feed Generation
1. GET `/feed?algo=ch&limit=20` returns post UUIDs
2. For each UUID, fetch full post data (title, images, engagement)
3. Use cursor-based pagination for infinite scroll
4. Invalidate cache on follow/unfollow via POST `/feed/invalidate`

---

## Best Practices

### Security
- Always use HTTPS in production
- Store JWT tokens securely (httpOnly cookies preferred)
- Rotate JWT keys periodically
- Use strong passwords (12+ chars, mixed case, numbers, symbols)
- Enable 2FA for high-security accounts
- Never log sensitive data (passwords, tokens)

### Performance
- Use pagination (cursor-based for large datasets)
- Cache frequently accessed data (user profiles, trending)
- Batch requests when possible
- Use appropriate limits (max 100 items per request)
- Monitor database query performance

### Error Handling
- Implement exponential backoff for retries
- Handle 429 (rate limit) gracefully
- Log detailed error context for debugging
- Never expose internal error details to clients
- Provide meaningful error messages

### Testing
- Unit test business logic
- Integration test with real database
- Load test critical endpoints
- Test offline scenarios (mobile)
- Verify encryption/decryption

---

**Version History**:
- 0.1.0 (2025-10-25) - Initial comprehensive API reference

