# Nova iOS Codebase Analysis: API Integration & Feature Status

## Executive Summary

The Nova iOS codebase (`ios/NovaSocialApp`) has a clean, modular architecture with proper separation of concerns. Core features like Authentication, Messaging, Feed, and Notifications are well-implemented. However, there are significant gaps in Video Streaming, Post Creation, and synchronization with the backend's full feature set.

**Critical Issues:**
1. No video upload/post creation API integration
2. Limited streaming/RTMP feature support
3. Missing advanced features (Stories, Experiments, Trending)
4. Config hardcoded to local development IP (192.168.31.154)
5. Incomplete notification system

---

## 1. Current API Integration Architecture

### Network Layer (Clean Design)

**File:** `/Network/Core/APIClient.swift`
- Centralized HTTP client with:
  - Automatic JSON encoding/decoding
  - ISO8601 date handling
  - Bearer token injection
  - Proper error handling
- **Good:** No retry logic here (delegated to RequestInterceptor)

**File:** `/Network/Core/AuthManager.swift` (Singleton)
- Token storage in Keychain (secure)
- AccessToken/RefreshToken management
- Pre-emptive token expiry check (60s buffer)
- User session restoration
- **Issue:** No concurrent request deduplication during token refresh (partially handled by RequestInterceptor)

**File:** `/Network/Core/RequestInterceptor.swift`
- Uses Swift Actor for thread-safe token refresh
- Exponential backoff retry (2^attempt, max 8s + jitter)
- Automatic 401 handling with token refresh
- Deduplicates concurrent refresh requests
- **Good:** Proper Linus-style design (simple, effective)

**File:** `/Network/Utils/AppConfig.swift`
```swift
case .development:
    return URL(string: "http://192.168.31.154:8001")!  // ← HARDCODED IP!
case .production:
    return URL(string: "https://api.nova.social")!
```
- **Issue:** Dev IP hardcoded - should use environment variables or Info.plist

---

## 2. Feature Implementation Status

### ✅ IMPLEMENTED FEATURES

#### Authentication
**Files:** `/Network/Repositories/AuthRepository.swift`

Endpoints Implemented:
- `POST /auth/register` - ✅
- `POST /auth/login` - ✅
- `POST /auth/logout` - ✅
- `POST /auth/verify-email` - ✅
- `POST /auth/refresh` - ✅ (via RequestInterceptor)

**Status:** Complete

---

#### Messaging (1:1 Chat with E2E Encryption)
**Files:** 
- `/Network/Repositories/MessagingRepository.swift`
- `/Services/WebSocket/ChatSocket.swift`
- `/ViewModels/Chat/ChatViewModel.swift`

Endpoints:
- `PUT /api/v1/users/me/public-key` - ✅ (Upload public key)
- `GET /api/v1/users/{userId}/public-key` - ✅
- `GET /api/v1/conversations/{conversationId}/messages` - ✅ (with cursor pagination)
- `POST /api/v1/messages` - ✅ (Send encrypted message)
- `POST /api/v1/conversations` - ✅ (Create direct conversation)

WebSocket Connection:
```swift
ws://localhost:8085/ws?conversation_id=...&user_id=...&token=...
```
- Message events: `{"type":"message.new","data":{...}}`
- Typing events: `{"type":"typing","conversation_id":"...","user_id":"..."}`

**Encryption:** NaCl box (asymmetric) for message encryption
- Uses `CryptoKeyStore` for key management
- Decryption happens client-side
- **Status:** Complete but assumes messaging-service running on port 8085

---

#### Feed & Posts
**Files:**
- `/Network/Repositories/FeedRepository.swift`
- `/Network/Repositories/PostRepository.swift`
- `/ViewModels/Feed/FeedViewModel.swift`

Endpoints Implemented:
- `GET /feed` - ✅ (cursor-based pagination)
- `GET /feed/explore` - ✅
- `GET /posts/{id}` - ✅
- `POST /posts` - ⚠️ **INCOMPLETE** (no image upload)
- `DELETE /posts/{id}` - ✅
- `POST /posts/{id}/like` - ✅
- `DELETE /posts/{id}/like` - ✅
- `GET /posts/{id}/comments` - ✅
- `POST /posts/{id}/comments` - ✅
- `DELETE /comments/{id}` - ✅

**Major Issue:** Post creation stubbed but incomplete:
```swift
func createPost(image: UIImage, caption: String?) async throws -> Post {
    // Step 1: Compress image ✅
    // Step 2: Get presigned S3 URL ✅
    let uploadInfo = try await requestUploadURL(contentType: "image/jpeg")
    // Step 3: Upload to S3 ✅
    // Step 4: Create post record ✅
}
```
- `POST /posts/upload-url` - Called but endpoint path unclear
- S3 presigned URL upload works
- But: No multi-image, no video support

**Feed Features:**
- Cursor-based pagination ✅
- Smart prefetch (5 items before bottom) ✅
- Optimistic UI updates (like/comment) ✅
- Caching with TTL ✅
- Request deduplication ✅

**Status:** Core feed works, post creation incomplete

---

#### Notifications
**Files:** `/Network/Repositories/NotificationRepository.swift`

Endpoints:
- `GET /notifications` - ✅ (cursor pagination)
- `PUT /notifications/{id}/read` - ✅
- `PUT /notifications/read-all` - ✅

**Issue:** No real-time push notification setup
- No APNs/FCM integration visible
- No WebSocket listener for notifications
- Basic polling API only

**Status:** Partial (read-only, no real-time delivery)

---

#### Users & Relationships
**Files:** `/Network/Repositories/UserRepository.swift`

Endpoints:
- `GET /users/{username}` - ✅
- `GET /users/{userId}/posts` - ✅
- `PUT /users/me` - ✅ (Update profile)
- `GET /users/search` - ✅
- `POST /users/{id}/follow` - ✅ (with deduplication)
- `DELETE /users/{id}/follow` - ✅ (with deduplication)
- `GET /users/{userId}/followers` - ✅
- `GET /users/{userId}/following` - ✅

**Status:** Complete

---

### ❌ MISSING/INCOMPLETE FEATURES

#### Video Streaming/RTMP
**Backend support exists:** `/backend/user-service/src/handlers/streams.rs`
- RTMP webhook handling
- Stream discovery
- Stream analytics
- Stream categories

**iOS implementation:** ❌ NOT IMPLEMENTED
- No stream list endpoint integration
- No RTMP publisher (livestream broadcast)
- VideoManager only handles local video processing:
  - Thumbnail generation ✅
  - Video compression ✅
  - Metadata extraction ✅
  - But no video upload to backend

**Missing endpoints:**
- `GET /streams` (list active streams)
- `POST /streams` (create stream)
- `GET /streams/{id}` (get stream details)
- `POST /streams/{id}/comments` (stream chat)
- RTMP ingestion endpoint

---

#### Video Upload (for Posts/Reels)
**Backend support exists:**
- `videos_table` in migrations
- Video transcoding pipeline
- Video ranking system
- Reels feature (`/handlers/reels.rs`)

**iOS implementation:** ❌ NOT IMPLEMENTED
- VideoManager handles local compression
- But no API endpoint calls
- No presigned URL request for video
- No progress tracking

---

#### Stories
**Backend support exists:** `/handlers/stories.rs`
- Create story with image/video
- Story viewing
- Story deletion

**iOS implementation:** ❌ NOT IMPLEMENTED
- No repository
- No view model
- No API integration

---

#### 2FA (Two-Factor Authentication)
**Backend support exists:** `/handlers/auth.rs`
- `POST /auth/enable-2fa`
- `POST /auth/confirm-2fa`
- `POST /auth/verify-2fa`

**iOS implementation:** ❌ NOT IMPLEMENTED

---

#### Experiments/A-B Testing
**Backend support exists:** `/handlers/experiments.rs`
- Experiment management
- Variant assignment
- Metrics recording

**iOS implementation:** ❌ NOT IMPLEMENTED

---

#### Trending/Recommendations
**Backend support exists:** `/handlers/trending.rs`

**iOS implementation:** ❌ NOT IMPLEMENTED

---

#### OAuth (Apple/Google Sign-In)
**Files exist:**
- `/Auth/AppleSignInService.swift`
- `/Auth/GoogleSignInService.swift`

**Status:** Stubbed, not integrated with backend
- No backend OAuth endpoints called
- No token exchange flow

---

## 3. Synchronization Issues: iOS vs Web Frontend

### Configuration Management

**Web Frontend** (`frontend/src/services/api/client.ts`):
```typescript
const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:8080';
```
- Uses environment variables
- Configurable via `.env` files

**iOS App** (`Network/Utils/AppConfig.swift`):
```swift
case .development:
    return URL(string: "http://192.168.31.154:8001")!  // Hardcoded!
```
- **Mismatch:** Dev server likely runs on `localhost:8001` or `192.168.1.x`
- **Problem:** Will fail on different networks

### WebSocket Implementation

**Web Frontend** (`EnhancedWebSocketClient.ts`):
```typescript
export class EnhancedWebSocketClient {
  // - Full reconnection logic
  // - Automatic backoff
  // - Message queuing during disconnection
  // - Type-safe handlers
}
```

**iOS** (`ChatSocket.swift`):
```swift
func connect(conversationId: UUID, meUserId: UUID, jwtToken: String?, peerPublicKeyB64: String?) {
    var comps = URLComponents(url: AppConfig.messagingWebSocketBaseURL.appendingPathComponent("/ws"), 
                              resolvingAgainstBaseURL: false)!
    // Simple URLSessionWebSocketTask
    // No auto-reconnect
    // No message queuing
}
```

**Differences:**
| Feature | Web | iOS |
|---------|-----|-----|
| Reconnection logic | ✅ With backoff | ❌ Manual only |
| Message queuing offline | ✅ | ❌ |
| Heartbeat/ping | ✅ | ❌ |
| Type safety | ✅ TypeScript | ⚠️ Manual JSON parsing |

### Error Handling

**Web:**
```typescript
export enum ErrorType {
  NETWORK_ERROR = 'NETWORK_ERROR',
  UNAUTHORIZED = 'UNAUTHORIZED',
  VALIDATION_ERROR = 'VALIDATION_ERROR',
  // ... 10+ types
}
```

**iOS:**
```swift
enum APIError: LocalizedError {
    case unauthorized
    case decodingError
    case serverError
    // ... basic types
}
```

**Issue:** iOS lacks granular error classification needed for UI decisions

### Request Deduplication

**Web:** ❌ Not implemented
- Can send duplicate requests

**iOS:** ✅ Implemented
- `RequestDeduplicator` class
- Prevents duplicate follows, likes, comments
- Uses key-based deduplication

---

## 4. Critical Design Issues

### Issue 1: Hardcoded Development IP

**Current:**
```swift
case .development:
    return URL(string: "http://192.168.31.154:8001")!
```

**Problem:**
- Only works on specific network
- Will fail for other developers
- Cannot test against staging/production easily

**Fix:**
```swift
case .development:
    let ip = ProcessInfo.processInfo.environment["NOVA_DEV_IP"] ?? "localhost"
    return URL(string: "http://\(ip):8001")!
```

### Issue 2: Config Mismatch

**iOS uses:**
```
HTTP://192.168.31.154:8001  (user-service on port 8001)
WS://localhost:8085         (messaging-service on port 8085)
```

**Need clarification:**
- Is `192.168.31.154` the same machine?
- Should WebSocket also use same IP?

### Issue 3: Token Refresh Race Condition (Partially Mitigated)

**Current:** Actor prevents concurrent refresh, but:
```swift
if authenticated && AuthManager.shared.isTokenExpired {
    try await refreshTokenIfNeeded()
}
```

Could race if 2 requests check `isTokenExpired` before first refresh completes.

**Better:**
```swift
if authenticated {
    try await ensureTokenValid()  // Atomic operation
}
```

### Issue 4: No Offline Queue for Messaging

**Web:** Has offline queue for messages
**iOS:** ❌ No mechanism to queue/retry failed sends

ChatViewModel just shows error:
```swift
} catch {
    self.error = error.localizedDescription
}
```

Should queue for retry when connection restores.

### Issue 5: Weak WebSocket Error Handling

```swift
socket.onError = { [weak self] err in
    Task { @MainActor in self?.error = err.localizedDescription }
}
```

No reconnection attempt. User must manually refresh.

---

## 5. API Endpoint Completeness Matrix

| Feature | Backend Handler | iOS Implemented | Notes |
|---------|---|---|---|
| Auth - Register | ✅ auth.rs | ✅ | Complete |
| Auth - Login | ✅ | ✅ | Complete |
| Auth - Logout | ✅ | ✅ | Complete |
| Auth - Verify Email | ✅ | ✅ | Complete |
| Auth - Token Refresh | ✅ | ✅ | Complete |
| Auth - 2FA Enable | ✅ | ❌ | Not implemented |
| Auth - 2FA Verify | ✅ | ❌ | Not implemented |
| Feed - Get Feed | ✅ feed.rs | ✅ | Complete with caching |
| Feed - Explore | ✅ | ✅ | Complete |
| Posts - Create | ✅ posts.rs | ⚠️ | Image only, no video |
| Posts - Get | ✅ | ✅ | Complete |
| Posts - Delete | ✅ | ✅ | Complete |
| Posts - Like | ✅ | ✅ | With dedup |
| Posts - Unlike | ✅ | ✅ | With dedup |
| Comments - Create | ✅ comments.rs | ✅ | With dedup |
| Comments - Get | ✅ | ✅ | Complete |
| Comments - Delete | ✅ | ✅ | Complete |
| Users - Get Profile | ✅ users.rs | ✅ | Complete |
| Users - Update | ✅ | ✅ | Complete |
| Users - Search | ✅ | ✅ | Complete |
| Users - Follow | ✅ relationships.rs | ✅ | With dedup |
| Users - Unfollow | ✅ | ✅ | With dedup |
| Users - Get Followers | ✅ | ✅ | Complete |
| Users - Get Following | ✅ | ✅ | Complete |
| Messaging - Get History | ✅ messaging-service | ✅ | E2E encrypted |
| Messaging - Send | ✅ | ✅ | E2E encrypted |
| Messaging - Public Key Get | ✅ | ✅ | Complete |
| Messaging - Public Key Upload | ✅ | ✅ | Best-effort |
| Messaging - WebSocket | ✅ | ✅ | Limited error handling |
| Notifications - Get | ✅ | ✅ | Basic only |
| Notifications - Mark Read | ✅ | ✅ | Complete |
| Notifications - Push (Real-time) | ✅ backend | ❌ iOS | No APNs integration |
| Stories - Create | ✅ stories.rs | ❌ | Not implemented |
| Stories - Get | ✅ | ❌ | Not implemented |
| Stories - Delete | ✅ | ❌ | Not implemented |
| Videos - Upload | ✅ videos.rs | ❌ | Only local processing |
| Videos - Get Metadata | ✅ | ❌ | Not implemented |
| Streams - Create | ✅ streams.rs | ❌ | Not implemented |
| Streams - List | ✅ | ❌ | Not implemented |
| Streams - Get Details | ✅ | ❌ | Not implemented |
| Experiments - Create | ✅ experiments.rs | ❌ | Not implemented |
| Trending - Get | ✅ trending.rs | ❌ | Not implemented |

---

## 6. Code Quality Assessment

### Strengths

1. **Clean Architecture:**
   - Clear separation: APIClient → RequestInterceptor → Repository → ViewController
   - Single responsibility principle followed

2. **Security:**
   - Tokens stored in Keychain (not UserDefaults)
   - Bearer token injection automatic
   - E2E encryption for messaging
   - No hardcoded passwords/keys

3. **Resilience:**
   - Exponential backoff retry logic
   - Token refresh with deduplication
   - Optimistic UI updates with rollback
   - Request deduplication for idempotent operations

4. **Performance:**
   - Feed caching with TTL
   - Image compression
   - Cursor-based pagination
   - Request deduplication prevents duplicate network calls

### Weaknesses

1. **Incomplete Features:**
   - Video upload
   - Stories
   - Live streaming
   - Push notifications
   - 2FA
   - OAuth (partially stubbed)

2. **Configuration:**
   - Hardcoded development IP
   - WebSocket URL hardcoded
   - No .env support

3. **Error Handling:**
   - Limited error types
   - WebSocket errors not retried
   - No offline queue for failed requests

4. **Testing:**
   - Basic mocks exist
   - No comprehensive integration tests
   - No fixtures for common scenarios

5. **Documentation:**
   - Missing API documentation
   - No setup guide for dev environment
   - WebSocket protocol not documented

---

## 7. Recommended Priority Fixes

### Priority 1 (Critical - Blocks Development)

1. **Fix Development Configuration**
   - [ ] Move IP to environment variable
   - [ ] Add support for `.env` files or Info.plist
   - [ ] Document network setup

2. **Complete Post Creation**
   - [ ] Implement upload URL endpoint integration
   - [ ] Add image picker integration test
   - [ ] Add progress tracking
   - [ ] Support multi-image posts

3. **Implement Offline Queue for Messaging**
   - [ ] Queue failed sends
   - [ ] Retry on connection restore
   - [ ] Persist queue to disk

### Priority 2 (High - Affects Feature Completeness)

4. **Enhance WebSocket Handling**
   - [ ] Auto-reconnect with backoff
   - [ ] Heartbeat/ping mechanism
   - [ ] Message queuing during disconnect
   - [ ] Better error recovery

5. **Implement Video Upload**
   - [ ] Support video selection
   - [ ] Compression/transcoding
   - [ ] Progress tracking
   - [ ] Multiple video support

6. **Add Push Notifications**
   - [ ] APNs device token registration
   - [ ] FCM fallback
   - [ ] Notification handler for foreground/background

### Priority 3 (Medium - Nice to Have)

7. **Implement Stories**
8. **Add Live Streaming Support**
9. **Implement 2FA**
10. **Trending/Recommendations Display**

---

## 8. Backend Service Endpoint Reference

### User Service (Port 8001)
```
POST   /auth/register
POST   /auth/login
POST   /auth/logout
POST   /auth/verify-email
POST   /auth/refresh
GET    /feed
GET    /feed/explore
POST   /posts
GET    /posts/{id}
DELETE /posts/{id}
POST   /posts/{id}/like
DELETE /posts/{id}/like
GET    /posts/{id}/comments
POST   /posts/{id}/comments
DELETE /comments/{id}
GET    /users/{username}
PUT    /users/me
GET    /users/search
POST   /users/{id}/follow
DELETE /users/{id}/follow
GET    /users/{id}/followers
GET    /users/{id}/following
GET    /notifications
PUT    /notifications/{id}/read
PUT    /notifications/read-all
POST   /posts/upload-url  (presigned S3)
GET    /streams
POST   /streams
GET    /stories
POST   /stories
GET    /videos/{id}
```

### Messaging Service (Port 8085)
```
WS     /ws (WebSocket endpoint)
  Params: conversation_id, user_id, token
  Messages: {"type":"message.new","data":{...}}
           {"type":"typing","conversation_id":"...","user_id":"..."}
```

Note: Messaging service has its own REST API:
```
PUT    /api/v1/users/me/public-key
GET    /api/v1/users/{userId}/public-key
GET    /api/v1/conversations/{conversationId}/messages
POST   /api/v1/messages
POST   /api/v1/conversations
```

---

## 9. Data Model Synchronization

All core models properly defined with CodingKeys for snake_case conversion:

- ✅ User (with stats)
- ✅ Post (with video_ids support backend, but iOS only uses images)
- ✅ Comment
- ✅ Notification
- ⚠️ Message (encrypted content, nonce handling correct)
- ⚠️ Stream (model exists but not integrated into iOS)
- ❌ Story (model exists backend, missing iOS)

---

## Summary

The Nova iOS app has a **solid foundation** with clean architecture and good security practices. Core features (auth, feed, messaging, notifications) are well-implemented. However, **critical gaps** exist in:

1. **Development Configuration** - Hardcoded IP prevents multi-machine development
2. **Post Creation** - Video upload not implemented
3. **Video Features** - Stories, live streaming, video posts not implemented  
4. **Real-time Features** - WebSocket lacks reconnection, offline queue missing
5. **Push Notifications** - No APNs/FCM integration

The codebase is **80% feature-complete** for social feed functionality but **40% for media/streaming** features.

Linus would note: **The special cases (video upload, streaming) that don't fit the pattern should be handled at the pattern level, not bolted on later.** Currently, the architecture assumes simple REST endpoints but video features need different handling (presigned URLs, progress tracking, multiple formats).
