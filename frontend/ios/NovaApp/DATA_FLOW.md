# Nova iOS - Data Flow Architecture

## Overview
This document describes how data flows through the app from user actions to backend API calls and back.

## Auth Flow

### Sign In Flow
```
User taps "Sign In"
  ↓
SignInView
  ↓
AuthService.signIn(email, password)
  ↓
AuthRepository.signIn()
  ↓
APIClient.request(Endpoints.signIn)
  ↓
Backend: POST /auth/signin
  ↓
Response: { access_token, refresh_token, user }
  ↓
KeychainManager.saveAccessToken()
  ↓
AuthService.isAuthenticated = true
  ↓
App.swift switches to MainTabView
```

### Apple Sign In Flow
```
User taps "Sign in with Apple"
  ↓
AppleSignInGateView
  ↓
SignInWithAppleButton callback
  ↓
AuthService.signInWithApple(authorization)
  ↓
Extract identity token from ASAuthorization
  ↓
AuthRepository.signInWithApple()
  ↓
Backend: POST /auth/apple
  ↓
Same flow as email sign in
```

### Token Refresh Flow
```
APIClient receives 401 response
  ↓
APIClient.refreshTokenIfNeeded()
  ↓
AuthService.refreshToken()
  ↓
Get refresh_token from Keychain
  ↓
Backend: POST /auth/refresh
  ↓
Update access_token + refresh_token in Keychain
  ↓
Retry original request
```

---

## Feed Flow

### Initial Feed Load
```
User opens app
  ↓
FeedView.onAppear
  ↓
FeedViewModel.loadInitial()
  ↓
Check CacheManager.getCachedFeed()
  ↓
If cached (< 30s old):
  └→ Return cached data immediately
  └→ Background refresh via refreshFeed()

If not cached:
  └→ FeedRepository.fetchFeed(page: 0, limit: 20)
  └→ Backend: GET /feed?page=0&limit=20
  └→ Response: { posts: [...], has_more: true }
  └→ CacheManager.cacheFeed(result)
  └→ FeedViewModel.posts = result.posts
  └→ UI updates via @Published
```

### Pagination (Load More)
```
User scrolls to bottom
  ↓
PostCard.onAppear (last post)
  ↓
FeedViewModel.loadMore()
  ↓
Check: !isLoadingMore && hasMore
  ↓
FeedRepository.fetchFeed(page: currentPage + 1)
  ↓
Backend: GET /feed?page=1&limit=20
  ↓
Response: { posts: [...], has_more: false }
  ↓
FeedViewModel.posts.append(contentsOf: newPosts)
  ↓
UI updates (new posts rendered)
```

### Pull-to-Refresh
```
User pulls down on FeedView
  ↓
SwiftUI .refreshable modifier triggered
  ↓
FeedViewModel.refresh()
  ↓
Same as loadInitial() but clears cache first
```

---

## Like/Unlike Flow

### Like Post (Optimistic Update)
```
User taps heart icon
  ↓
PostCard.onLike callback
  ↓
FeedViewModel.toggleLike(postId)
  ↓
Optimistic update:
  └→ post.isLiked = true
  └→ post.likeCount += 1
  └→ UI updates immediately

Background API call:
  └→ FeedRepository.likePost(postId)
  └→ ActionQueue.enqueue(LikeAction)
  └→ Backend: POST /posts/:id/like (idempotency-key)

If success:
  └→ ActionQueue.markCompleted()

If error:
  └→ Revert optimistic update
  └→ ActionQueue.markFailed() (retry up to 3 times)
```

### Offline Like
```
User likes post (offline)
  ↓
Optimistic update (same as above)
  ↓
FeedRepository.likePost() fails (network error)
  ↓
ActionQueue keeps action in pending state
  ↓
App regains connectivity
  ↓
ActionQueue.processQueue()
  ↓
Retry POST /posts/:id/like
  ↓
Success → ActionQueue.markCompleted()
```

---

## Post Detail Flow

### View Post
```
User taps PostCard
  ↓
NavigationCoordinator.navigate(to: .postDetail(postId))
  ↓
PostDetailView appears
  ↓
PostDetailViewModel.loadPost(postId)
  ↓
Backend: GET /posts/:id
  ↓
Response: { id, author, image_url, caption, ... }
  ↓
PostDetailViewModel.post = response
  ↓
UI renders post details
```

### View Comments
```
User taps comment icon
  ↓
NavigationCoordinator.navigate(to: .comments(postId))
  ↓
CommentsSheet appears
  ↓
CommentsViewModel.loadComments(postId)
  ↓
Backend: GET /posts/:id/comments?page=0&limit=20
  ↓
Response: { comments: [...], has_more: false }
  ↓
CommentsViewModel.comments = response.comments
  ↓
UI renders comment list
```

### Add Comment
```
User types comment and taps "Post"
  ↓
CommentsViewModel.createComment(text)
  ↓
Optimistic update:
  └→ Insert new comment at top of list

Background API call:
  └→ Backend: POST /posts/:id/comments (idempotency-key)
  └→ Request: { text: "..." }
  └→ Response: { id, created_at }
  └→ Update local comment with server-generated ID
```

---

## Upload Flow

### Photo Selection
```
User taps "Create" tab
  ↓
CreateEntryView appears
  ↓
User taps "Photo Library"
  ↓
PhotoPickerView (native PHPicker)
  ↓
User selects photo
  ↓
Convert to Data (JPEG 85% quality)
  ↓
Resize if > 2048x2048
  ↓
Navigate to ImageEditView(imageData)
```

### Image Editing
```
ImageEditView
  ↓
User applies crop/filters
  ↓
User taps "Next"
  ↓
Navigate to PublishFormView(editedImageData)
```

### Publish Post
```
PublishFormView
  ↓
User enters caption
  ↓
User taps "Publish"
  ↓
CreateViewModel.publishPost(imageData, caption)
  ↓
Step 1: Get presigned URL
  └→ Backend: POST /upload/presign
  └→ Request: { filename: "photo.jpg", content_type: "image/jpeg" }
  └→ Response: { upload_url, file_key, expires_at }

Step 2: Upload to S3
  └→ PUT {upload_url} (direct upload, not via API)
  └→ Body: [binary image data]
  └→ Response: 200 OK

Step 3: Create post record
  └→ Backend: POST /posts (idempotency-key)
  └→ Request: { image_key: file_key, caption: "..." }
  └→ Response: { id, image_url, created_at }

Track analytics:
  └→ AnalyticsTracker.track(.uploadSuccess(postId, duration))

Navigate back to Feed
  └→ Refresh feed to show new post
```

### Upload Failure Handling
```
If presigned URL fails:
  └→ Show error "Failed to prepare upload"
  └→ Retry button available

If S3 upload fails:
  └→ Add to UploadQueue (retry later)
  └→ Show "Uploading..." in UploadQueueView
  └→ Retry when network available

If POST /posts fails:
  └→ Add to ActionQueue
  └→ Retry with same idempotency-key
```

---

## Search Flow

### User Search
```
User types in SearchView
  ↓
SearchViewModel.searchUsers(query)
  ↓
Throttle: Wait 300ms after last keystroke
  ↓
Backend: GET /search/users?q={query}&page=0&limit=20
  ↓
Response: { users: [...], has_more: false }
  ↓
SearchViewModel.results = response.users
  ↓
UI updates with results
```

### Search Result Tap
```
User taps on user in search results
  ↓
NavigationCoordinator.navigate(to: .profile(userId))
  ↓
UserProfileView appears
  ↓
ProfileViewModel.loadProfile(userId)
  ↓
Backend: GET /users/:id
  ↓
Response: { id, username, avatar_url, bio, ... }
  ↓
ProfileViewModel.user = response
  ↓
UI renders profile

Analytics:
  └→ AnalyticsTracker.track(.searchResultClick(userId, query))
```

---

## Profile Flow

### View Own Profile
```
User taps "Profile" tab
  ↓
MyProfileView appears
  ↓
ProfileViewModel.loadProfile(userId: currentUser.id)
  ↓
Backend: GET /users/:id
  ↓
Response: User + posts grid
  ↓
UI renders profile
```

### Edit Profile
```
User taps "Edit Profile"
  ↓
EditProfileView appears
  ↓
User updates display name, bio, avatar
  ↓
User taps "Save"
  ↓
EditProfileViewModel.updateProfile()
  ↓
Compress avatar (if changed)
  ↓
Backend: PATCH /users/:id (multipart/form-data)
  ↓
Request: { display_name, bio, avatar: [binary] }
  ↓
Response: Updated user object
  ↓
AuthService.currentUser = updatedUser
  ↓
Navigate back to MyProfileView
```

---

## Notification Flow

### Fetch Notifications
```
User taps "Notifications" tab
  ↓
NotificationsView appears
  ↓
NotificationsViewModel.loadNotifications()
  ↓
Backend: GET /notifications?page=0&limit=20
  ↓
Response: { notifications: [...], has_more: false }
  ↓
NotificationsViewModel.notifications = response
  ↓
UI renders notification list
```

### Notification Tap
```
User taps notification
  ↓
Parse notification type:
  ├→ "like" → navigate to PostDetailView
  ├→ "comment" → navigate to CommentsSheet
  └→ "follow" → navigate to UserProfileView

Analytics:
  └→ AnalyticsTracker.track(.notificationOpen(notificationId))
```

---

## Analytics Flow

### Event Tracking
```
User performs action (e.g., taps post)
  ↓
AnalyticsTracker.track(.postTap(postId))
  ↓
Create TrackedEvent:
  └→ name: "post_tap"
  └→ category: "feed"
  └→ parameters: { post_id: "..." }
  └→ timestamp: Date()
  └→ device_id, user_id, platform, app_version

Add to eventBuffer (in-memory)

If buffer.count >= 50 or timer fires (30s):
  ↓
AnalyticsTracker.flush()
  ↓
ClickHouseClient.sendBatch(events)
  ↓
Backend: POST /analytics/events
  ↓
Request: [{ event1 }, { event2 }, ...]
  ↓
Response: 200 OK
  ↓
Clear eventBuffer
```

### App Lifecycle Events
```
App enters background:
  └→ AnalyticsTracker.track(.appBackground)
  └→ AnalyticsTracker.flush() (immediate)

App enters foreground:
  └→ AnalyticsTracker.track(.appForeground)
```

---

## Error Handling

### Network Errors
All API calls go through this flow:
```
APIClient.request()
  ↓
Try request (up to 3 times)

If 401 Unauthorized:
  └→ refreshTokenIfNeeded()
  └→ Retry request

If 429 Rate Limited:
  └→ Wait (exponential backoff)
  └→ Retry request

If 5xx Server Error:
  └→ Wait (exponential backoff)
  └→ Retry request

If 4xx Client Error (except 401):
  └→ Don't retry
  └→ Show error to user

If network error:
  └→ Add to ActionQueue (for mutating operations)
  └→ Show "No connection" error
```

### Offline Queue Processing
```
ActionQueue.processQueue() runs on:
  1. App foreground
  2. Network connection restored
  3. Timer (every 60s)

For each pending action:
  └→ Retry API call
  └→ If success: markCompleted()
  └→ If error && retryCount < 3: markFailed() (retry later)
  └→ If error && retryCount >= 3: Remove (give up)
```
