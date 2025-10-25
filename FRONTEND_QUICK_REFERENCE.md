# Nova Frontend - Quick Reference Guide

## Project Overview
- **Framework**: React 18.2.0 + TypeScript 5.6.3
- **Build Tool**: Vite 5.4.8
- **State Management**: Zustand 4.5.2
- **HTTP Client**: Axios 1.7.7
- **WebSocket**: Native WebSocket API (ws 8.18.0)
- **Status**: ~60% Complete (3 main features partially implemented)

## Architecture at a Glance

```
Frontend (React)
├── 2 Backend Services
│   ├── User Service (Port 8080) - REST for posts, feed, videos
│   └── Messaging Service (Port 8085) - REST + WebSocket for messaging
├── 4 Zustand Stores (State Management)
│   ├── appStore - Global UI state
│   ├── messagingStore - Conversations and messages
│   ├── connectionStore - WebSocket metrics
│   └── AuthContext (React Context) - Auth state
└── 3 Main Features
    ├── Messaging (70% complete)
    ├── Post Creation (60% complete)
    └── Feed Display (50% complete)
```

## Connected Services Summary

| Service | Port | Type | Status | Features |
|---------|------|------|--------|----------|
| User Service | 8080 | REST | ✅ 60% connected | Feed, posts, uploads |
| Messaging Service | 8085 | REST + WS | ✅ 70% connected | 1:1 messaging, real-time |

## Feature Completion Matrix

### Messaging (70% Complete)
```
Working:
✅ Create 1:1 conversations
✅ Send/receive messages (REST)
✅ Real-time delivery (WebSocket)
✅ Message history
✅ Typing indicators
✅ Auto-reconnection (exponential backoff)
✅ Offline message queue
✅ Idempotency keys

Broken/Missing:
❌ Message encryption (stubbed, messages in plaintext)
❌ Group conversations
❌ Message search
❌ Message reactions
❌ Read receipts
```

### Post Creation (60% Complete)
```
Working:
✅ Photo upload (JPEG, PNG, WebP, HEIC)
✅ Video upload (MP4, MOV, WebM)
✅ Multiple file batch upload
✅ File validation & size limits
✅ S3 presigned URL upload
✅ Upload progress tracking
✅ Caption input (2200 chars)
✅ SHA-256 file hashing

Missing:
❌ Image cropping/editing
❌ Video trimming
❌ Hashtag suggestions
❌ Privacy settings
```

### Feed Display (50% Complete)
```
Working:
✅ Fetch personalized feed
✅ Cursor pagination
✅ Display posts with images/videos
✅ Show engagement metrics (display only)
✅ Post card UI

CRITICAL MISSING:
❌ Like functionality (shows "coming soon" alert)
❌ Comment functionality (shows "coming soon" alert)
❌ POST /posts/{id}/like endpoint integration
❌ GET /posts/{id}/comments endpoint integration

Other missing:
❌ Share/repost
❌ User profiles
❌ Search
❌ Notifications
```

## Critical Issues & Bugs

### 1. AUTH TOKEN INCONSISTENCY (HIGH PRIORITY)
**Location**: `src/context/AuthContext.tsx` vs `src/components/Feed/FeedView.tsx`

**Problem**:
```typescript
// AuthContext.tsx provides:
token: string | null

// FeedView.tsx expects:
const { accessToken } = useAuth(); // ❌ undefined!
```

**Impact**: FeedView always has undefined accessToken, breaking feed fetch.

**Fix**: Update AuthContext to export `accessToken` property.

---

### 2. LIKE/COMMENT NOT IMPLEMENTED (CRITICAL)
**Location**: `src/components/Post/PostCard.tsx`

**Current Code**:
```typescript
const handleLike = async (postId: string) => {
  console.log('Like post:', postId);
  alert('Like functionality coming soon!'); // ❌ Stub implementation
};
```

**Missing Backend Endpoints**:
- `POST /posts/{id}/like`
- `DELETE /posts/{id}/like`
- `POST /posts/{id}/comment`
- `GET /posts/{id}/comments`

**Impact**: Feed engagement is completely broken. Users cannot like or comment on posts.

---

### 3. MESSAGE ENCRYPTION STUBBED (CRITICAL SECURITY)
**Location**: `src/services/encryption/client.ts`, `src/components/MessagingUI/MessageThread.tsx`

**Current Code**:
```typescript
<i>{m.preview ?? '(encrypted)'}</i> // Shows (encrypted) but actually plaintext!
```

**Status**: Encryption services exist but are not wired up. Messages sent in plaintext.

**Impact**: Private messages are not encrypted. Security breach.

---

### 4. TOKEN STORED UNENCRYPTED (HIGH SECURITY)
**Location**: `src/context/AuthContext.tsx`

**Current Code**:
```typescript
localStorage.setItem('auth:token', token); // ❌ Plaintext in localStorage
```

**Issues**:
- XSS attacks can steal token
- No token refresh mechanism
- No session expiration check
- Token is long-lived

---

### 5. N+1 QUERY PATTERN IN FEED (PERFORMANCE)
**Location**: `src/components/Feed/FeedView.tsx`

**Current Code**:
```typescript
// Fetch feed returns post IDs
const feedData = await fetch(`${apiBase}/feed?...`);

// Then fetch each post individually
const postDetails = await Promise.all(
  feedData.posts.map((postId) =>
    fetch(`${apiBase}/posts/${postId}`, ...) // ❌ One request per post!
  )
);
```

**Impact**: 10 posts = 1 feed request + 10 individual requests = 11 total. Slow.

**Fix**: Backend should support `/feed?include=full` or batch endpoint.

---

## File Structure Quick Map

```
src/
├── App.tsx                          ← Main shell, tabs (messaging, feed, create)
├── context/
│   └── AuthContext.tsx              ← ⚠️ Has token inconsistency bug
├── stores/
│   ├── appStore.ts                  ← Online status, theme
│   ├── messagingStore.ts            ← Conversations, messages (70% complete)
│   └── connectionStore.ts           ← WebSocket connection state
├── services/
│   ├── api/
│   │   ├── client.ts               ← Axios retry wrapper ✅
│   │   ├── postService.ts          ← Photo/video uploads ✅
│   │   ├── errors.ts               ← Error classification ✅
│   │   └── errorStore.ts
│   ├── websocket/
│   │   └── EnhancedWebSocketClient.ts ← Auto-reconnect ✅
│   └── encryption/
│       └── client.ts               ← 🚧 Stubbed, not wired up
├── components/
│   ├── MessagingUI/
│   │   ├── ConversationList.tsx     ✅
│   │   ├── MessageThread.tsx        ✅
│   │   └── MessageComposer.tsx      ✅
│   ├── PostCreator/
│   │   ├── PostCreator.tsx          ✅ (60% complete)
│   │   └── MediaPreview.tsx         ✅
│   ├── Feed/
│   │   └── FeedView.tsx             ⚠️ (50% complete, has bugs)
│   ├── Post/
│   │   └── PostCard.tsx             ⚠️ (Like/comment not implemented)
│   └── VideoPlayer/
│       └── VideoPlayer.tsx          🚧 (Stub)
└── package.json                     ⚠️ Missing routing, component libs
```

## Backend Endpoints Status

### ✅ Implemented & Working (6 endpoints)
1. `GET /feed` - Fetch feed post IDs
2. `GET /posts/{id}` - Get post details
3. `POST /api/v1/posts/upload/init` - Init photo upload
4. `POST /api/v1/posts/upload/complete` - Complete photo upload
5. `POST /api/v1/videos/upload-url` - Get video upload URL
6. `POST /api/v1/videos` - Create video metadata
7. `POST /conversations` - Create 1:1 conversation
8. `GET /conversations/{id}/messages` - Load message history
9. `POST /conversations/{id}/messages` - Send message
10. `WS /ws?conversation_id=...` - WebSocket messaging

### ❌ Critical Missing (4 endpoints)
1. `POST /posts/{id}/like` - Like a post
2. `DELETE /posts/{id}/like` - Unlike a post
3. `POST /posts/{id}/comment` - Comment on post
4. `GET /posts/{id}/comments` - Fetch comments

### ❌ Not Started (50+ endpoints)
- Authentication (login, register, logout)
- User profiles
- Follow/unfollow
- Search (posts, users, hashtags)
- Notifications
- Message search
- Group messaging
- Message reactions
- Post reactions
- And many more...

## Quick Integration Checklist

### Immediate (Must fix before production)
- [ ] Fix AuthContext token naming (add `accessToken` export)
- [ ] Implement like/comment endpoints and integrate frontend
- [ ] Implement message encryption
- [ ] Add login/register UI
- [ ] Add logout functionality

### Short-term (1-2 weeks)
- [ ] User profile pages
- [ ] Follow/unfollow
- [ ] Search functionality
- [ ] Notifications system
- [ ] Message encryption

### Medium-term (3-4 weeks)
- [ ] Group messaging
- [ ] Message reactions
- [ ] Post reactions
- [ ] Advanced search
- [ ] Analytics/metrics

### Nice to have
- [ ] Post scheduling
- [ ] Drafts
- [ ] Trending
- [ ] Video filters
- [ ] Image editing

## Environment Configuration

```env
# .env.development

# User Service (REST API)
VITE_API_BASE=http://localhost:8080

# Messaging Service (WebSocket)
VITE_WS_BASE=ws://localhost:8085
```

**Missing configuration**:
- S3 bucket URL
- API version
- Feature flags
- Analytics keys

## Dependencies

```json
{
  "axios": "1.7.7",
  "react": "18.2.0",
  "react-dom": "18.2.0",
  "ws": "8.18.0",
  "zustand": "4.5.2"
}
```

**Missing critical dependencies**:
- `react-router-dom` - Multi-page routing
- `@hookform/react` or `formik` - Form validation
- UI component library (Material-UI, Chakra, etc.)
- `react-query` or `swr` - Data fetching/caching
- `vitest` - Testing (exists but not used)

## Testing

**Test files**: 5 (minimal coverage)
- `MessageComposer.test.ts`
- `PostCreator.test.tsx`
- `websocketStore.test.ts`
- `localStorage.test.ts`
- `visual-verification.test.ts`

**Status**: Incomplete, no integration tests, no E2E tests.

## Performance Issues

1. **N+1 Queries**: Feed fetches each post individually
2. **No Caching**: Every component re-fetches same data
3. **No Deduplication**: Same request sent multiple times
4. **No Infinite Scroll**: Uses "Load More" button instead
5. **No Lazy Loading**: Images/videos loaded immediately

## Security Issues

| Issue | Severity | Fix |
|-------|----------|-----|
| Token in localStorage plaintext | HIGH | Encrypt or use httpOnly cookie |
| No CSRF tokens | HIGH | Add CSRF protection |
| Messages unencrypted | CRITICAL | Implement E2E encryption |
| Long-lived tokens | MEDIUM | Add refresh token rotation |
| No rate limiting | MEDIUM | Add client-side rate limiting |
| XSS vulnerabilities | HIGH | Sanitize all user input |

## Key Metrics

```
Total Source Files: 32
- Components: 14
- Services: 8
- Stores: 3
- Context: 1
- Tests: 5
- Other: 1

Lines of Code: ~8,500
Test Coverage: <10%

Feature Completeness:
- Messaging: 70%
- Posts: 60%
- Feed: 50%
- Overall: 60%
```

## Run Commands

```bash
# Development
npm run dev              # Starts Vite dev server on :5173

# Production
npm run build            # Build for production
npm run preview          # Preview production build

# Testing
npm run test             # Run vitest
```

## Developer Notes

1. **Architecture is good** - Centralized API client, proper error handling, decent state management
2. **Implementation is incomplete** - Critical features stubbed or missing
3. **Security needs work** - Token handling, encryption, CSRF
4. **Testing is minimal** - Only 5 test files, mostly incomplete
5. **No routing** - All features in single view/tabs
6. **Token bug breaks feed** - `accessToken` vs `token` naming inconsistency

## Next Steps (Priority Order)

1. **Emergency Fix**: Update AuthContext to export `accessToken` (fixes feed immediately)
2. **Critical Feature**: Implement like/comment endpoints
3. **Security**: Implement message encryption
4. **Auth Flow**: Login/register/logout UI
5. **Routing**: Add React Router for multi-page support

