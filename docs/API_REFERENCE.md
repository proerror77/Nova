# Nova API Reference

**Version**: 2.0
**Last Updated**: 2025-12-16
**Base URL**: `https://api.nova.social` (Production) | Staging ELB

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS/Android Client                        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GraphQL Gateway (:8080)                       │
│              REST /api/v2/* + GraphQL /graphql                   │
└─────────────────────────────────────────────────────────────────┘
          │              │              │              │
          ▼              ▼              ▼              ▼
   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
   │ Identity │   │ Content  │   │  Social  │   │  Search  │
   │ Service  │   │ Service  │   │ Service  │   │ Service  │
   │  (gRPC)  │   │  (gRPC)  │   │  (gRPC)  │   │  (gRPC)  │
   └──────────┘   └──────────┘   └──────────┘   └──────────┘
          │              │              │              │
          ▼              ▼              ▼              ▼
   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
   │  Media   │   │   Feed   │   │ Ranking  │   │ Realtime │
   │ Service  │   │ Service  │   │ Service  │   │   Chat   │
   │:8082/9082│   │:8084/9084│   │  :9083   │   │  :8085   │
   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

---

## Service Port Map

| Service | HTTP Port | gRPC Port | Description |
|---------|-----------|-----------|-------------|
| GraphQL Gateway | 8080 | - | Main API gateway |
| Media Service | 8082 | 9082 | Media upload/transcode |
| Feed Service | 8084 | 9084 | Recommendation/Feed |
| Ranking Service | - | 9083 | ML ranking |
| Realtime Chat Service | 8085 | 9085 | Chat/WebSocket/E2EE |
| Identity Service | - | 50051 | Auth/JWT |
| Content Service | - | gRPC | Posts/Channels |
| Social Service | - | gRPC | Likes/Comments/Follow |
| Search Service | - | gRPC | Elasticsearch |
| Communication Service | - | gRPC | Notifications |

---

## 1. Authentication (via GraphQL Gateway)

### REST /api/v2/auth/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/auth/register` | Register new user | - |
| POST | `/api/v2/auth/login` | Login, returns JWT | - |
| POST | `/api/v2/auth/refresh` | Refresh access token | Refresh Token |
| POST | `/api/v2/auth/logout` | Logout, revoke token | JWT |

### OAuth Authentication /api/v2/auth/oauth/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/auth/oauth/google/start` | Start Google OAuth flow | - |
| POST | `/api/v2/auth/oauth/google/callback` | Complete Google OAuth | - |
| POST | `/api/v2/auth/oauth/apple/start` | Start Apple OAuth flow | - |
| POST | `/api/v2/auth/oauth/apple/callback` | Complete Apple OAuth | - |
| POST | `/api/v2/auth/oauth/apple/native` | iOS native Apple Sign-In | - |

**Request: Register**
```json
{
  "username": "johndoe",
  "email": "john@example.com",
  "password": "secureP@ss123",
  "display_name": "John Doe"
}
```

**Response: Login**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g...",
  "expires_in": 3600,
  "user": {
    "id": "uuid",
    "username": "johndoe",
    "display_name": "John Doe"
  }
}
```

**Request: Start OAuth (Google/Apple)**
```json
{
  "redirect_uri": "novasocial://oauth/callback",
  "invite_code": "OPTIONAL_INVITE_CODE"
}
```

**Response: Start OAuth**
```json
{
  "authorization_url": "https://accounts.google.com/o/oauth2/v2/auth?...",
  "state": "random_state_string"
}
```

**Request: Complete OAuth (Google/Apple)**
```json
{
  "code": "authorization_code_from_provider",
  "state": "state_from_start_response",
  "redirect_uri": "novasocial://oauth/callback",
  "invite_code": "OPTIONAL_INVITE_CODE"
}
```

**Request: Apple Native Sign-In (iOS)**
```json
{
  "authorization_code": "code_from_ASAuthorizationController",
  "identity_token": "jwt_identity_token_from_apple",
  "user_identifier": "unique_user_id_from_apple",
  "email": "user@example.com",
  "full_name": {
    "given_name": "John",
    "family_name": "Doe"
  },
  "invite_code": "OPTIONAL_INVITE_CODE"
}
```

**Response: OAuth Callback / Apple Native**
```json
{
  "user_id": "uuid",
  "token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g...",
  "expires_in": 3600,
  "is_new_user": true,
  "user": {
    "id": "uuid",
    "username": "johndoe",
    "email": "john@example.com"
  }
}
```

---

## 2. User Profile

### REST /api/v2/users/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/users/{id}` | Get user profile | JWT |
| PUT | `/api/v2/users/{id}` | Update profile | JWT (owner) |
| POST | `/api/v2/users/avatar` | Upload avatar | JWT |

---

## 3. Content (Posts)

### REST /api/v2/content/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/content` | Create post | JWT |
| GET | `/api/v2/content/{id}` | Get post by ID | JWT |
| PUT | `/api/v2/content/{id}` | Update post | JWT (owner) |
| DELETE | `/api/v2/content/{id}` | Delete post | JWT (owner) |
| GET | `/api/v2/content/user/{user_id}` | Get user's posts | JWT |
| POST | `/api/v2/content/posts/batch` | Batch get posts | JWT |

---

## 4. Feed & Recommendations

### REST /api/v2/feed/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/feed` | Get personalized feed | JWT |
| GET | `/api/v2/feed/user/{user_id}` | Get user feed | JWT |
| GET | `/api/v2/feed/explore` | Explore feed | JWT |
| GET | `/api/v2/feed/trending` | Trending posts | JWT |

**Query Parameters:**
- `algo`: `ch` (ClickHouse ML) or `time` (chronological)
- `limit`: 1-100 (default: 20)
- `cursor`: pagination cursor

---

## 5. Social Interactions

### REST /api/v2/social/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/social/likes` | Like a post | JWT |
| DELETE | `/api/v2/social/likes/{post_id}` | Unlike | JWT |
| GET | `/api/v2/social/likes/{post_id}` | Get likes | JWT |
| GET | `/api/v2/social/likes/{post_id}/check` | Check if liked | JWT |
| POST | `/api/v2/social/comments` | Create comment | JWT |
| DELETE | `/api/v2/social/comments/{id}` | Delete comment | JWT |
| GET | `/api/v2/social/comments/{post_id}` | Get comments | JWT |
| POST | `/api/v2/social/shares` | Share post | JWT |
| GET | `/api/v2/social/shares/{post_id}/count` | Share count | JWT |

---

## 6. Social Graph (Follow/Block)

### REST /api/v2/graph/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/graph/follow` | Follow user | JWT |
| DELETE | `/api/v2/graph/unfollow` | Unfollow user | JWT |
| GET | `/api/v2/graph/followers` | Get followers | JWT |
| GET | `/api/v2/graph/following` | Get following | JWT |
| GET | `/api/v2/graph/is-following` | Check relationship | JWT |

---

## 7. Search

### REST /api/v2/search/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/search` | Global search | JWT |
| GET | `/api/v2/search/users` | Search users | JWT |
| GET | `/api/v2/search/content` | Search posts | JWT |
| GET | `/api/v2/search/hashtags` | Search hashtags | JWT |
| GET | `/api/v2/search/suggestions` | Autocomplete | JWT |
| GET | `/api/v2/search/trending` | Trending topics | JWT |

---

## 8. Channels

### REST /api/v2/channels/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/channels` | List all channels | JWT |
| GET | `/api/v2/channels/{id}` | Get channel details | JWT |
| GET | `/api/v2/users/{id}/channels` | User's channels | JWT |
| POST | `/api/v2/channels/subscribe` | Subscribe | JWT |
| DELETE | `/api/v2/channels/unsubscribe` | Unsubscribe | JWT |

---

## 9. Polls (Voting)

### REST /api/v2/polls/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/polls/trending` | Trending polls | JWT |
| GET | `/api/v2/polls` | Active polls | JWT |
| POST | `/api/v2/polls` | Create poll | JWT |
| GET | `/api/v2/polls/{id}` | Get poll details | JWT |
| POST | `/api/v2/polls/{id}/vote` | Vote on poll | JWT |
| POST | `/api/v2/polls/{id}/unvote` | Remove vote | JWT |
| GET | `/api/v2/polls/{id}/voted` | Check if voted | JWT |
| GET | `/api/v2/polls/{id}/rankings` | Get rankings | JWT |
| DELETE | `/api/v2/polls/{id}` | Delete poll | JWT (owner) |

---

## 10. Media Service

### REST /api/v1/uploads/* (Direct to Media Service :8082)

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v1/uploads` | Initiate upload | JWT |
| GET | `/api/v1/uploads/{id}` | Get upload status | JWT |
| PATCH | `/api/v1/uploads/{id}/progress` | Update progress | JWT |
| POST | `/api/v1/uploads/{id}/complete` | Complete upload | JWT |
| POST | `/api/v1/uploads/{id}/presigned-url` | Get S3 presigned URL | JWT |
| DELETE | `/api/v1/uploads/{id}` | Cancel upload | JWT |

### REST /api/v1/videos/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v1/videos` | List videos | JWT |
| POST | `/api/v1/videos` | Create video record | JWT |
| GET | `/api/v1/videos/{id}` | Get video | JWT |
| PATCH | `/api/v1/videos/{id}` | Update video | JWT |
| DELETE | `/api/v1/videos/{id}` | Delete video | JWT |

### REST /api/v1/reels/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v1/reels` | List reels | JWT |
| POST | `/api/v1/reels` | Create reel | JWT |
| GET | `/api/v1/reels/{id}` | Get reel | JWT |
| DELETE | `/api/v1/reels/{id}` | Delete reel | JWT |

---

## 11. Realtime Chat Service (:8085)

### WebSocket

| Endpoint | Description |
|----------|-------------|
| `/ws` | WebSocket connection for real-time messaging |

### REST - Conversations

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/conversations` | Create DM/group | JWT |
| GET | `/conversations` | List conversations | JWT |
| GET | `/conversations/{id}` | Get conversation | JWT |
| PUT | `/conversations/{id}` | Update conversation | JWT |

### REST - Messages

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/conversations/{id}/messages` | Send message | JWT |
| GET | `/conversations/{id}/messages` | Get messages | JWT |
| PUT | `/messages/{id}` | Edit message | JWT |
| DELETE | `/messages/{id}` | Delete message | JWT |
| POST | `/conversations/{cid}/messages/{mid}/recall` | Recall message | JWT |

### REST - Reactions

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/messages/{id}/reactions` | Add reaction | JWT |
| GET | `/messages/{id}/reactions` | Get reactions | JWT |
| DELETE | `/messages/{mid}/reactions/{rid}` | Remove reaction | JWT |

### REST - Groups

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/groups` | Create group | JWT |
| POST | `/conversations/{id}/members` | Add member | JWT (admin) |
| DELETE | `/conversations/{id}/members/{uid}` | Remove member | JWT (admin) |
| PUT | `/conversations/{id}/members/{uid}/role` | Update role | JWT (owner) |

### REST - Voice/Video Calls

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/conversations/{id}/calls` | Initiate call | JWT |
| POST | `/calls/{id}/answer` | Answer call | JWT |
| POST | `/calls/{id}/reject` | Reject call | JWT |
| POST | `/calls/{id}/end` | End call | JWT |
| POST | `/calls/ice-candidate` | ICE candidate | JWT |
| GET | `/calls/ice-servers` | Get TURN/STUN servers | JWT |

### REST - Location Sharing

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/conversations/{id}/location` | Share location | JWT |
| DELETE | `/conversations/{id}/location` | Stop sharing | JWT |
| GET | `/nearby-users` | Get nearby users | JWT |

---

## 12. E2EE (End-to-End Encryption) - /api/v2/*

### REST /api/v2/* (Realtime Chat Service)

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/devices` | Register E2EE device | JWT |
| POST | `/api/v2/keys/upload` | Upload identity/one-time keys | JWT |
| POST | `/api/v2/keys/claim` | Claim one-time keys | JWT |
| POST | `/api/v2/keys/query` | Query device keys | JWT |
| GET | `/api/v2/to-device` | Get to-device messages | JWT |
| DELETE | `/api/v2/to-device/{id}` | Acknowledge message | JWT |

### Key Exchange

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/keys/device` | Exchange device keys | JWT |
| GET | `/conversations/{cid}/keys/{uid}/{did}` | Get conversation keys | JWT |

---

## 13. Relationships & Privacy - /api/v2/*

### REST /api/v2/* (Realtime Chat Service)

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/blocks` | Block user | JWT |
| DELETE | `/api/v2/blocks/{user_id}` | Unblock user | JWT |
| GET | `/api/v2/blocks` | Get blocked list | JWT |
| GET | `/api/v2/relationships/{user_id}` | Get relationship status | JWT |
| GET | `/api/v2/settings/privacy` | Get DM privacy settings | JWT |
| PUT | `/api/v2/settings/privacy` | Update DM privacy | JWT |
| GET | `/api/v2/message-requests` | Get pending requests | JWT |
| POST | `/api/v2/message-requests/{id}/accept` | Accept request | JWT |
| POST | `/api/v2/message-requests/{id}/reject` | Reject request | JWT |

**DM Permission Values:**
- `anyone` - Anyone can DM
- `followers` - Only followers can DM
- `mutuals` - Only mutual followers can DM
- `nobody` - No one can DM

---

## 14. Alice AI Assistant

### REST /api/v2/alice/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/alice/status` | AI assistant status | JWT |
| POST | `/api/v2/alice/chat` | Send chat message | JWT |
| POST | `/api/v2/alice/voice` | Voice mode | JWT |

---

## 15. Device & Session Management

### REST /api/v2/devices/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v2/devices` | List logged-in devices | JWT |
| GET | `/api/v2/devices/current` | Current device info | JWT |
| POST | `/api/v2/devices/logout` | Logout specific device | JWT |

---

## 16. Invitations

### REST /api/v2/invitations/*

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v2/invitations/generate` | Generate invite code | JWT |
| GET | `/api/v2/invitations` | List invitations | JWT |
| GET | `/api/v2/invitations/stats` | Invitation stats | JWT |
| POST | `/api/v2/invitations/send` | Send invite | JWT |

---

## 17. Health & Monitoring

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/health/circuit-breakers` | Circuit breaker status |

---

## GraphQL Schema

### Endpoint
- `POST /graphql` - Query execution
- `GET /graphql` - WebSocket subscriptions
- `GET /playground` - Apollo Sandbox

### Example Query
```graphql
query GetFeed($limit: Int!, $cursor: String) {
  feed(limit: $limit, cursor: $cursor) {
    edges {
      node {
        id
        content
        author {
          id
          username
          displayName
        }
        createdAt
        likeCount
        commentCount
      }
      cursor
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

### Example Mutation
```graphql
mutation CreatePost($input: CreatePostInput!) {
  createPost(input: $input) {
    id
    content
    mediaUrls
    createdAt
  }
}
```

### Subscriptions
```graphql
subscription OnNewMessage($conversationId: ID!) {
  messageReceived(conversationId: $conversationId) {
    id
    content
    sender {
      id
      username
    }
    createdAt
  }
}
```

---

## Error Codes

| HTTP Code | Description |
|-----------|-------------|
| 400 | Bad Request - Invalid input |
| 401 | Unauthorized - Invalid/expired JWT |
| 403 | Forbidden - No permission |
| 404 | Not Found |
| 409 | Conflict - Resource already exists |
| 422 | Unprocessable Entity - Validation error |
| 429 | Too Many Requests - Rate limited |
| 500 | Internal Server Error |

### Error Response Format
```json
{
  "error": {
    "code": "INVALID_INPUT",
    "message": "Email format is invalid",
    "details": {
      "field": "email",
      "value": "not-an-email"
    }
  }
}
```

---

## Rate Limits

| Endpoint Category | Limit |
|-------------------|-------|
| Auth (login/register) | 5 req/min |
| Content creation | 30 req/min |
| Feed/Read | 100 req/min |
| Search | 30 req/min |
| WebSocket messages | 60 msg/min |

---

## Authentication

All authenticated endpoints require:
```
Authorization: Bearer <access_token>
```

JWT payload includes:
```json
{
  "sub": "user-uuid",
  "exp": 1234567890,
  "iat": 1234567890,
  "username": "johndoe"
}
```

---

## iOS SDK Reference

See `ios/NovaSocial/Shared/Services/Networking/APIConfig.swift` for Swift endpoint definitions.

```swift
// Example usage
let endpoint = APIConfig.Feed.getFeed  // "/api/v2/feed"
let userEndpoint = APIConfig.Auth.user("uuid")  // "/api/v2/users/{id}"
```
