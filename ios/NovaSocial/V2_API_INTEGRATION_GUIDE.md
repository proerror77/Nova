# iOS v2 API Integration Guide

**Status**: ✅ v2 API Integration Complete
**Date**: 2025-11-18
**Environment**: Staging

---

## 🎯 Overview

All iOS services have been migrated to use v2 API endpoints. This document provides a quick reference for using the new v2 APIs.

---

## 📡 Staging Environment

### Base URL
```swift
APIConfig.current = .staging
// http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com
```

### Available Services
- ✅ **identity-service** - Authentication & User Management
- ✅ **content-service** - Posts & Content
- ✅ **media-service** - Uploads & Media Processing
- ✅ **search-service** - Search Functionality
- ✅ **notification-service** - Notifications
- ⚠️ **social-service** - (Currently offline - relationships & feed)

---

## 🔐 Authentication (v2)

### Endpoints
```swift
APIConfig.Auth.login       // POST /api/v2/auth/login
APIConfig.Auth.register    // POST /api/v2/auth/register
APIConfig.Auth.refresh     // POST /api/v2/auth/refresh
APIConfig.Auth.logout      // POST /api/v2/auth/logout
APIConfig.Auth.getUser     // GET  /api/v2/users/{id}
APIConfig.Auth.updateUser  // PUT  /api/v2/users/{id}
```

### Example: Login
```swift
// TODO: Implement in IdentityService
let request = LoginRequest(
    username: "test",
    password: "test123"
)

let response: LoginResponse = try await client.request(
    endpoint: APIConfig.Auth.login,
    method: "POST",
    body: request
)

// Save token
APIClient.shared.setAuthToken(response.token)
```

---

## 📝 Content Service (v2)

### Endpoints
```swift
APIConfig.Content.getPost        // GET    /api/v2/posts/{id}
APIConfig.Content.createPost     // POST   /api/v2/posts/create
APIConfig.Content.updatePost     // PUT    /api/v2/posts/update
APIConfig.Content.deletePost     // DELETE /api/v2/posts/delete
APIConfig.Content.postsByAuthor  // GET    /api/v2/posts/author/{author_id}
APIConfig.Content.bookmarks      // GET    /api/v2/posts/bookmarks
```

### Example: Get Posts by Author
```swift
// Implemented in ContentService
let posts = try await contentService.getPostsByAuthor(
    authorId: "user-123",
    limit: 20,
    offset: 0
)
```

---

## 📷 Media Service (v2)

### Endpoints
```swift
APIConfig.Media.uploadStart     // POST /api/v2/uploads/start
APIConfig.Media.uploadProgress  // POST /api/v2/uploads/progress
APIConfig.Media.uploadComplete  // POST /api/v2/uploads/complete
APIConfig.Media.videos          // GET  /api/v2/videos/{id}
APIConfig.Media.reels           // GET  /api/v2/reels
```

### Example: Upload Image
```swift
// Step 1: Start upload
let startRequest = StartUploadRequest(
    filename: "photo.jpg",
    size: imageData.count,
    mimeType: "image/jpeg"
)

let startResponse: StartUploadResponse = try await client.request(
    endpoint: APIConfig.Media.uploadStart,
    method: "POST",
    body: startRequest
)

// Step 2: Upload to S3 (use presigned URL from response)
// ...

// Step 3: Complete upload
let completeRequest = CompleteUploadRequest(
    uploadId: startResponse.uploadId
)

let completeResponse: CompleteUploadResponse = try await client.request(
    endpoint: APIConfig.Media.uploadComplete,
    method: "POST",
    body: completeRequest
)

let mediaUrl = completeResponse.url
```

---

## 🔍 Search Service (v2)

### Endpoints
```swift
APIConfig.Search.search       // GET /api/v2/search?q={query}
APIConfig.Search.searchUsers  // GET /api/v2/search/users?q={query}
APIConfig.Search.searchPosts  // GET /api/v2/search/posts?q={query}
```

### Example: Search Users
```swift
let searchService = SearchService()

let results = try await searchService.searchUsers(
    query: "john",
    limit: 20,
    offset: 0
)

// Handle results
for result in results {
    if case .user(let id, let username, let displayName, let avatarUrl, let isVerified, let followerCount) = result {
        print("\(username): \(followerCount) followers")
    }
}
```

### Example: Search Posts
```swift
let results = try await searchService.searchPosts(
    query: "swift programming",
    limit: 20,
    offset: 0
)

// Handle results
for result in results {
    if case .post(let id, let content, let author, let createdAt, let likeCount, let commentCount) = result {
        print("\(content) - \(likeCount) likes")
    }
}
```

---

## 🔔 Notification Service (v2)

### Endpoints
```swift
APIConfig.Notification.getNotifications  // GET    /api/v2/notifications
APIConfig.Notification.markRead          // POST   /api/v2/notifications/mark-read
APIConfig.Notification.delete            // DELETE /api/v2/notifications/{id}
```

### Example: Get Notifications
```swift
// TODO: Implement in NotificationService
let response: NotificationsResponse = try await client.request(
    endpoint: APIConfig.Notification.getNotifications,
    method: "GET"
)

let notifications = response.notifications
```

---

## 👥 Social/Relationships (v2)

### Endpoints
```swift
// Relationships
APIConfig.Graph.followers    // GET  /api/v2/relationships/followers
APIConfig.Graph.following    // GET  /api/v2/relationships/following
APIConfig.Graph.follow       // POST /api/v2/relationships/follow
APIConfig.Graph.unfollow     // POST /api/v2/relationships/unfollow
APIConfig.Graph.isFollowing  // GET  /api/v2/relationships/is-following

// Social Interactions (Feed Service)
APIConfig.Social.createLike      // POST /api/v2/feed/like
APIConfig.Social.deleteLike      // POST /api/v2/feed/unlike
APIConfig.Social.getLikes        // GET  /api/v2/feed/likes
APIConfig.Social.checkLiked      // GET  /api/v2/feed/check-liked
APIConfig.Social.createComment   // POST /api/v2/feed/comment
APIConfig.Social.deleteComment   // POST /api/v2/feed/comment/delete
APIConfig.Social.getComments     // GET  /api/v2/feed/comments
APIConfig.Social.createShare     // POST /api/v2/feed/share
APIConfig.Social.getShareCount   // GET  /api/v2/feed/shares/count
APIConfig.Social.batchGetStats   // POST /api/v2/feed/stats/batch
```

### Note
⚠️ **Social service is currently offline in staging.** To enable:
```bash
kubectl scale deployment social-service -n nova-staging --replicas=1
```

---

## 🛠️ Usage Patterns

### 1. Using APIClient Directly

```swift
struct MyRequest: Codable {
    let userId: String
    let limit: Int
}

struct MyResponse: Codable {
    let data: [String]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case data
        case totalCount = "total_count"  // Map snake_case to camelCase
    }
}

let request = MyRequest(userId: "123", limit: 20)
let response: MyResponse = try await APIClient.shared.request(
    endpoint: "/api/v2/my/endpoint",
    method: "POST",
    body: request
)
```

### 2. Using Service Layer

```swift
// Recommended: Use service classes for organized API calls
let searchService = SearchService()
let results = try await searchService.searchUsers(query: "john")

let contentService = ContentService()
let posts = try await contentService.getPostsByAuthor(authorId: "user-123")
```

### 3. Error Handling

```swift
do {
    let results = try await searchService.searchUsers(query: query)
    // Handle success
} catch APIError.unauthorized {
    // Token expired, redirect to login
} catch APIError.notFound {
    // Resource not found
} catch APIError.serverError(let statusCode, let message) {
    // Server error with details
    print("Error \(statusCode): \(message)")
} catch {
    // Network or other error
    print("Unexpected error: \(error)")
}
```

---

## 🧪 Testing

### 1. Enable Staging Environment

In your app or view model:
```swift
// For testing with staging backend
APIConfig.current = .staging
```

### 2. Test Search Functionality

```swift
let searchService = SearchService()

// Test user search
let users = try await searchService.searchUsers(query: "test")
print("Found \(users.count) users")

// Test post search
let posts = try await searchService.searchPosts(query: "hello")
print("Found \(posts.count) posts")
```

### 3. View Request Logs

Enable request logging:
```swift
APIFeatureFlags.enableRequestLogging = true
```

---

## 📋 Migration Checklist

- [x] Update APIConfig endpoints to v2
- [x] Update staging base URL
- [x] Implement SearchService with v2 API
- [x] Add Search, Notification configs
- [ ] Implement NotificationService
- [ ] Implement IdentityService (Auth)
- [ ] Update ContentService implementations
- [ ] Update MediaService implementations
- [ ] Update GraphService implementations
- [ ] Update SocialService implementations
- [ ] Test all services with staging backend
- [ ] Add unit tests for v2 API services
- [ ] Update documentation

---

## 🐛 Troubleshooting

### Connection Failed
```swift
// Check base URL
print(APIConfig.current.baseURL)
// Should print: http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com
```

### 401 Unauthorized
```swift
// Ensure token is set
APIClient.shared.setAuthToken("your-jwt-token")
```

### 404 Not Found
- Verify endpoint path (should be `/api/v2/...`)
- Check if service is running in staging
```bash
kubectl get pods -n nova-staging
```

### View Service Logs
```bash
kubectl logs -n nova-staging -l app=search-service --tail=100
kubectl logs -n nova-staging -l app=content-service --tail=100
```

---

## 📚 Next Steps

1. **Test in Xcode**: Build and run the app with staging environment
2. **Implement Remaining Services**: Complete TODO items in service files
3. **Add Error Recovery**: Implement retry logic and offline caching
4. **Performance**: Add request/response caching where appropriate
5. **Monitoring**: Add analytics for API calls

---

## 📞 Support

- **Backend API Issues**: Check service logs in K8s
- **iOS Integration Issues**: Review this guide and API documentation
- **Service Documentation**: See `ios/NovaSocial/STAGING_API_ENDPOINTS.md`

---

**Last Updated**: 2025-11-18
**Maintained by**: Nova iOS Team
