# iOS Integration Gaps - Quick Reference

## Critical Path Blockers

### 1. Development Configuration Issue
**File:** `ios/NovaSocialApp/Network/Utils/AppConfig.swift:21`

**Current (Broken):**
```swift
case .development:
    return URL(string: "http://192.168.31.154:8001")!
```

**Impact:** Only works on specific network. Developers on different networks cannot run the app.

**Fix Needed:**
```swift
case .development:
    #if DEBUG
    // Support environment variable override
    if let ip = ProcessInfo.processInfo.environment["NOVA_DEV_IP"] {
        return URL(string: "http://\(ip):8001")!
    }
    // Try reading from Info.plist
    if let ip = Bundle.main.infoDictionary?["NOVA_DEV_IP"] as? String {
        return URL(string: "http://\(ip):8001")!
    }
    // Default to localhost
    return URL(string: "http://localhost:8001")!
    #else
    return URL(string: "https://api.nova.social")!
    #endif
```

---

### 2. Missing Upload URL Endpoint
**File:** `ios/NovaSocialApp/Network/Repositories/PostRepository.swift:174`

**Current:**
```swift
private func requestUploadURL(contentType: String) async throws -> UploadURLResponse {
    let request = UploadURLRequest(contentType: contentType)
    let endpoint = APIEndpoint(
        path: "/posts/upload-url",  // ← What's the actual path?
        method: .post,
        body: request
    )
    return try await interceptor.executeWithRetry(endpoint)
}
```

**Problem:** Post creation is called but the upload-url endpoint path is unclear.

**What's needed from backend:**
- Confirm endpoint path: `/posts/upload-url` or `/api/v1/posts/upload-url`?
- Return format: `{"upload_url": "...", "file_key": "..."}`
- Supports what content types? (image/jpeg, image/png, video/mp4, etc.)

---

## Feature Gaps by Priority

### Priority 1: Video Upload for Posts
**Affected:** Post creation (currently image-only)

**Missing Implementation:**
1. Video selection UI (already have image picker)
2. Video repository method:
```swift
func uploadVideo(_ video: AVAsset, caption: String?) async throws -> Post {
    // 1. Compress video (VideoManager exists)
    let compressedURL = try await VideoManager.shared.compressVideo(from: videoURL)
    
    // 2. Get upload URL for video
    let uploadInfo = try await requestUploadURL(contentType: "video/mp4")
    
    // 3. Upload to S3 with progress tracking
    // ← Currently missing: progress callback, multipart upload
    
    // 4. Create post record with video_ids
    // ← Currently only supports image_ids
}
```

3. Progress tracking:
```swift
// Need to add to PostRepository
func uploadVideoWithProgress(
    _ data: Data,
    to uploadURL: String,
    progress: @escaping (Double) -> Void
) async throws
```

### Priority 2: Real-time Message Delivery & Offline Queue
**Affected:** Messaging (ChatViewModel + ChatSocket)

**Current Behavior:**
- Connect to WebSocket
- Receive messages via socket
- If send fails, show error and give up
- No retry mechanism
- No offline queue

**Missing:**
```swift
// Add to ChatViewModel
class OfflineMessageQueue {
    private var queue: [PendingMessage] = []
    private var isOnline = true
    
    func queueMessage(_ message: String) throws {
        let pending = PendingMessage(
            id: UUID(),
            conversationId: conversationId,
            peerUserId: peerUserId,
            content: message,
            timestamp: Date(),
            retryCount: 0
        )
        queue.append(pending)
        try persistToKeychain()
        attemptSend()
    }
    
    func processQueueWhenOnline() async {
        for pending in queue {
            do {
                try await repo.sendText(
                    conversationId: pending.conversationId,
                    to: pending.peerUserId,
                    text: pending.content
                )
                queue.removeAll { $0.id == pending.id }
            } catch {
                pending.retryCount += 1
                if pending.retryCount > 3 {
                    queue.removeAll { $0.id == pending.id }
                }
            }
        }
    }
}
```

### Priority 3: WebSocket Resilience
**Affected:** ChatSocket

**Current Issues:**
1. No auto-reconnect on disconnect
2. No heartbeat/ping mechanism
3. Manual JSON parsing (error-prone)
4. No message buffering during disconnect

**Need to add:**
```swift
class EnhancedChatSocket {
    private var reconnectTimer: Timer?
    private var messageBuffer: [String] = []
    private var isConnected = false
    private let reconnectStrategy: ExponentialBackoff
    
    func connect(...) {
        // Auto-reconnect on failure
        task?.resume()
        startHeartbeat()
    }
    
    private func startHeartbeat() {
        // Send ping every 30s
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.sendPing()
        }
    }
    
    func handleDisconnect(error: Error?) {
        isConnected = false
        scheduleReconnect()
    }
    
    private func scheduleReconnect() {
        let delay = reconnectStrategy.nextDelay()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.connect(...)  // Retry with backoff
        }
    }
}
```

---

## Missing Features by Category

### Stories (Backend ready, iOS missing)
**Backend Files:** `/handlers/stories.rs`
**What's needed:**

```swift
// New file: Network/Repositories/StoriesRepository.swift
final class StoriesRepository {
    func createStory(image: UIImage?, video: URL?) async throws -> Story {
        // Like createPost, but simpler
        // Stories expire in 24h
    }
    
    func getStories(userId: UUID) async throws -> [Story] {
        let endpoint = APIEndpoint(path: "/users/\(userId.uuidString)/stories", method: .get)
        return try await interceptor.executeWithRetry(endpoint)
    }
    
    func deleteStory(id: UUID) async throws {
        let endpoint = APIEndpoint(path: "/stories/\(id.uuidString)", method: .delete)
        try await interceptor.executeNoResponseWithRetry(endpoint)
    }
}

// New file: ViewModels/Stories/StoriesViewModel.swift
@MainActor
final class StoriesViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var isLoading = false
    
    private let repository = StoriesRepository()
    
    func loadStories(userId: UUID) async {
        isLoading = true
        do {
            stories = try await repository.getStories(userId: userId)
        } catch {
            // Handle error
        }
        isLoading = false
    }
}
```

### Live Streaming (Backend ready, iOS missing)
**Backend Files:** `/handlers/streams.rs`

```swift
// New file: Network/Repositories/StreamRepository.swift
final class StreamRepository {
    func getActiveStreams(category: String? = nil) async throws -> [LiveStream] {
        var items = [URLQueryItem(name: "status", value: "active")]
        if let category { items.append(URLQueryItem(name: "category", value: category)) }
        let ep = APIEndpoint(path: "/streams", method: .get, queryItems: items)
        let resp: StreamListResponse = try await interceptor.executeWithRetry(ep)
        return resp.streams
    }
    
    func createStream(title: String, category: String, isPublic: Bool) async throws -> LiveStream {
        let request = CreateStreamRequest(title: title, category: category, isPublic: isPublic)
        let ep = APIEndpoint(path: "/streams", method: .post, body: request)
        let resp: StreamResponse = try await interceptor.executeWithRetry(ep)
        return resp.stream
    }
    
    func endStream(streamId: UUID) async throws {
        let ep = APIEndpoint(path: "/streams/\(streamId.uuidString)/end", method: .post)
        try await interceptor.executeNoResponseWithRetry(ep)
    }
}

// Need RTMP publisher library integration
// Options:
// 1. BroadcastKit (iOS 12+)
// 2. Custom RTMP client library (e.g., SwiftRTMP)
// 3. HLS publishing via HTTP Live Streaming
```

### Push Notifications (Backend ready, iOS missing)
**What's needed:**

```swift
// New file: Services/Notifications/APNsManager.swift
import UserNotifications

@MainActor
final class APNsManager {
    static let shared = APNsManager()
    
    func registerForPushNotifications() async {
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            Logger.log("Push notification request failed: \(error)", level: .error)
        }
    }
    
    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Logger.log("Device token: \(token)", level: .info)
        
        // Send to backend
        Task {
            do {
                try await registerDeviceToken(token)
            } catch {
                Logger.log("Failed to register device token: \(error)", level: .error)
            }
        }
    }
    
    private func registerDeviceToken(_ token: String) async throws {
        let request = RegisterDeviceTokenRequest(deviceToken: token, platform: "ios")
        let endpoint = APIEndpoint(path: "/users/me/device-tokens", method: .post, body: request)
        try await RequestInterceptor(apiClient: APIClient(baseURL: AppConfig.baseURL))
            .executeNoResponseWithRetry(endpoint)
    }
}

// In AppDelegate
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Task {
        await APNsManager.shared.registerForPushNotifications()
    }
    return true
}

func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    APNsManager.shared.handleDeviceToken(deviceToken)
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // Handle notification
    if let notificationId = userInfo["notification_id"] as? String {
        Task {
            try? await NotificationRepository().markAsRead(id: UUID(uuidString: notificationId) ?? UUID())
        }
    }
    completionHandler(.newData)
}
```

### 2FA (Backend ready, iOS missing)
```swift
// New file: Network/Repositories/TwoFactorRepository.swift
final class TwoFactorRepository {
    func enable2FA() async throws -> TwoFactorSetup {
        let ep = APIEndpoint(path: "/auth/2fa/enable", method: .post)
        let resp: TwoFactorSetupResponse = try await interceptor.executeWithRetry(ep)
        return resp.setup
    }
    
    func confirm2FA(code: String) async throws {
        let request = ["code": code]
        let ep = APIEndpoint(path: "/auth/2fa/confirm", method: .post, body: request)
        try await interceptor.executeNoResponseWithRetry(ep)
    }
    
    func verify2FA(code: String) async throws -> Bool {
        let request = ["code": code]
        let ep = APIEndpoint(path: "/auth/2fa/verify", method: .post, body: request)
        let resp: VerifyResponse = try await interceptor.executeWithRetry(ep)
        return resp.verified
    }
}
```

---

## Data Synchronization Issues

### Model Gaps

**Post Model** - Has `video_ids` support in backend but iOS only uses `imageUrl`:
```swift
struct Post: Codable, Identifiable, Equatable {
    // ... existing fields ...
    let imageUrl: String
    let videos: [Video]?  // ← Add this
    
    enum CodingKeys: String, CodingKey {
        // ... existing ...
        case videos = "videos"
    }
}
```

**Stream Model** - Exists but not integrated:
```swift
// Ensure this exists and is complete
struct LiveStream: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let title: String
    let description: String?
    let thumbnailUrl: String?
    let status: StreamStatus  // "active", "ended", "scheduled"
    let category: String
    let viewerCount: Int
    let createdAt: Date
    let user: User?
}
```

---

## Testing Gaps

### Missing Test Coverage

```swift
// Tests needed in Tests/ directory

1. AuthRepositoryTests.swift
   - Test login flow
   - Test token refresh
   - Test logout clears state

2. MessagingRepositoryTests.swift
   - Test encryption/decryption
   - Test message history pagination
   - Test conversation creation

3. FeedRepositoryTests.swift
   - Test feed pagination
   - Test cache behavior
   - Test deduplication

4. RequestInterceptorTests.swift
   - Test auto-retry on failure
   - Test token refresh deduplication
   - Test exponential backoff

5. OfflineQueueTests.swift
   - Test queuing failed messages
   - Test persistence
   - Test retry on reconnect
```

---

## Summary of Blocked Work

| Feature | Blocker | Effort | Priority |
|---------|---------|--------|----------|
| Post creation | Config issue | 2h | P0 |
| Video upload | Config + upload URL endpoint | 8h | P1 |
| Message offline queue | Design + implementation | 6h | P1 |
| WebSocket resilience | Refactor + retry logic | 8h | P1 |
| Stories | New repository + UI | 12h | P2 |
| Live streaming | New repository + RTMP library | 20h | P2 |
| Push notifications | APNs setup + backend integration | 10h | P2 |
| 2FA | New repository + UI flow | 8h | P3 |

Total blocking work: ~10 hours for P0-P1 features
