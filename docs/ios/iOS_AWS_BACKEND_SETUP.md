# iOS AWS Backend Integration Setup Guide

## Overview

The iOS application has been updated to connect with the real AWS backend services running on Kubernetes. This guide explains the changes made and how to test them.

## Changes Made

### 1. API Configuration (`APIConfig.swift`)

**Added new environment**: `stagingAWS`
- **Base URL**: `http://host.docker.internal:8081` (simulator) or `http://localhost:8081` (device)
- **Purpose**: Connects to AWS-hosted backend via local port-forward
- **Default in DEBUG builds**: Now defaults to `.stagingAWS` instead of `.stagingProxy`

```swift
case .stagingAWS:
    // AWS backend via port-forward
    #if targetEnvironment(simulator)
    return "http://host.docker.internal:8081"
    #else
    return "http://localhost:8081"
    #endif
```

**Environment variable support**: Can set via `API_ENV=aws` or `API_ENV=staging_aws`

### 2. PostService Updates (`PostService.swift`)

**Fixed request parameters** to match backend API:
- Changed from `imageUrl` → `imageKey` (S3 object key)
- Added `contentType` parameter (MIME type: "image/jpeg", "image/png", etc.)
- Both parameters are optional but must be provided together

**Updated function signature**:
```swift
func createPost(
    caption: String,
    imageKey: String? = nil,
    contentType: String? = nil
) async throws -> Post
```

**Validation**:
- Ensures caption is not empty and within 500 character limit
- If imageKey is provided, contentType must also be provided (and vice versa)
- Returns proper error messages for validation failures

### 3. FeedService Updates (`FeedService.swift`)

**Intelligent port switching**:
- Detects when using AWS staging with port 8081 (content-service)
- Automatically switches to port 8083 for feed endpoints (user-service)
- Creates custom HTTPClient with correct base URL

**Implementation**:
```swift
init(httpClient: HTTPClient = HTTPClient(), cache: CacheManager = CacheManager()) {
    let actualHTTPClient: HTTPClient
    if APIConfig.environment == .stagingAWS {
        let baseURLString = APIConfig.baseURL.absoluteString
        if let correctedURL = URL(string: baseURLString.replacingOccurrences(of: ":8081", with: ":8083")) {
            actualHTTPClient = HTTPClient(baseURL: correctedURL, session: APIConfig.session)
        } else {
            actualHTTPClient = httpClient
        }
    } else {
        actualHTTPClient = httpClient
    }
    self.httpClient = actualHTTPClient
    self.cache = cache
}
```

**Why**: The Kubernetes Ingress routes:
- `/api/v1/posts` → content-service:8081
- `/api/v1/feed` → user-service:8083

## Backend Service Architecture

The AWS backend is running on EKS (Kubernetes) in ap-northeast-1 region:

- ### Services Running:
- **content-service** (port 8081) - Handles posts creation and management
- **feed-service** (port 8084) - Personalized feed & ranking (aggregates other services)
- **identity-service** (port 8083 gRPC) - Auth/JWT (via GraphQL gateway)
- **media-service** (port 8082) - Handles media uploads
- **realtime-chat-service** (port 8080 HTTP / 9000 gRPC) - Messaging + WebSocket
- **PostgreSQL** (port 5432) - Primary database
- **Redis** (port 6379) - Cache/session store
- **ClickHouse** (port 8123/9000) - Analytics database
- **Kafka** - Event streaming

### Kubernetes Configuration:
- Cluster: EKS in ap-northeast-1
- Namespace: nova
- All services are ClusterIP (internal only)
- NGINX Ingress configured but external IP not yet provisioned

## Setup Instructions

### Step 1: Enable Port Forwarding

You need to establish port-forwards to access the services from your iOS simulator/device:

```bash
# Terminal 1: Set up all port-forwards
./scripts/ios-aws-port-forward.sh
```

Or manually:
```bash
# Terminal 1: Content Service (Posts)
kubectl port-forward -n nova svc/content-service 8081:8081

# Terminal 2: GraphQL Gateway (Feed/Profiles)
kubectl port-forward -n nova svc/graphql-gateway 8080:8080

# Terminal 3: Media Service (Optional, for image uploads)
kubectl port-forward -n nova svc/media-service 8082:8082

# Terminal 4: Messaging Service (Optional, for messaging)
kubectl port-forward -n nova svc/messaging-service 8084:8084
```

### Step 2: Verify Port-Forward Connectivity

```bash
# Test content-service
curl -H "Authorization: Bearer test-token" http://localhost:8081/health

# Test GraphQL gateway (feeds/profiles)
curl -H "Authorization: Bearer test-token" http://localhost:8080/health
```

### Step 3: Run iOS App

```bash
# In Xcode or via command line
xcodebuild -workspace ios/NovaSocial/NovaSocial.xcworkspace \
    -scheme NovaSocial \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Testing the Integration

### Test 1: View Feed (Real Data)

1. Launch the iOS app
2. Navigate to **Home** tab (first tab)
3. Should see the feed loading from `http://localhost:8083/api/v1/feed`
4. If no posts exist in database yet, will fallback to mock data

**What's happening**:
- FeedService calls user-service via port 8083
- Fetches real posts from PostgreSQL database
- Falls back to mock data if request fails

### Test 2: Create a Post (Write to Database)

1. Navigate to **Create** tab (fourth tab, pencil icon)
2. Enter some text (up to 500 characters)
3. Tap "Publish Post" button
4. Should see success response or error message

**What's happening**:
- PostService sends POST to `http://localhost:8081/api/v1/posts`
- Backend validates caption and stores in PostgreSQL
- Returns new Post object with ID and timestamp
- If successful, clears local feed cache for fresh data

**Example successful POST request**:
```json
POST http://localhost:8081/api/v1/posts
Authorization: Bearer test-token
Content-Type: application/json

{
  "caption": "Hello from iOS!",
  "image_key": null,
  "content_type": null
}
```

**Response**:
```json
{
  "id": "post_uuid",
  "author": { "id": "user_uuid", "username": "..." },
  "caption": "Hello from iOS!",
  "image_url": null,
  "like_count": 0,
  "comment_count": 0,
  "is_liked": false,
  "created_at": "2024-11-03T02:30:00Z"
}
```

### Test 3: Search Users (User Service)

1. Navigate to **Explore** tab (second tab, magnifying glass)
2. Type a username to search
3. Should see real users from database or mock data on failure

**What's happening**:
- SearchService calls user-service on port 8083
- Queries PostgreSQL for matching users
- Returns list of users with followers count

### Test 4: View Messages (Messaging Service)

1. Navigate to **Messages** tab (third tab, chat bubble)
2. Should see list of conversations
3. Tap on conversation to view messages (if implemented)

**What's happening**:
- MessagingService calls messaging-service on port 8084
- Fetches conversations and messages from PostgreSQL

## Endpoint Mapping

| Feature | Endpoint | Service | Port |
|---------|----------|---------|------|
| Create Post | POST /api/v1/posts | content-service | 8081 |
| Feed | GET /api/v1/feed | user-service | 8083 |
| Search Users | GET /api/v1/users/search | user-service | 8083 |
| Get Conversations | GET /api/v1/conversations | messaging-service | 8084 |
| Send Message | POST /api/v1/conversations/{id}/messages | messaging-service | 8084 |
| Get Notifications | GET /api/v1/notifications | user-service | 8083 |

## Troubleshooting

### Issue: "Network error. Please try again"

**Causes**:
1. Port-forwards not running
2. Services not accessible from your machine
3. Firewall blocking localhost connections

**Solution**:
```bash
# Verify port-forwards are running
lsof -i :8081
lsof -i :8083

# Check service availability
kubectl get pods -n nova -l component=content-service
kubectl get pods -n nova -l component=user-service
```

### Issue: "Unauthorized" or 401 error

**Cause**: Missing or invalid authentication token

**Solution**:
- The app uses `Bearer test-token` by default (from APIConfig)
- For production, you need a real JWT token from auth-service
- Get token via: `POST /api/v1/auth/login` with credentials

### Issue: App still shows mock data instead of real data

**Possible reasons**:
1. Port-forward on correct port but service not responding
2. Firewall blocking connections to port
3. API endpoint not in database yet

**Debugging**:
```bash
# Test the actual endpoint
curl -H "Authorization: Bearer test-token" \
  http://localhost:8083/api/v1/feed \
  -v

# Check service logs
kubectl logs -n nova -l component=user-service -f

# Check if services are healthy
kubectl get pods -n nova
```

## Performance Notes

- **First load**: May take 2-3 seconds to establish port-forward and connect
- **Caching**: All responses are cached locally to reduce network calls
- **Fallback**: If any request fails, app gracefully falls back to mock data
- **Retry logic**: HTTPClient retries failed requests up to 3 times with exponential backoff

## Future Improvements

1. **Image Upload Support**: Implement image upload to S3 via media-service
2. **Authentication Flow**: Add proper login/logout with JWT tokens
3. **Real-time Updates**: Use WebSocket for messaging and notifications
4. **Pagination**: Implement cursor-based pagination for feed and search
5. **External IP**: Configure AWS API Gateway with external IP/DNS when available

## Important Files Modified

- `APIConfig.swift` - Added stagingAWS environment
- `PostService.swift` - Updated to use image_key and content_type
- `FeedService.swift` - Added intelligent port switching
- `ContentView.swift` - Updated PostService call parameters
- `ios-aws-port-forward.sh` - New script for port-forward setup

## Next Steps

1. Run the port-forward script to enable AWS backend connectivity
2. Launch the iOS app and test creating a post
3. Verify the post appears in the feed
4. Check backend logs for any errors
5. Add more features (image uploads, messaging, etc.)
