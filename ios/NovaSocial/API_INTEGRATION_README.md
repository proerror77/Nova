# iOS API Integration Guide

## Overview

This document explains how the iOS app integrates with the backend gRPC services through the HTTP/JSON API Gateway.

## Architecture

```
iOS App (SwiftUI)
    ↓
ViewModel Layer (UserProfileViewModel)
    ↓
Service Layer (GraphService, SocialService, ContentService, MediaService)
    ↓
API Client (APIClient)
    ↓
HTTP/JSON Gateway
    ↓
Backend gRPC Services (graph-service, social-service, content-service, media-service)
```

## File Structure

```
ios/NovaSocial/
├── Models/
│   ├── UserModels.swift         # UserProfile, UserSettings, UserRelationship
│   └── ContentModels.swift      # Post, Comment, PostLike
├── Services/
│   └── APIClient.swift          # API communication layer
├── ViewModels/
│   └── UserProfileViewModel.swift  # State management for AccountView
├── Config/
│   └── APIConfig.swift          # API endpoints and environment config
└── Views/
    └── AccountView.swift        # Updated to use ViewModel
```

## API Configuration

### Environments

The app supports three environments:

```swift
enum APIEnvironment {
    case development    // localhost:8080
    case staging       // staging-api.nova.social
    case production    // api.nova.social
}
```

Default environment is set based on build configuration:
- DEBUG builds → development
- RELEASE builds → production

### Endpoints

All API endpoints are defined in `APIConfig.swift`:

```swift
// Graph Service (Follow/Follower relationships)
APIConfig.Graph.followers       // POST /api/v1/graph/followers
APIConfig.Graph.following       // POST /api/v1/graph/following
APIConfig.Graph.follow          // POST /api/v1/graph/follow
APIConfig.Graph.unfollow        // POST /api/v1/graph/unfollow

// Social Service (Likes, Comments, Shares)
APIConfig.Social.createLike     // POST /api/v1/social/like
APIConfig.Social.deleteLike     // POST /api/v1/social/unlike
APIConfig.Social.getLikes       // POST /api/v1/social/likes
APIConfig.Social.createComment  // POST /api/v1/social/comment
APIConfig.Social.getComments    // POST /api/v1/social/comments

// Content Service (Posts, Bookmarks)
APIConfig.Content.postsByAuthor // POST /api/v1/content/posts/author
APIConfig.Content.bookmarks     // POST /api/v1/content/bookmarks
APIConfig.Content.createPost    // POST /api/v1/content/post/create

// Media Service (Uploads)
APIConfig.Media.uploadStart     // POST /api/v1/media/upload/start
```

## Data Models

All data models match the backend proto definitions:

### UserProfile (user_service.proto)

```swift
struct UserProfile: Codable {
    let id: String
    let username: String
    let email: String?
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let coverUrl: String?
    let location: String?
    let followerCount: Int
    let followingCount: Int
    let postCount: Int
    // ... timestamps
}
```

### Post (content_service.proto)

```swift
struct Post: Codable {
    let id: String
    let creatorId: String
    let content: String
    let createdAt: Int64
    let updatedAt: Int64
}
```

## Usage Examples

### Loading Followers/Following

```swift
class UserProfileViewModel: ObservableObject {
    @Published var followerIds: [String] = []
    @Published var followingIds: [String] = []

    func loadFollowers(userId: String) async {
        do {
            let (userIds, totalCount, hasMore) = try await graphService.getFollowers(userId: userId)
            followerIds = userIds
        } catch {
            // Handle error
        }
    }

    func loadFollowing(userId: String) async {
        do {
            let (userIds, totalCount, hasMore) = try await graphService.getFollowing(userId: userId)
            followingIds = userIds
        } catch {
            // Handle error
        }
    }
}
```

### Liking/Unliking Posts

```swift
func likePost(postId: String) async {
    do {
        try await socialService.createLike(postId: postId, userId: currentUserId)
        // Reload content to reflect the change
    } catch {
        // Handle error
    }
}

func unlikePost(postId: String) async {
    do {
        try await socialService.deleteLike(postId: postId, userId: currentUserId)
        // Reload content to reflect the change
    } catch {
        // Handle error
    }
}
```

### Loading Posts by Tab

```swift
func loadContent(for tab: ContentTab) async {
    switch tab {
    case .posts:
        let response = try await contentService.getPostsByAuthor(authorId: userId)
        posts = response.posts

    case .saved:
        let response = try await contentService.getUserBookmarks(userId: userId)
        savedPosts = response.posts

    case .liked:
        // TODO: Need API endpoint for fetching posts liked by a user
        // Current SocialService only provides users who liked a specific post
        likedPosts = []
    }
}
```

## Error Handling

All API errors are wrapped in `APIError`:

```swift
enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(statusCode: Int, message: String)
    case unauthorized
    case notFound
}
```

ViewModel automatically handles errors and exposes them:

```swift
@Published var errorMessage: String?
```

Display errors using alerts:

```swift
.alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
    Button("OK") {
        viewModel.errorMessage = nil
    }
} message: {
    Text(viewModel.errorMessage ?? "")
}
```

## Backend Proto Definitions

### Graph Service (backend/proto/services/graph_service.proto)

Manages follow/follower relationships as directed graph edges:
- `CreateFollow` - Follow a user (create edge)
- `DeleteFollow` - Unfollow a user (delete edge)
- `GetFollowers` - Get user's followers (returns user IDs)
- `GetFollowing` - Get users this user follows (returns user IDs)
- `IsFollowing` - Check if a user follows another

### Social Service (backend/proto/services/social_service.proto)

Manages social interactions (likes, comments, shares):
- `CreateLike` - Like a post
- `DeleteLike` - Unlike a post
- `GetPostLikes` - Get users who liked a post (returns user IDs)
- `CheckUserLiked` - Check if user liked a specific post
- `CreateComment` - Create a comment on a post
- `DeleteComment` - Delete a comment
- `GetComments` - Get comments for a post
- `CreateShare` - Share a post
- `GetShareCount` - Get share count for a post
- `BatchGetPostStats` - Get stats (likes, comments, shares) for multiple posts

### Content Service (backend/proto/services/content_service.proto)

Manages posts and bookmarks:
- `GetPost` - Get a single post by ID
- `CreatePost` - Create a new post
- `UpdatePost` - Update an existing post
- `DeletePost` - Delete a post
- `GetPostsByAuthor` - Get all posts by a specific author
- `GetUserBookmarks` - Get user's bookmarked posts
- `CheckPostExists` - Check if a post exists

### Media Service (backend/proto/services/media_service.proto)

Manages media uploads (images, videos, reels):
- `StartUpload` - Initialize file upload
- `UpdateUploadProgress` - Update upload progress
- `CompleteUpload` - Finalize upload
- `CreateVideo` - Create a video
- `GetVideo` - Get video details
- `CreateReel` - Create a reel
- `ListReels` - List reels

## Testing

### Mock Data

Enable mock data for testing without backend:

```swift
APIFeatureFlags.enableMockData = true
```

### Request Logging

Enable detailed request logging:

```swift
APIFeatureFlags.enableRequestLogging = true
```

### Preview Data

Use ViewModel preview helper:

```swift
#Preview {
    let viewModel = UserProfileViewModel.preview()
    AccountView(currentPage: .constant(.account))
        .environmentObject(viewModel)
}
```

## TODO

- [ ] Implement authentication service and token management
- [ ] Implement user profile service (separate from GraphService)
  - User profile fetching
  - Profile updates (avatar, bio, etc.)
  - User profile stats aggregation
- [ ] Add API for fetching posts liked by a user
  - Currently SocialService only provides users who liked a post
  - Need reverse lookup: given user ID, get posts they liked
- [ ] Add offline caching and retry logic
- [ ] Implement pagination for posts
- [ ] Add image caching for avatars and post images
- [ ] Implement WebSocket for real-time updates
- [ ] Add analytics tracking
- [ ] Implement proper error recovery strategies
- [ ] Add unit tests for API service layer
- [ ] Add integration tests with mock server

## Backend Integration Checklist

### API Gateway

Ensure the API Gateway is configured to route requests:

```
/api/v1/graph/*    → graph-service:8080
/api/v1/content/*  → content-service:8081
/api/v1/media/*    → media-service:8082
/api/v1/social/*   → social-service:8083
/api/v1/feed/*     → feed-service:8084
```

### Authentication

The app sends JWT tokens in the Authorization header:

```
Authorization: Bearer <token>
```

Ensure backend services validate these tokens.

### Response Format

All responses should match the proto message structure serialized to JSON:

Example responses:

**GraphService GetFollowers:**
```json
{
  "user_ids": ["user-uuid-1", "user-uuid-2"],
  "total_count": 3021,
  "has_more": true
}
```

**ContentService GetPostsByAuthor:**
```json
{
  "posts": [
    {
      "id": "post-uuid",
      "creator_id": "user-uuid",
      "content": "Post content...",
      "created_at": 1234567890,
      "updated_at": 1234567890
    }
  ],
  "total_count": 245
}
```

**SocialService CreateLike:**
```json
{
  "success": true
}
```

## Troubleshooting

### Cannot connect to localhost

- Ensure backend services are running
- Check GraphQL Gateway is accessible at port 8080
- Verify firewall settings

### Data not loading

- Check request logging in Xcode console
- Verify API endpoints match backend routes
- Check response format matches expected JSON structure

### Authentication errors

- Ensure valid JWT token is set: `APIClient.shared.setAuthToken(token)`
- Check token expiration
- Verify backend authentication middleware

## Support

For backend API questions, refer to:
- `backend/proto/services/*.proto` - gRPC service definitions
- Backend service README files
- GraphQL Gateway documentation
