# Phase 2: Matrix iOS SDK Migration Plan

## Overview

Migrate from Matrix Rust SDK (via FFI) to native matrix-ios-sdk for better stability, native Swift/ObjC integration, and automatic token refresh handling.

**Current Issues with Rust SDK:**
- Tokio runtime panics when objects deallocated outside async context
- FFI boundary causes memory management issues
- No native token refresh - M_UNKNOWN_TOKEN crashes app
- Complex stub types needed for compilation fallback

**Benefits of matrix-ios-sdk:**
- Native Swift/ObjC - no FFI boundary issues
- Automatic token refresh via MXSession
- Mature, battle-tested in Element iOS
- Better debugging and crash reporting
- Native iOS crypto via MatrixSDKCrypto (still uses Rust for E2EE, but proper integration)

---

## Migration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MatrixBridgeService                       │
│               (NO CHANGES - Adapter Layer)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  MatrixServiceProtocol                       │
│                 (INTERFACE - NO CHANGES)                     │
│   23 methods: login, sync, createRoom, sendMessage, etc.    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    MXMatrixService                           │
│            (NEW IMPLEMENTATION using matrix-ios-sdk)         │
│  - MXRestClient for API calls                               │
│  - MXSession for session management                         │
│  - MXRoom for room operations                               │
│  - MXCredentials for auth                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Step 1: Dependency Setup

### 1.1 Remove MatrixRustSDK

**project.yml changes:**
```yaml
packages:
  # REMOVE this:
  # MatrixRustSDK:
  #   url: https://github.com/matrix-org/matrix-rust-components-swift
  #   from: 1.0.0
```

**Build Settings:**
- Remove `MATRIX_SDK_ENABLED` from Active Compilation Conditions

### 1.2 Add matrix-ios-sdk via CocoaPods

**Podfile:**
```ruby
platform :ios, '15.0'
use_frameworks!

target 'NovaSocial' do
  # Matrix iOS SDK with Crypto (E2EE)
  pod 'MatrixSDK', '~> 0.27'
  pod 'MatrixSDK/JingleCallStack'  # Optional: VoIP
end
```

**Alternative: Swift Package Manager**
```yaml
packages:
  MatrixSDK:
    url: https://github.com/matrix-org/matrix-ios-sdk
    from: 0.27.0
```

### 1.3 Bridging Header (if needed)

Create `NovaSocial-Bridging-Header.h`:
```objc
#import <MatrixSDK/MatrixSDK.h>
```

---

## Step 2: API Mapping Reference

### 2.1 Core Types Mapping

| Rust SDK Type | matrix-ios-sdk Type | Notes |
|--------------|---------------------|-------|
| `Client` | `MXSession` | Main session object |
| `ClientBuilder` | `MXRestClient` + `MXCredentials` | Build via credentials |
| `Room` | `MXRoom` | Room operations |
| `Timeline` | `MXEventTimeline` | Message timeline |
| `Session` | `MXCredentials` | Auth credentials |
| `SyncService` | Built into `MXSession` | Automatic sync |
| `RoomListService` | `MXRoomListDataManager` | Room list updates |

### 2.2 Method Mapping (23 Protocol Methods)

```swift
// ═══════════════════════════════════════════════════════════════
// INITIALIZATION & AUTHENTICATION (5 methods)
// ═══════════════════════════════════════════════════════════════

// initialize(homeserverURL:sessionPath:)
// Rust:  ClientBuilder().homeserverUrl(url).sessionPaths(data,cache).build()
// iOS:   MXRestClient(homeServer: url, unrecognizedCertificateHandler: nil)

// login(novaUserId:accessToken:)
// Rust:  client.restoreSession(session: Session(...))
// iOS:   let credentials = MXCredentials(homeServer: url, userId: matrixId, accessToken: token)
//        MXSession(credentials: credentials)

// loginWithPassword(username:password:)
// Rust:  client.login(username:password:initialDeviceName:deviceId:)
// iOS:   restClient.login(username: user, password: pass) { response in
//            let credentials = MXCredentials(from: response)
//            MXSession(credentials: credentials)
//        }

// restoreSession() -> Bool
// Rust:  client.restoreSession(session:)
// iOS:   MXFileStore() -> MXSession.setStore() -> session.resume()

// logout()
// Rust:  client.logout()
// iOS:   session.logout { ... }; session.close()

// ═══════════════════════════════════════════════════════════════
// SYNC (2 methods)
// ═══════════════════════════════════════════════════════════════

// startSync()
// Rust:  syncService = client.syncService().finish(); syncService.start()
// iOS:   session.start { response in ... }  // Sync is automatic

// stopSync()
// Rust:  syncService.stop()
// iOS:   session.pause()

// ═══════════════════════════════════════════════════════════════
// ROOM OPERATIONS (5 methods)
// ═══════════════════════════════════════════════════════════════

// createRoom(name:isDirect:inviteUserIds:isEncrypted:) -> String
// Rust:  client.createRoom(request: CreateRoomParameters(...))
// iOS:   let params = MXRoomCreationParameters()
//        params.name = name
//        params.isDirect = isDirect
//        params.inviteArray = userIds
//        params.preset = isDirect ? kMXRoomPresetTrustedPrivateChat : kMXRoomPresetPrivateChat
//        params.initialStateEvents = [/* encryption event */]
//        session.createRoom(parameters: params) { response in ... }

// joinRoom(roomIdOrAlias:) -> String
// Rust:  client.joinRoomByIdOrAlias(roomIdOrAlias:serverNames:)
// iOS:   session.joinRoom(roomIdOrAlias) { response in ... }

// leaveRoom(roomId:)
// Rust:  room.leave()
// iOS:   room.leave { response in ... }

// getRoom(roomId:) -> MatrixRoom?
// Rust:  client.getRoom(roomId:)
// iOS:   session.room(withRoomId: roomId)

// getJoinedRooms() -> [MatrixRoom]
// Rust:  client.rooms()
// iOS:   session.rooms.filter { $0.summary.membership == .join }

// ═══════════════════════════════════════════════════════════════
// MESSAGING (3 methods)
// ═══════════════════════════════════════════════════════════════

// sendMessage(roomId:content:) -> String
// Rust:  timeline.send(msg: messageEventContentFromMarkdown(md:))
// iOS:   room.sendTextMessage(content) { response in ... }

// sendMedia(roomId:mediaURL:mimeType:caption:) -> String
// Rust:  timeline.sendImage/sendVideo/sendAudio/sendFile(...)
// iOS:   room.sendImage(localURL, mimeType:, size:, ...) { ... }
//        room.sendVideo(localURL, thumbnail:, ...) { ... }
//        room.sendFile(localURL, mimeType:, ...) { ... }

// getRoomMessages(roomId:limit:from:) -> [MatrixMessage]
// Rust:  timeline.paginateBackwards(numEvents:); timeline.addListener(...)
// iOS:   room.liveTimeline { timeline in
//            timeline.paginate(limit, direction: .backwards, ...) { ... }
//            timeline.listenToEvents { event, direction, state in ... }
//        }

// ═══════════════════════════════════════════════════════════════
// USER OPERATIONS (4 methods)
// ═══════════════════════════════════════════════════════════════

// inviteUser(roomId:userId:)
// Rust:  room.inviteUserById(userId:)
// iOS:   room.invite(userId) { response in ... }

// kickUser(roomId:userId:reason:)
// Rust:  room.kickUser(userId:reason:)
// iOS:   room.kickUser(userId, reason:) { response in ... }

// setTyping(roomId:isTyping:)
// Rust:  room.typingNotice(isTyping:)
// iOS:   room.sendTypingNotification(typing: isTyping, timeout: 30000) { ... }

// markRoomAsRead(roomId:)
// Rust:  timeline.markAsRead(receiptType:)
// iOS:   room.markAllAsRead() { ... }

// ═══════════════════════════════════════════════════════════════
// REACTIONS/EDITING (4 methods)
// ═══════════════════════════════════════════════════════════════

// editMessage(roomId:eventId:newContent:)
// Rust:  timeline.edit(eventOrTransactionId:newContent:)
// iOS:   room.sendTextMessage(newContent, replaces: eventId) { ... }

// redactMessage(roomId:eventId:reason:)
// Rust:  timeline.redactEvent(eventOrTransactionId:reason:)
// iOS:   room.redactEvent(eventId, reason:) { response in ... }

// toggleReaction(roomId:eventId:emoji:)
// Rust:  timeline.toggleReaction(itemId:key:)
// iOS:   let aggregations = room.aggregations(forEvent: eventId)
//        if aggregations?.reactions?[emoji]?.containsCurrentUser {
//            room.unreact(emoji, toEvent: eventId) { ... }
//        } else {
//            room.react(emoji, toEvent: eventId) { ... }
//        }

// sendReaction(roomId:eventId:emoji:)
// Rust:  timeline.toggleReaction (add-only behavior)
// iOS:   room.react(emoji, toEvent: eventId) { response in ... }

// getReactions(roomId:eventId:) -> [MatrixReaction]
// Rust:  (reactions from timeline events)
// iOS:   let aggregations = room.aggregations(forEvent: eventId)
//        aggregations?.reactions.map { ... }
```

---

## Step 3: Implementation Plan

### 3.1 New File: `MXMatrixService.swift`

```swift
import Foundation
import Combine
import MatrixSDK

/// Matrix service implementation using native matrix-ios-sdk
@MainActor
@Observable
final class MXMatrixService: MatrixServiceProtocol {

    // MARK: - Singleton
    static let shared = MXMatrixService()

    // MARK: - State
    private(set) var connectionState: MatrixConnectionState = .disconnected
    private let connectionStateSubject = CurrentValueSubject<MatrixConnectionState, Never>(.disconnected)

    var connectionStatePublisher: AnyPublisher<MatrixConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    private(set) var userId: String?

    // MARK: - matrix-ios-sdk Components
    private var restClient: MXRestClient?
    private var session: MXSession?
    private var fileStore: MXFileStore?
    private var credentials: MXCredentials?

    // MARK: - Configuration
    private var homeserverURL: String?
    private var sessionPath: String?

    // MARK: - Room Cache
    private var roomCache: [String: MatrixRoom] = [:]

    // MARK: - Callbacks
    var onMessageReceived: ((MatrixMessage) -> Void)?
    var onRoomUpdated: ((MatrixRoom) -> Void)?
    var onTypingIndicator: ((String, [String]) -> Void)?

    // MARK: - Listeners
    private var eventListeners: [String: Any] = [:]

    // MARK: - Initialization

    private init() {
        #if DEBUG
        print("[MXMatrixService] Initialized with matrix-ios-sdk")
        #endif
    }

    // MARK: - Protocol Implementation

    func initialize(homeserverURL: String, sessionPath: String) async throws {
        self.homeserverURL = homeserverURL
        self.sessionPath = sessionPath

        updateConnectionState(.connecting)

        // Create REST client
        guard let homeserverUrl = URL(string: homeserverURL) else {
            throw MatrixError.sdkError("Invalid homeserver URL")
        }

        restClient = MXRestClient(homeServer: homeserverUrl, unrecognizedCertificateHandler: nil)

        // Initialize file store for persistence
        fileStore = MXFileStore()

        updateConnectionState(.disconnected)

        #if DEBUG
        print("[MXMatrixService] Initialized with homeserver: \(homeserverURL)")
        #endif
    }

    func login(novaUserId: String, accessToken: String) async throws {
        guard restClient != nil else {
            throw MatrixError.notInitialized
        }

        updateConnectionState(.connecting)

        let matrixUserId = convertToMatrixUserId(novaUserId: novaUserId)

        // Create credentials
        credentials = MXCredentials(
            homeServer: homeserverURL,
            userId: matrixUserId,
            accessToken: accessToken
        )
        credentials?.deviceId = getOrCreateDeviceId()

        // Create session
        session = MXSession(credentials: credentials!)

        // Set up file store
        if let store = fileStore {
            session?.setStore(store) { [weak self] response in
                if case .failure(let error) = response {
                    self?.updateConnectionState(.error(error.localizedDescription))
                }
            }
        }

        self.userId = matrixUserId
        storeSessionCredentials(userId: matrixUserId, accessToken: accessToken, deviceId: credentials!.deviceId!)

        updateConnectionState(.connected)

        #if DEBUG
        print("[MXMatrixService] Logged in as: \(matrixUserId)")
        #endif
    }

    // ... (implement all other protocol methods)

    // MARK: - Token Refresh Handling

    /// matrix-ios-sdk handles token refresh automatically via MXSession
    /// When token expires, it will:
    /// 1. Pause sync
    /// 2. Attempt refresh using refresh_token
    /// 3. Resume sync on success
    /// 4. Call delegate on failure for re-authentication

    private func setupSessionDelegate() {
        // MXSessionDelegate handles:
        // - sessionDidReceiveSyncError (for token expiration)
        // - sessionStateDidChange
        // - session.credentials.accessToken updates automatically
    }
}
```

### 3.2 Token Refresh Implementation

```swift
extension MXMatrixService: MXSessionDelegate {

    func session(_ session: MXSession, didReceiveError error: Error) {
        // Check for token expiration
        if let mxError = error as? MXError,
           mxError.errcode == kMXErrCodeStringUnknownToken {

            #if DEBUG
            print("[MXMatrixService] Token expired, attempting refresh...")
            #endif

            // matrix-ios-sdk will automatically try to refresh if refresh_token exists
            // If not, we need to clear session and re-authenticate
            if session.credentials.refreshToken == nil {
                clearSessionCredentials()
                updateConnectionState(.error("Session expired. Please login again."))
            }
        }
    }

    func session(_ session: MXSession, newRefreshToken refreshToken: String) {
        // Store new refresh token
        #if DEBUG
        print("[MXMatrixService] Received new refresh token")
        #endif

        // Update stored credentials
        if let userId = session.myUserId,
           let accessToken = session.credentials.accessToken,
           let deviceId = session.credentials.deviceId {
            storeSessionCredentials(userId: userId, accessToken: accessToken, deviceId: deviceId)
        }
    }
}
```

---

## Step 4: Migration Checklist

### Phase 2.1: Setup (Day 1)
- [ ] Add MatrixSDK pod/SPM dependency
- [ ] Create bridging header if needed
- [ ] Verify build succeeds with new SDK

### Phase 2.2: Core Implementation (Days 2-3)
- [ ] Create `MXMatrixService.swift` skeleton
- [ ] Implement `initialize()` with MXRestClient
- [ ] Implement `login()` with MXCredentials + MXSession
- [ ] Implement `loginWithPassword()` with MXRestClient.login
- [ ] Implement `restoreSession()` with MXFileStore
- [ ] Implement `logout()` with session.logout + close
- [ ] Implement `startSync()` with session.start
- [ ] Implement `stopSync()` with session.pause

### Phase 2.3: Room Operations (Day 4)
- [ ] Implement `createRoom()` with MXRoomCreationParameters
- [ ] Implement `joinRoom()` with session.joinRoom
- [ ] Implement `leaveRoom()` with room.leave
- [ ] Implement `getRoom()` with session.room(withRoomId:)
- [ ] Implement `getJoinedRooms()` with session.rooms filter

### Phase 2.4: Messaging (Day 5)
- [ ] Implement `sendMessage()` with room.sendTextMessage
- [ ] Implement `sendMedia()` with room.sendImage/Video/File
- [ ] Implement `getRoomMessages()` with timeline pagination
- [ ] Set up MXEventListener for real-time messages

### Phase 2.5: User & Reactions (Day 6)
- [ ] Implement `inviteUser()` with room.invite
- [ ] Implement `kickUser()` with room.kickUser
- [ ] Implement `setTyping()` with sendTypingNotification
- [ ] Implement `markRoomAsRead()` with markAllAsRead
- [ ] Implement `editMessage()` with sendTextMessage(replaces:)
- [ ] Implement `redactMessage()` with redactEvent
- [ ] Implement `toggleReaction()` with react/unreact
- [ ] Implement `getReactions()` with aggregations

### Phase 2.6: Integration (Day 7)
- [ ] Update MatrixService.swift to use MXMatrixService
- [ ] Keep MatrixServiceProtocol interface unchanged
- [ ] Verify MatrixBridgeService works without changes
- [ ] Remove Rust SDK stubs (lines 26-309)

### Phase 2.7: Testing (Days 8-9)
- [ ] Test login flow with SSO
- [ ] Test session restoration
- [ ] Test token refresh handling
- [ ] Test room creation (direct & group)
- [ ] Test message sending/receiving
- [ ] Test media sending
- [ ] Test reactions
- [ ] Test message editing/deletion
- [ ] Test E2EE encryption

### Phase 2.8: Cleanup (Day 10)
- [ ] Remove MatrixRustSDK package dependency
- [ ] Remove MATRIX_SDK_ENABLED compilation flag
- [ ] Remove stub types
- [ ] Update documentation
- [ ] Archive old MatrixService.swift

---

## Step 5: Risk Mitigation

### 5.1 Fallback Strategy
Keep the current Rust SDK implementation as `MatrixServiceRust.swift` until migration is complete and tested.

```swift
// Feature flag to switch implementations
enum MatrixSDKImplementation {
    case rustSDK   // Current (deprecated)
    case iosSDK    // New (matrix-ios-sdk)
}

let activeImplementation: MatrixSDKImplementation = .iosSDK
```

### 5.2 E2EE Compatibility
matrix-ios-sdk uses MatrixSDKCrypto (Rust-based) for encryption, same as Element iOS. This ensures:
- Full E2EE support
- Device verification
- Key backup
- Cross-signing

### 5.3 Data Migration
Session data stored by Rust SDK is NOT compatible with matrix-ios-sdk. On first launch after migration:
1. Detect old session format
2. Clear session data
3. Prompt user to re-login
4. Re-establish E2EE keys

---

## Step 6: Estimated Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| 2.1 | 1 day | Dependency setup |
| 2.2 | 2 days | Core implementation |
| 2.3 | 1 day | Room operations |
| 2.4 | 1 day | Messaging |
| 2.5 | 1 day | User operations & reactions |
| 2.6 | 1 day | Integration |
| 2.7 | 2 days | Testing |
| 2.8 | 1 day | Cleanup |
| **Total** | **10 days** | Full migration |

---

## References

- [matrix-ios-sdk GitHub](https://github.com/matrix-org/matrix-ios-sdk)
- [matrix-ios-sdk Documentation](https://matrix-org.github.io/matrix-ios-sdk/)
- [Element iOS (reference implementation)](https://github.com/element-hq/element-ios)
- [MatrixSDK Podspec](https://cocoapods.org/pods/MatrixSDK)
- [Token Refresh MR](https://github.com/matrix-org/matrix-ios-sdk/pull/1657)
