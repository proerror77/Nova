# iOS AWS Backend - Quick Start

## TL;DR - Get Running in 5 Minutes

### Step 1: Open 4 Terminal Tabs and Run Port-Forwards

```bash
# Tab 1: Content Service (Posts)
kubectl port-forward -n nova svc/content-service 8081:8081

# Tab 2: User Service (Feed, Users)
kubectl port-forward -n nova svc/user-service 8083:8083

# Tab 3: Media Service (Images) - Optional
kubectl port-forward -n nova svc/media-service 8082:8082

# Tab 4: Messaging Service - Optional
kubectl port-forward -n nova svc/messaging-service 8084:8084
```

### Step 2: Run iOS App in Xcode

```bash
# In Xcode: Select NovaSocial scheme and run on simulator
# Or command line:
open ios/NovaSocial/NovaSocial.xcworkspace
```

### Step 3: Test It Out

1. **Create a Post**: Go to Create tab, type text, tap Publish
2. **View Feed**: Go to Home tab, should show your post + mock data
3. **Search Users**: Go to Explore tab, search for "john" or "jane"
4. **View Messages**: Go to Messages tab

## What Changed

| Component | Change | Why |
|-----------|--------|-----|
| APIConfig | Added `.stagingAWS` environment | Point to AWS backend via localhost:8081 |
| PostService | Changed `imageUrl` → `imageKey` + `contentType` | Match backend API spec |
| FeedService | Auto-switch port 8081 → 8080 | Feed/Profiles via GraphQL gateway |
| ContentView | Updated PostService call | Use new image_key parameter |

## Architecture Overview

```
iOS App (Simulator)
    ↓
host.docker.internal:8081 (APIConfig stagingAWS)
    ↓
Port-Forward: kubectl port-forward -n nova svc/content-service 8081:8081
    ↓
EKS Cluster (AWS ap-northeast-1)
    ├── content-service:8081 ← Posts endpoints
    ├── graphql-gateway:8080 ← Feeds & users (aggregates identity/feed/social)
    ├── media-service:8082 ← Image upload
    ├── realtime-chat-service:8080 ← Chat/WebSocket
    └── PostgreSQL:5432 ← Data storage
```

## Key Points to Remember

1. **Port-forwards are REQUIRED** - Without them, app falls back to mock data
2. **Two different ports**: content-service (8081) and GraphQL gateway (8080)
3. **Default auth**: Uses `Bearer test-token` from APIConfig
4. **Fallback to mock**: If any request fails, gracefully shows mock data instead of error
5. **No database data yet**: Posts database may be empty, so you'll see mock data initially

## Verify It's Working

```bash
# Test the endpoints directly
curl -H "Authorization: Bearer test-token" http://localhost:8081/health
curl -H "Authorization: Bearer test-token" http://localhost:8080/graphql

# Check port-forwards are running
lsof -i :8081
lsof -i :8080
```

## Common Issues

| Issue | Solution |
|-------|----------|
| "Network error" | Check port-forwards are running: `lsof -i :8081` |
| Still shows only mock data | Verify backend service is running: `kubectl get pods -n nova` |
| Cannot connect to host.docker.internal | Use `localhost` instead on physical device |
| Xcode build fails | Make sure to open `.xcworkspace` not `.xcodeproj` |

## File Locations

- 📄 Full setup guide: `iOS_AWS_BACKEND_SETUP.md`
- 🔧 Port-forward script: `scripts/ios-aws-port-forward.sh`
- 🌐 API Config: `ios/NovaSocial/NovaSocialPackage/Sources/NovaSocialFeature/Networking/APIConfig.swift`
- 📝 Post Service: `ios/NovaSocial/NovaSocialPackage/Sources/NovaSocialFeature/Services/PostService.swift`
- 📰 Feed Service: `ios/NovaSocial/NovaSocialPackage/Sources/NovaSocialFeature/Services/FeedService.swift`

## Next Steps

1. **Test creating posts** - Verify they appear in real database
2. **Check backend logs** - `kubectl logs -n nova -l component=content-service -f`
3. **Add image upload** - Implement S3 integration via media-service
4. **Proper authentication** - Replace test token with real JWT from auth-service
5. **Configure external endpoint** - AWS API Gateway with public IP/DNS

## API Endpoints Reference

```
GET /api/v1/feed?limit=20&offset=0          # Get feed posts
POST /api/v1/posts                          # Create post
POST /api/v1/posts/{id}/like                # Like post
POST /api/v1/posts/{id}/unlike              # Unlike post
DELETE /api/v1/posts/{id}                   # Delete post

GET /api/v1/users/search?q=username         # Search users
GET /api/v1/users/{id}                      # Get user profile
POST /api/v1/users/{id}/follow              # Follow user
POST /api/v1/users/{id}/unfollow            # Unfollow user

GET /api/v1/conversations                   # List conversations
POST /api/v1/conversations                  # Create conversation
GET /api/v1/conversations/{id}/messages     # Get messages
POST /api/v1/conversations/{id}/messages    # Send message

GET /api/v1/notifications                   # Get notifications
POST /api/v1/notifications/{id}/read        # Mark as read
```

---

**Questions?** Check the full setup guide at `iOS_AWS_BACKEND_SETUP.md`
