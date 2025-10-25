# Nova Frontend - Backend Service Integration Matrix

## Service Connection Status

```
┌─────────────────────────────────────────────────────────────┐
│ FRONTEND (React + TypeScript)                               │
├─────────────────┬───────────────────────────────────────────┤
│ Port 3000       │ Vite Dev Server                           │
│ Port 5173       │ Vite Production Build                     │
└─────────────────┴───────────────────────────────────────────┘
         ↓                              ↓
    ┌─────────────┐          ┌──────────────────┐
    │ User Service│          │Messaging Service │
    │ Port 8080   │          │ Port 8085 (WS)   │
    └─────────────┘          └──────────────────┘
         ↓                              ↓
    ┌─────────────┐          ┌──────────────────┐
    │  Postgres   │          │  Postgres        │
    │   Database  │          │  Database        │
    └─────────────┘          └──────────────────┘
         ↓                              ↓
    ┌─────────────┐          ┌──────────────────┐
    │ S3 Storage  │          │  Redis Pub/Sub   │
    │  (Photos/   │          │  (Message relay) │
    │  Videos)    │          │                  │
    └─────────────┘          └──────────────────┘
```

---

## Feature Implementation Checklist

### US1: Messaging System (70% Complete)
```
┌─────────────────────────────────────────────┐
│ Messaging Features                          │
├─────────────────────────────────────────────┤
│ ✅ 1:1 Conversations                        │
│ ✅ Message sending (REST)                   │
│ ✅ Real-time delivery (WebSocket)           │
│ ✅ Message history                          │
│ ✅ Typing indicators                        │
│ ✅ Auto-reconnection                        │
│ ✅ Offline message queueing                 │
│ ✅ Idempotency keys                         │
│ ✅ Connection metrics                       │
│                                             │
│ ❌ Group conversations                      │
│ ❌ Message encryption                       │
│ ❌ Message search                           │
│ ❌ Message reactions                        │
│ ❌ Message editing/deletion                 │
│ ❌ Read receipts                            │
│ ❌ User presence                            │
│ ❌ Attachments in messages                  │
│ ❌ Message pinning                          │
│ ❌ Conversation archive/mute                │
└─────────────────────────────────────────────┘
```

### US2: Post Creation (60% Complete)
```
┌─────────────────────────────────────────────┐
│ Post Creation Features                      │
├─────────────────────────────────────────────┤
│ ✅ Photo upload (JPEG, PNG, WebP, HEIC)    │
│ ✅ Video upload (MP4, MOV, WebM)           │
│ ✅ Multiple file upload                     │
│ ✅ Caption input (2200 chars)              │
│ ✅ File validation                          │
│ ✅ S3 presigned URLs                        │
│ ✅ Upload progress tracking                 │
│ ✅ SHA-256 file hashing                     │
│ ✅ Error handling & recovery                │
│                                             │
│ ❌ Image cropping                           │
│ ❌ Video trimming                           │
│ ❌ Filters/effects                          │
│ ❌ Hashtag suggestions                      │
│ ❌ Location tagging                         │
│ ❌ Privacy settings                         │
│ ❌ Draft saving                             │
│ ❌ Post scheduling                          │
│ ❌ Tag other users                          │
│ ❌ Post templates                           │
└─────────────────────────────────────────────┘
```

### US3: Feed Display (50% Complete)
```
┌─────────────────────────────────────────────┐
│ Feed Features                               │
├─────────────────────────────────────────────┤
│ ✅ Feed fetching                            │
│ ✅ Cursor-based pagination                  │
│ ✅ Post card display                        │
│ ✅ Image & video support                    │
│ ✅ Engagement metrics (display only)        │
│ ✅ User info display                        │
│ ✅ Timestamp display                        │
│                                             │
│ ❌ CRITICAL: Like functionality             │
│ ❌ CRITICAL: Comment functionality          │
│ ❌ Share/repost                             │
│ ❌ Follow/unfollow                          │
│ ❌ User profile links                       │
│ ❌ Trending/discover                        │
│ ❌ Search                                   │
│ ❌ Infinite scroll (has Load More btn)      │
│ ❌ Pull-to-refresh                          │
│ ❌ Save posts                               │
└─────────────────────────────────────────────┘
```

---

## API Endpoint Coverage

### User Service Endpoints

```
┌──────────────────────────────────────────────────────────────┐
│ USER SERVICE (Port 8080) - REST API                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ FEED ENDPOINTS                          Status              │
│  GET /feed                             ✅ IMPLEMENTED       │
│  GET /feed/explore                     ❌ MISSING            │
│  GET /feed/trending                    ❌ MISSING            │
│                                                              │
│ POST ENDPOINTS                                               │
│  GET /posts/{id}                       ✅ IMPLEMENTED       │
│  POST /posts/upload/init               ✅ IMPLEMENTED       │
│  POST /posts/upload/complete           ✅ IMPLEMENTED       │
│  DELETE /posts/{id}                    ❌ MISSING            │
│  PUT /posts/{id}                       ❌ MISSING            │
│                                                              │
│ ENGAGEMENT ENDPOINTS                                         │
│  POST /posts/{id}/like                 ❌ MISSING (CRITICAL)│
│  DELETE /posts/{id}/like               ❌ MISSING (CRITICAL)│
│  POST /posts/{id}/comment              ❌ MISSING (CRITICAL)│
│  GET /posts/{id}/comments              ❌ MISSING            │
│  DELETE /posts/{id}/comments/{cId}     ❌ MISSING            │
│                                                              │
│ VIDEO ENDPOINTS                                              │
│  POST /videos/upload-url               ✅ IMPLEMENTED       │
│  POST /videos                          ✅ IMPLEMENTED       │
│  GET /videos/{id}                      ❌ MISSING            │
│  DELETE /videos/{id}                   ❌ MISSING            │
│  PUT /videos/{id}                      ❌ MISSING            │
│                                                              │
│ USER ENDPOINTS                                               │
│  GET /users/{id}/profile               ❌ MISSING            │
│  PUT /users/{id}/profile               ❌ MISSING            │
│  GET /users/{id}/posts                 ❌ MISSING            │
│  GET /users/{id}/followers             ❌ MISSING            │
│  POST /users/{id}/follow               ❌ MISSING            │
│                                                              │
│ AUTH ENDPOINTS                                               │
│  POST /auth/login                      ❌ MISSING            │
│  POST /auth/register                   ❌ MISSING            │
│  POST /auth/logout                     ❌ MISSING            │
│  GET /auth/profile                     ❌ MISSING            │
│                                                              │
│ SEARCH ENDPOINTS                                             │
│  GET /search/posts                     ❌ MISSING            │
│  GET /search/users                     ❌ MISSING            │
│  GET /search/hashtags                  ❌ MISSING            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Messaging Service Endpoints

```
┌──────────────────────────────────────────────────────────────┐
│ MESSAGING SERVICE (Port 8085) - REST + WebSocket             │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ CONVERSATION ENDPOINTS                 Status               │
│  POST /conversations                   ✅ IMPLEMENTED       │
│  GET /conversations/{id}/messages      ✅ IMPLEMENTED       │
│  GET /conversations                    ❌ MISSING            │
│  GET /conversations/{id}               ❌ MISSING            │
│  PUT /conversations/{id}               ❌ MISSING            │
│  DELETE /conversations/{id}            ❌ MISSING            │
│                                                              │
│ MESSAGE ENDPOINTS                                            │
│  POST /conversations/{id}/messages     ✅ IMPLEMENTED       │
│  DELETE /conversations/{id}/messages   ❌ MISSING            │
│  PUT /conversations/{id}/messages      ❌ MISSING            │
│  POST /conversations/{id}/msg/react    ❌ MISSING            │
│  GET /conversations/{id}/msg/search    ❌ MISSING            │
│                                                              │
│ WEBSOCKET ENDPOINTS                                          │
│  WS /ws?conversation_id=...            ✅ IMPLEMENTED       │
│    ├── message events                  ✅ IMPLEMENTED       │
│    ├── typing events                   ✅ IMPLEMENTED       │
│    └── presence events                 ❌ MISSING            │
│                                                              │
│ GROUP ENDPOINTS                                              │
│  POST /groups                          ❌ MISSING            │
│  GET /groups/{id}                      ❌ MISSING            │
│  PUT /groups/{id}                      ❌ MISSING            │
│  POST /groups/{id}/members             ❌ MISSING            │
│  DELETE /groups/{id}/members           ❌ MISSING            │
│                                                              │
│ ATTACHMENT ENDPOINTS                                         │
│  POST /msg/{id}/attachments            ❌ MISSING            │
│  GET /msg/{id}/attachments             ❌ MISSING            │
│  DELETE /msg/{id}/attachments          ❌ MISSING            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Frontend-to-Backend API Call Flow

### Messaging Feature Flow
```
User Action: Create Conversation
  │
  ├─→ [Frontend] App.tsx receives peer_id
  │
  ├─→ [API Call] POST /conversations
  │    Headers: Authorization: Bearer {token}
  │    Body: { user_a: userId, user_b: peerId }
  │
  ├─→ [Backend] Messaging Service validates JWT
  │
  ├─→ [Backend] Creates conversation in PostgreSQL
  │
  ├─→ [Backend] Publishes to Redis Pub/Sub
  │
  ├─→ [Frontend] Store updates (messagingStore)
  │
  └─→ [UI] ConversationList re-renders


User Action: Send Message
  │
  ├─→ [Frontend] MessageComposer captures text
  │
  ├─→ [API Call] POST /conversations/{id}/messages
  │    Headers: Authorization: Bearer {token}
  │    Body: { sender_id, plaintext, idempotency_key }
  │
  ├─→ [Backend] Validates JWT & deduplicates (idempotency)
  │
  ├─→ [Backend] Persists to PostgreSQL
  │
  ├─→ [Backend] Publishes to Redis for real-time delivery
  │
  ├─→ [Frontend] Optimistic update in messagingStore
  │
  ├─→ [WebSocket] Real-time message event received
  │
  └─→ [UI] MessageThread re-renders with new message
```

### Post Creation Flow
```
User Action: Upload Photo
  │
  ├─→ [Frontend] PostCreator validates file
  │
  ├─→ [API Call] POST /api/v1/posts/upload/init
  │    Body: { filename, content_type, file_size, caption }
  │
  ├─→ [Backend] Creates upload token & generates presigned URL
  │
  ├─→ [Frontend] Calculates SHA-256 hash of file
  │
  ├─→ [S3 Upload] PUT {presigned_url}
  │    Headers: Content-Type: image/jpeg
  │    Body: File binary
  │
  ├─→ [Frontend] File successfully uploaded to S3
  │
  ├─→ [API Call] POST /api/v1/posts/upload/complete
  │    Body: { post_id, upload_token, file_hash, file_size }
  │
  ├─→ [Backend] Validates hash & marks post as published
  │
  └─→ [UI] Success notification
```

### Feed Display Flow
```
User Action: View Feed
  │
  ├─→ [API Call] GET /feed?algo=time&limit=10
  │    Headers: Authorization: Bearer {token}
  │
  ├─→ [Backend] Returns { posts: [postId1, postId2, ...], cursor, has_more }
  │
  ├─→ [Frontend] For each post_id, call GET /posts/{id}
  │    (This is N+1 pattern - should batch in backend!)
  │
  ├─→ [Backend] Returns full post data for each ID
  │
  ├─→ [Frontend] Updates FeedView state with post array
  │
  ├─→ [UI] PostCard[] renders with images/videos
  │
  └─→ [Frontend] When Like button clicked
       │
       ├─→ [Alert] "Like functionality coming soon!"
       │    (NOT IMPLEMENTED)
       │
       └─→ [Missing] Should call POST /posts/{id}/like
```

---

## Data Flow Diagrams

### Messaging Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│ FRONTEND                                                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  React Components           Zustand Stores      Services       │
│  ───────────────            ───────────────      ────────      │
│                                                                 │
│  MessageComposer ─────────→ messagingStore ──→ REST API       │
│        │                         ↑              (axios)        │
│        │                         │                               │
│        └────────────────→ addMessage()  ←───── HTTP Response   │
│                                                                 │
│  MessageThread ──────────→ messagingStore ──→ WebSocket       │
│        │                         ↑              (auto-reconnect)
│        └────────────────→ loadMessages()  ←── message event   │
│                                                                 │
│  ConversationList ───────→ messagingStore                      │
│                                 ↑                              │
│                                 │                              │
│                          connectionStore ←──── Connection     │
│                                 ↑                  Metrics     │
│                                 │                              │
└─────────────────────────────────────────────────────────────────┘
         ↓                        ↓                      ↓
┌─────────────────────────────────────────────────────────────────┐
│ BACKEND                                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  REST Handlers              WebSocket Handlers    Database    │
│  ──────────────             ──────────────────    ────────    │
│                                                                 │
│  POST /conversations        WS /ws                PostgreSQL  │
│  POST /msg                  ├─ message event      ├─ convs   │
│  GET /msg/history           ├─ typing event       ├─ messages│
│                             └─ presence           └─ users   │
│                                                                 │
│                             Redis Pub/Sub                      │
│                             ─────────────                      │
│                             (cross-instance                    │
│                              fanout)                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Feed Architecture
```
┌───────────────────────────────────────────────────────────────┐
│ FRONTEND                                                      │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  FeedView (Component)                                         │
│  ├─ fetch /feed ────→ REST API (axios)                      │
│  ├─ state: posts[] ──→ FeedView local state                 │
│  │                                                           │
│  └─ render PostCard[]                                       │
│     ├─ Display images/videos ✅                             │
│     ├─ Display engagement metrics ✅                        │
│     ├─ Like button ❌ (calls alert, not API)                │
│     └─ Comment button ❌ (calls alert, not API)             │
│                                                               │
│  [MISSING]                                                    │
│  ├─ No global feed store (uses local state)                 │
│  ├─ No optimistic updates                                   │
│  ├─ No cache/dedup for posts                                │
│  ├─ No infinite scroll (has Load More btn)                  │
│  └─ No pull-to-refresh                                      │
│                                                               │
└───────────────────────────────────────────────────────────────┘
         ↓                                    ↓
┌───────────────────────────────────────────────────────────────┐
│ BACKEND                                                       │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  GET /feed                                                    │
│  ├─ Returns: [postId1, postId2, ...] ✅                      │
│  ├─ WITH: cursor, has_more, total_count ✅                  │
│  │                                                           │
│  GET /posts/{id}                                             │
│  └─ Returns: full post object ✅                            │
│                                                               │
│  [MISSING]                                                    │
│  ├─ POST /posts/{id}/like ❌                                │
│  ├─ GET /posts/{id}/comments ❌                             │
│  ├─ POST /posts/{id}/comment ❌                             │
│  ├─ Batch post fetch (GraphQL or /feed?ids=...) ❌         │
│  └─ Like count updates in real-time ❌                      │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

---

## Authentication Status

```
┌──────────────────────────────────────────────────────────────┐
│ AUTHENTICATION FLOW STATUS                                   │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ ❌ Login Screen        → NO UI COMPONENT                    │
│                                                              │
│ ❌ Register Screen     → NO UI COMPONENT                    │
│                                                              │
│ ✅ Token Storage      → localStorage (auth:token key)      │
│                          ⚠️ Not encrypted                   │
│                          ⚠️ XSS vulnerability               │
│                                                              │
│ ✅ Token Injection    → Axios interceptor adds Bearer token│
│                                                              │
│ ❌ Token Refresh      → NOT IMPLEMENTED                    │
│                          Tokens are long-lived             │
│                                                              │
│ ❌ Logout             → NO API CALL                         │
│                          Only removes from localStorage     │
│                                                              │
│ ⚠️  Token Inconsistency → AuthContext provides 'token'     │
│                          FeedView expects 'accessToken'    │
│                          → RUNTIME BUG! accessToken = undef│
│                                                              │
│ ❌ CSRF Protection    → NO VISIBLE TOKENS/HEADERS          │
│                                                              │
│ ❌ Session Validation → NO PERIODIC CHECK                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Integration Summary Table

```
Feature          | Service      | REST | WebSocket | Status    | Priority
─────────────────┼──────────────┼──────┼───────────┼───────────┼──────────
1:1 Messaging    | Messaging    | ✅   | ✅        | 70%       | HIGH
Group Messaging  | Messaging    | ❌   | ❌        | 0%        | MEDIUM
Message Search   | Messaging    | ❌   | ❌        | 0%        | MEDIUM
Message Enc.     | Messaging    | ✅   | ✅        | STUBBED   | CRITICAL
Message React.   | Messaging    | ❌   | ❌        | 0%        | LOW
─────────────────┼──────────────┼──────┼───────────┼───────────┼──────────
Photo Upload     | User Service | ✅   | ❌        | 90%       | HIGH
Video Upload     | User Service | ✅   | ❌        | 90%       | HIGH
Post Edit        | User Service | ❌   | ❌        | 0%        | LOW
─────────────────┼──────────────┼──────┼───────────┼───────────┼──────────
Feed Display     | User Service | ✅   | ❌        | 50%       | CRITICAL
Post Like        | User Service | ❌   | ❌        | 0%        | CRITICAL
Post Comment     | User Service | ❌   | ❌        | 0%        | CRITICAL
Post Search      | User Service | ❌   | ❌        | 0%        | HIGH
─────────────────┼──────────────┼──────┼───────────┼───────────┼──────────
User Profile     | User Service | ❌   | ❌        | 0%        | HIGH
Follow/Unfollow  | User Service | ❌   | ❌        | 0%        | HIGH
User Search      | User Service | ❌   | ❌        | 0%        | MEDIUM
─────────────────┼──────────────┼──────┼───────────┼───────────┼──────────
Notifications    | Both         | ❌   | ❌        | 0%        | HIGH
```

