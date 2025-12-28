import Foundation
import Combine
import UIKit  // For UIDevice

// MARK: - MatrixRustSDK Import
// Import the Matrix Rust SDK Swift components
// Package: https://github.com/matrix-org/matrix-rust-components-swift

// MARK: - MatrixRustSDK Conditional Import
// Use MATRIX_SDK_ENABLED flag instead of canImport() for reliable detection
// Set in Build Settings > Swift Compiler - Custom Flags > Active Compilation Conditions
//
// When MATRIX_SDK_ENABLED is defined:
//   - Real MatrixRustSDK types are used
//   - Full E2EE functionality is available
//
// When NOT defined (fallback mode):
//   - Stub types allow compilation without the SDK
//   - E2EE features gracefully degrade

#if MATRIX_SDK_ENABLED
import MatrixRustSDK
// Real SDK types are now available: Client, ClientBuilder, Room, Timeline, Session, etc.

#else
// MARK: - Stub Mode Active
// MatrixRustSDK package not available - using stub implementations
// To enable real SDK: Add MATRIX_SDK_ENABLED to Active Compilation Conditions
// MARK: - MatrixRustSDK Stub Types (Fallback)
// These stub types allow compilation when SDK is not yet resolved
// They will be replaced by real SDK types once the package is downloaded

class Client {
    func userId() -> String { "" }
    func rooms() -> [Room] { [] }
    func getRoom(roomId: String) -> Room? { nil }
    func createRoom(request: CreateRoomParameters) async throws -> String { "" }
    func joinRoomByIdOrAlias(roomIdOrAlias: String, serverNames: [String]) async throws -> Room {
        fatalError("MatrixRustSDK not integrated")
    }
    func syncService() -> SyncServiceBuilder { SyncServiceBuilder() }
    func login(username: String, password: String, initialDeviceName: String, deviceId: String?) async throws {}
    func logout() async throws {}
    func session() throws -> Session { fatalError("MatrixRustSDK not integrated") }
    func restoreSession(session: Session) async throws {}
    /// Returns the sliding sync versions available on the homeserver
    func availableSlidingSyncVersions() async -> [SlidingSyncVersion] { [.none] }
    /// Returns the current sliding sync version being used
    func slidingSyncVersion() -> SlidingSyncVersion { .none }
}

/// Builder enum for sliding sync version configuration
enum SlidingSyncVersionBuilder {
    case none
    case native
    case discoverNative
}

class ClientBuilder {
    func homeserverUrl(url: String) -> ClientBuilder { self }
    func sessionPath(path: String) -> ClientBuilder { self }
    func sessionPaths(dataPath: String, cachePath: String) -> ClientBuilder { self }
    func userAgent(userAgent: String) -> ClientBuilder { self }
    func setSessionDelegate(sessionDelegate: ClientSessionDelegate) -> ClientBuilder { self }
    func slidingSyncVersionBuilder(versionBuilder: SlidingSyncVersionBuilder) -> ClientBuilder { self }
    func build() async throws -> Client { Client() }
}

class SyncServiceBuilder {
    func withCrossProcessLock() -> SyncServiceBuilder { self }
    func finish() async throws -> SyncService { SyncService() }
}

class SyncService {
    func start() async throws {}
    func stop() async throws {}
    func roomListService() -> RoomListService { RoomListService() }
    func state(listener: SyncServiceStateObserver) -> TaskHandle { TaskHandle() }
}

enum SyncServiceState {
    case idle
    case running
    case terminated
    case error
}

protocol SyncServiceStateObserver: AnyObject, Sendable {
    func onUpdate(state: SyncServiceState)
}

class RoomListService {
    func allRooms() async throws -> RoomList { RoomList() }
    func state(listener: RoomListServiceStateListener) -> TaskHandle { TaskHandle() }
}

enum RoomListServiceState {
    case initial
    case settingUp
    case recovering
    case running
    case error
    case terminated
}

protocol RoomListServiceStateListener: AnyObject, Sendable {
    func onUpdate(state: RoomListServiceState)
}

class RoomList {
    func entriesWithDynamicAdapters(pageSize: UInt32, listener: RoomListEntriesListener) -> RoomListEntriesWithDynamicAdaptersResult {
        return RoomListEntriesWithDynamicAdaptersResult()
    }

    func room(roomId: String) throws -> Room {
        return Room()
    }
}

class Room {
    func id() -> String { "" }
    func displayName() -> String? { nil }
    func roomInfo() -> RoomInfo { RoomInfo() }
    func leave() async throws {}
    func inviteUserById(userId: String) async throws {}
    func kickUser(userId: String, reason: String?) async throws {}
    func typingNotice(isTyping: Bool) async throws {}
    func timeline() async throws -> Timeline { Timeline() }
}

enum Membership {
    case invited
    case joined
    case left
    case banned
    case knocked
}

enum EncryptionState {
    case encrypted
    case notEncrypted
}

struct RoomInfo {
    var topic: String?
    var avatarUrl: String?
    var isDirect: Bool = false
    var isEncrypted: Bool = false
    var activeMembersCount: UInt = 0
    var numUnreadMessages: UInt = 0
    var membership: Membership = .joined
    var encryptionState: EncryptionState = .notEncrypted
}

class Timeline {
    func send(msg: Any) async throws {}
    func paginateBackwards(numEvents: UInt16) async throws {}
    func getTimelineItems() -> [TimelineItem] { [] }
    func addListener(listener: TimelineListener) async -> TaskHandle { TaskHandle() }
    func markAsRead(receiptType: ReceiptType) async throws {}
    func sendImage(url: String, thumbnailUrl: String?, imageInfo: ImageInfo, caption: String?, formattedCaption: String?, progressWatcher: Any?) async throws {}
    func sendVideo(url: String, thumbnailUrl: String?, videoInfo: VideoInfo, caption: String?, formattedCaption: String?, progressWatcher: Any?) async throws {}
    func sendAudio(url: String, audioInfo: AudioInfo, caption: String?, formattedCaption: String?, progressWatcher: Any?) async throws {}
    func sendFile(url: String, fileInfo: FileInfo, progressWatcher: Any?) async throws {}
    // Edit message
    func edit(eventOrTransactionId: EventOrTransactionId, newContent: EditedContent) async throws {}
    // Redact (delete) message
    func redactEvent(eventOrTransactionId: EventOrTransactionId, reason: String?) async throws {}
    // Reactions - toggle only (adds if not present, removes if present)
    func toggleReaction(itemId: EventOrTransactionId, key: String) async throws {}
}

enum EventOrTransactionId {
    case eventId(eventId: String)
    case transactionId(transactionId: String)
}

struct EditedContent {
    let content: RoomMessageEventContentWithoutRelation

    static func roomMessage(content: RoomMessageEventContentWithoutRelation) -> EditedContent {
        return EditedContent(content: content)
    }
}

struct RoomMessageEventContentWithoutRelation {
    let body: String
    let formatted: FormattedBody?

    init(body: String, formatted: FormattedBody? = nil) {
        self.body = body
        self.formatted = formatted
    }
}

struct FormattedBody {
    let format: MessageFormat
    let body: String
}

enum MessageFormat {
    case html
}

enum ReceiptType { case read }

class TimelineItem {
    func asEvent() -> EventTimelineItem? { nil }
}

class EventTimelineItem {
    func eventId() -> String? { nil }
    func sender() -> String { "" }
    func timestamp() -> UInt64 { 0 }
    func content() -> TimelineItemContent? { nil }
}

class TimelineItemContent {
    func kind() -> TimelineItemContentKind { .message }
    func asMessage() -> MessageContent? { nil }
}

enum TimelineItemContentKind { case message }

class MessageContent {
    func body() -> String { "" }
    func msgtype() -> MatrixMessageTypeSDK { .text }
}

enum MatrixMessageTypeSDK { case text, image, video, audio, file, location, notice, emote }

struct Session {
    var accessToken: String
    var refreshToken: String?
    var userId: String
    var deviceId: String
    var homeserverUrl: String
    var oidcData: String?
    var slidingSyncVersion: SlidingSyncVersion
}

enum SlidingSyncVersion { case none, native }

struct CreateRoomParameters {
    var name: String?
    var topic: String?
    var isEncrypted: Bool
    var isDirect: Bool
    var visibility: RoomVisibility
    var preset: RoomPreset
    var invite: [String]
    var avatar: String?
    var powerLevelContentOverride: String?
}

enum RoomVisibility { case `private` }
enum RoomPreset { case trustedPrivateChat, privateChat }

struct ImageInfo {
    var height: UInt64?
    var width: UInt64?
    var mimetype: String?
    var size: UInt64
    var thumbnailInfo: String?
    var thumbnailSource: String?
    var blurhash: String?
}

struct VideoInfo {
    var duration: UInt64?
    var height: UInt64?
    var width: UInt64?
    var mimetype: String?
    var size: UInt64
    var thumbnailInfo: String?
    var thumbnailSource: String?
    var blurhash: String?
}

struct AudioInfo {
    var duration: UInt64?
    var size: UInt64
    var mimetype: String?
}

struct FileInfo {
    var mimetype: String?
    var size: UInt64
    var thumbnailInfo: String?
    var thumbnailSource: String?
}

class TaskHandle {
    func cancel() {}
}

// New SDK uses Room objects directly, no RoomListEntry wrapper
enum RoomListEntriesUpdate {
    case append(values: [Room])
    case clear
    case pushFront(value: Room)
    case pushBack(value: Room)
    case popFront
    case popBack
    case insert(index: UInt32, value: Room)
    case set(index: UInt32, value: Room)
    case remove(index: UInt32)
    case truncate(length: UInt32)
    case reset(values: [Room])
}

protocol RoomListEntriesListener: AnyObject, Sendable {
    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate])
}

protocol RoomListEntriesWithDynamicAdaptersResultProtocol: AnyObject {
    func controller() -> RoomListDynamicEntriesControllerProtocol
    func entriesStream() -> TaskHandle
}

protocol RoomListDynamicEntriesControllerProtocol: AnyObject {
    func setFilter(kind: RoomListEntriesDynamicFilterKind) -> Bool
}

enum RoomListEntriesDynamicFilterKind {
    case all(filters: [RoomListEntriesDynamicFilterKind])
    case any(filters: [RoomListEntriesDynamicFilterKind])
    case joined
    case invite
    case nonLeft
    case none
}

class RoomListEntriesWithDynamicAdaptersResult: RoomListEntriesWithDynamicAdaptersResultProtocol {
    func controller() -> RoomListDynamicEntriesControllerProtocol {
        return RoomListDynamicEntriesController()
    }

    func entriesStream() -> TaskHandle {
        TaskHandle()
    }
}

class RoomListDynamicEntriesController: RoomListDynamicEntriesControllerProtocol {
    func setFilter(kind: RoomListEntriesDynamicFilterKind) -> Bool { true }
}

enum TimelineDiff {
    case append(values: [TimelineItem])
    case clear
    case pushFront(value: TimelineItem)
    case pushBack(value: TimelineItem)
    case popFront
    case popBack
    case insert(index: UInt32, value: TimelineItem)
    case set(index: UInt32, value: TimelineItem)
    case remove(index: UInt32)
    case truncate(length: UInt32)
    case reset(values: [TimelineItem])
}

protocol TimelineListener: AnyObject, Sendable {
    func onUpdate(diff: [TimelineDiff])
}

func messageEventContentFromMarkdown(md: String) -> Any { md }

// Stub for ClientSessionDelegate when SDK not available
protocol ClientSessionDelegate: AnyObject, Sendable {
    func saveSessionInKeychain(session: Session)
    func retrieveSessionFromKeychain(userId: String) throws -> Session
}

// Stub for MatrixSessionDelegateImpl when SDK not available
final class MatrixSessionDelegateImpl: ClientSessionDelegate, @unchecked Sendable {
    private weak var matrixService: MatrixService?

    init(matrixService: MatrixService) {
        self.matrixService = matrixService
    }

    func saveSessionInKeychain(session: Session) {
        // Stub - no-op when SDK not available
    }

    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        throw MatrixError.notInitialized
    }
}

#endif
// End of conditional SDK import - real types used when MATRIX_SDK_ENABLED is defined

// MARK: - Timeline Item Collector Helper

/// Helper class to collect timeline items from the listener-based API
private final class TimelineItemCollector: TimelineListener, @unchecked Sendable {
    private let onItemsReceived: ([TimelineItem]) -> Void
    private var hasReturned = false

    init(onItemsReceived: @escaping ([TimelineItem]) -> Void) {
        self.onItemsReceived = onItemsReceived
    }

    func onUpdate(diff: [TimelineDiff]) {
        guard !hasReturned else { return }

        var items: [TimelineItem] = []
        var sawReset = false
        for d in diff {
            switch d {
            case .reset(let values):
                items = values
                sawReset = true
            case .append(let values):
                items.append(contentsOf: values)
            case .pushBack(let value):
                items.append(value)
            case .pushFront(let value):
                items.insert(value, at: 0)
            default:
                break
            }
        }

        if sawReset || !items.isEmpty {
            hasReturned = true
            onItemsReceived(items)
        }
    }
}

/// Listener for continuous timeline updates (used for realtime message delivery)
private final class RoomTimelineListener: TimelineListener, @unchecked Sendable {
    private let onDiff: ([TimelineDiff]) -> Void

    init(onDiff: @escaping ([TimelineDiff]) -> Void) {
        self.onDiff = onDiff
    }

    func onUpdate(diff: [TimelineDiff]) {
        onDiff(diff)
    }
}

// MARK: - Matrix Service
//
// Matrix Rust SDK integration for end-to-end encrypted chat
// This service wraps the Matrix Rust SDK FFI bindings for iOS
//
// Architecture:
// - Uses MatrixRustSDK Swift package (matrix-rust-components-swift)
// - Client lifecycle: build -> login -> sync -> send/receive
// - Room operations: create -> join -> leave -> invite
// - E2EE is handled automatically by the SDK
//
// Integration with Nova backend:
// - Nova backend runs Matrix Synapse homeserver
// - User IDs map: nova-uuid -> @nova-<uuid>:staging.nova.internal
// - Conversation IDs map to Matrix room IDs stored in DB

// MARK: - Matrix Service Protocol

@MainActor
protocol MatrixServiceProtocol: AnyObject {
    /// Current connection state
    var connectionState: MatrixConnectionState { get }
    var connectionStatePublisher: AnyPublisher<MatrixConnectionState, Never> { get }

    /// Current user ID (if logged in)
    var userId: String? { get }

    /// Initialize the Matrix client with session data
    func initialize(homeserverURL: String, sessionPath: String) async throws

    /// Login with Nova credentials (bridges to Matrix)
    func login(novaUserId: String, accessToken: String, deviceId: String?) async throws

    /// Login with username/password directly
    func loginWithPassword(username: String, password: String) async throws

    /// Restore session from stored credentials
    func restoreSession() async throws -> Bool

    /// Logout and clear session
    func logout() async throws

    /// Clear stored credentials without full logout (for session expiry recovery)
    func clearCredentials()

    /// Start background sync
    func startSync() async throws

    /// Stop background sync
    func stopSync()

    /// Create a new room (direct or group)
    func createRoom(name: String?, isDirect: Bool, inviteUserIds: [String], isEncrypted: Bool) async throws -> String

    /// Join existing room by ID or alias
    func joinRoom(roomIdOrAlias: String) async throws -> String

    /// Leave a room
    func leaveRoom(roomId: String) async throws

    /// Send a text message to a room
    func sendMessage(roomId: String, content: String) async throws -> String

    /// Send a media message (image, file, etc.)
    func sendMedia(roomId: String, mediaURL: URL, mimeType: String, caption: String?) async throws -> String

    /// Get room timeline/messages
    func getRoomMessages(roomId: String, limit: Int, from: String?) async throws -> [MatrixMessage]

    /// Invite user to room
    func inviteUser(roomId: String, userId: String) async throws

    /// Kick user from room
    func kickUser(roomId: String, userId: String, reason: String?) async throws

    /// Update user power level in room
    func updatePowerLevel(roomId: String, userId: String, powerLevel: Int) async throws

    /// Set typing indicator
    func setTyping(roomId: String, isTyping: Bool) async throws

    /// Mark room as read
    func markRoomAsRead(roomId: String) async throws

    /// Get room by ID
    func getRoom(roomId: String) -> MatrixRoom?

    /// Get all joined rooms
    func getJoinedRooms() async throws -> [MatrixRoom]

    /// Get room members
    func getRoomMembers(roomId: String) async throws -> [MatrixRoomMember]

    // MARK: - Message Edit/Delete/Reactions

    /// Edit a message
    func editMessage(roomId: String, eventId: String, newContent: String) async throws

    /// Delete/redact a message
    func redactMessage(roomId: String, eventId: String, reason: String?) async throws

    /// Toggle reaction on a message (add if not present, remove if present)
    func toggleReaction(roomId: String, eventId: String, emoji: String) async throws

    /// Send reaction to a message
    func sendReaction(roomId: String, eventId: String, emoji: String) async throws

    /// Get reactions for a message
    func getReactions(roomId: String, eventId: String) async throws -> [MatrixReaction]
}

// MARK: - Matrix Connection State

enum MatrixConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case syncing
    case error(String)
}

// MARK: - Matrix Models

struct MatrixRoom: Identifiable, Equatable {
    let id: String  // Matrix room ID (!xxx:server)
    let name: String?
    let topic: String?
    let avatarURL: String?
    let isDirect: Bool
    let isEncrypted: Bool
    let memberCount: Int
    let unreadCount: Int
    let lastMessage: MatrixMessage?
    let lastActivity: Date?

    /// Nova conversation ID (mapped from backend)
    var novaConversationId: String?
}

struct MatrixMessage: Identifiable, Equatable {
    let id: String  // Matrix event ID ($xxx)
    let roomId: String
    let senderId: String
    let content: String
    let type: MatrixMessageType
    let timestamp: Date
    let isEdited: Bool
    let replyTo: String?

    /// Media info for image/file messages
    let mediaURL: String?
    let mediaInfo: MediaInfo?

    struct MediaInfo: Equatable {
        let mimeType: String
        let size: Int64
        let width: Int?
        let height: Int?
        let thumbnailURL: String?
    }
}

/// Room member information from Matrix
struct MatrixRoomMember: Identifiable, Equatable {
    let id: String  // User ID
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let powerLevel: Int
    let isAdmin: Bool
    let membership: MatrixMembershipState
}

/// Matrix membership state
enum MatrixMembershipState: String, Equatable {
    case join
    case invite
    case leave
    case ban
    case knock
    case unknown
}

enum MatrixMessageType: String, Equatable {
    case text = "m.text"
    case image = "m.image"
    case video = "m.video"
    case audio = "m.audio"
    case file = "m.file"
    case location = "m.location"
    case notice = "m.notice"
    case emote = "m.emote"
}

/// Matrix reaction model
struct MatrixReaction: Identifiable, Equatable {
    let id: String  // Unique identifier (eventId + emoji)
    let eventId: String  // The message event ID this reaction is on
    let senderId: String  // Who sent the reaction
    let emoji: String  // The reaction emoji/key
    let timestamp: Date
}

/// Aggregated reaction for display
struct MatrixReactionGroup: Identifiable, Equatable {
    var id: String { emoji }
    let emoji: String
    var count: Int
    var senderIds: [String]
    var includesCurrentUser: Bool
}

// MARK: - Matrix Service Errors

enum MatrixError: Error, LocalizedError {
    case notInitialized
    case notLoggedIn
    case loginFailed(String)
    case roomNotFound(String)
    case sendFailed(String)
    case syncFailed(String)
    case networkError(String)
    case sdkError(String)
    case sessionRestoreFailed
    case encryptionError(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Matrix client not initialized"
        case .notLoggedIn:
            return "Not logged in to Matrix"
        case .loginFailed(let reason):
            return "Login failed: \(reason)"
        case .roomNotFound(let roomId):
            return "Room not found: \(roomId)"
        case .sendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .sdkError(let reason):
            return "SDK error: \(reason)"
        case .sessionRestoreFailed:
            return "Failed to restore session"
        case .encryptionError(let reason):
            return "Encryption error: \(reason)"
        }
    }
}

// MARK: - Matrix Service Implementation

/// Main Matrix service implementation using MatrixRustSDK
@MainActor
@Observable
final class MatrixService: MatrixServiceProtocol {

    // MARK: - Singleton

    static let shared = MatrixService()

    // MARK: - Published State

    private(set) var connectionState: MatrixConnectionState = .disconnected
    private let connectionStateSubject = CurrentValueSubject<MatrixConnectionState, Never>(.disconnected)

    var connectionStatePublisher: AnyPublisher<MatrixConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    private(set) var userId: String?

    /// Current device ID for this Matrix session
    var currentDeviceId: String {
        getOrCreateDeviceId()
    }

    // MARK: - Internal Properties (accessible from extensions)

    /// Matrix client instance (from MatrixRustSDK)
    var client: Client?

    /// Sync service for background updates
    var syncService: SyncService?

    /// Room list service for efficient room updates
    var roomListService: RoomListService?

    /// Keep room list objects alive to prevent crash (Issue #4774)
    /// These must be stored as properties, not local variables
    var roomListEntriesStreamHandle: TaskHandle?
    var roomList: RoomList?
    var roomListController: RoomListDynamicEntriesControllerProtocol?

    /// Room list service state observation (for waiting for Running state)
    var roomListStateHandle: TaskHandle?
    var currentRoomListState: RoomListServiceState = .initial

    /// Sync service state observation (for debugging)
    var syncServiceStateHandle: TaskHandle?
    var currentSyncServiceState: SyncServiceState = .idle

    /// Session storage path
    var sessionPath: String?

    /// Homeserver URL
    var homeserverURL: String?

    /// Room cache
    var roomCache: [String: MatrixRoom] = [:]

    /// Timeline listeners cache (room_id -> listener)
    var timelineListeners: [String: TaskHandle] = [:]
    var roomTimelines: [String: Timeline] = [:]

    /// De-duplication cache for timeline events (roomId -> eventIds)
    var seenTimelineEventIdsByRoom: [String: Set<String>] = [:]

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Message callbacks
    var onMessageReceived: ((MatrixMessage) -> Void)?
    var onRoomUpdated: ((MatrixRoom) -> Void)?
    var onTypingIndicator: ((String, [String]) -> Void)?  // roomId, userIds

    // MARK: - Initialization

    private init() {
        #if DEBUG
        print("[MatrixService] Initialized")
        #endif
    }

    // MARK: - Client Lifecycle

    func initialize(homeserverURL: String, sessionPath: String) async throws {
        #if DEBUG
        print("[MatrixService] Initializing with homeserver: \(homeserverURL)")
        #endif

        self.homeserverURL = homeserverURL
        self.sessionPath = sessionPath

        updateConnectionState(.connecting)

        do {
            // Ensure session directory exists
            let sessionURL = URL(fileURLWithPath: sessionPath)
            try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)

            // Create separate cache path
            let cachePath = sessionPath + "/cache"
            let cacheURL = URL(fileURLWithPath: cachePath)
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)

            // Create session delegate for token refresh handling
            let delegate = MatrixSessionDelegateImpl(matrixService: self)
            self.sessionDelegate = delegate

            // Build client using ClientBuilder
            // - setSessionDelegate: enables automatic token refresh with persistence
            // - Token refresh is enabled by default (don't call disableAutomaticTokenRefresh)
            // - slidingSyncVersionBuilder: use discoverNative to auto-detect server support
            // NOTE: RoomListService requires sliding sync. Server must have it properly configured.
            // If rooms don't sync, check matrix.staging.gcp.icered.com sliding sync configuration.
            let clientBuilder = ClientBuilder()
                .homeserverUrl(url: homeserverURL)
                .sessionPaths(dataPath: sessionPath, cachePath: cachePath)
                .userAgent(userAgent: "NovaSocial-iOS/1.0")
                .setSessionDelegate(sessionDelegate: delegate)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)

            self.client = try await clientBuilder.build()

            #if DEBUG
            print("[MatrixService] Client built with session delegate for token refresh")
            print("[MatrixService] Client configured with discoverNative sliding sync")
            #endif

            // Check available sliding sync versions for diagnostics
            #if DEBUG
            Task {
                if let client = self.client {
                    let availableVersions = await client.availableSlidingSyncVersions()
                    print("[MatrixService] 🔍 Available sliding sync versions: \(availableVersions)")
                    let currentVersion = client.slidingSyncVersion()
                    print("[MatrixService] 🔍 Current sliding sync version: \(currentVersion)")
                }
            }
            #endif

            updateConnectionState(.disconnected)

            #if DEBUG
            print("[MatrixService] Client initialized successfully")
            #endif
        } catch {
            updateConnectionState(.error(error.localizedDescription))
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func login(novaUserId: String, accessToken: String, deviceId providedDeviceId: String? = nil) async throws {
        #if DEBUG
        print("[MatrixService] 🔐 login() called with:")
        print("[MatrixService]   - novaUserId: \(novaUserId)")
        print("[MatrixService]   - accessToken length: \(accessToken.count) chars")
        print("[MatrixService]   - accessToken prefix: \(String(accessToken.prefix(20)))...")
        print("[MatrixService]   - providedDeviceId: \(providedDeviceId ?? "nil")")
        #endif

        guard let client = client else {
            #if DEBUG
            print("[MatrixService] ❌ Client not initialized!")
            #endif
            throw MatrixError.notInitialized
        }

        updateConnectionState(.connecting)

        // Use provided Matrix user ID directly (if it's already in Matrix format @xxx:server)
        // Otherwise convert from Nova user ID
        let matrixUserId: String
        if novaUserId.hasPrefix("@") && novaUserId.contains(":") {
            matrixUserId = novaUserId  // Already in Matrix format
        } else {
            matrixUserId = convertToMatrixUserId(novaUserId: novaUserId)
        }

        do {
            // Use provided device ID or get/create one
            let deviceId = providedDeviceId ?? getOrCreateDeviceId()

            // Determine the best sliding sync version to use
            // The client was built with .discoverNative, so it should know what's available
            let detectedSlidingSyncVersion = client.slidingSyncVersion()

            #if DEBUG
            print("[MatrixService] Session parameters:")
            print("[MatrixService]   - Matrix User ID: \(matrixUserId)")
            print("[MatrixService]   - Device ID: \(deviceId)")
            print("[MatrixService]   - Homeserver URL: \(homeserverURL ?? "NOT SET!")")
            print("[MatrixService]   - Sliding Sync: \(detectedSlidingSyncVersion)")

            // Also check available versions for debugging
            let availableVersions = await client.availableSlidingSyncVersions()
            print("[MatrixService]   - Available sliding sync versions: \(availableVersions)")
            #endif

            // Restore session with access token
            // Use the detected sliding sync version from the client builder discovery
            let session = Session(
                accessToken: accessToken,
                refreshToken: nil,
                userId: matrixUserId,
                deviceId: deviceId,
                homeserverUrl: homeserverURL ?? "",
                oidcData: nil,
                slidingSyncVersion: detectedSlidingSyncVersion
            )

            #if DEBUG
            print("[MatrixService] 🔄 Calling client.restoreSession()...")
            #endif

            try await client.restoreSession(session: session)

            #if DEBUG
            print("[MatrixService] ✅ client.restoreSession() succeeded")
            #endif

            self.userId = matrixUserId

            // Store session for later restoration
            storeSessionCredentials(
                userId: matrixUserId,
                accessToken: accessToken,
                deviceId: deviceId
            )

            updateConnectionState(.connected)

            #if DEBUG
            print("[MatrixService] ✅ Logged in as: \(matrixUserId)")
            #endif
        } catch {
            #if DEBUG
            print("[MatrixService] ❌ login failed: \(error)")
            print("[MatrixService]   Error type: \(type(of: error))")
            print("[MatrixService]   Error description: \(error.localizedDescription)")
            #endif
            updateConnectionState(.error(error.localizedDescription))
            throw MatrixError.loginFailed(error.localizedDescription)
        }
    }

    func loginWithPassword(username: String, password: String) async throws {
        #if DEBUG
        print("[MatrixService] Logging in with password: \(username)")
        #endif

        guard let client = client else {
            throw MatrixError.notInitialized
        }

        updateConnectionState(.connecting)

        do {
            try await client.login(
                username: username,
                password: password,
                initialDeviceName: UIDevice.current.name,
                deviceId: nil
            )

            self.userId = try client.userId()

            // Store session credentials
            if let session = try? client.session() {
                storeSessionCredentials(
                    userId: session.userId,
                    accessToken: session.accessToken,
                    deviceId: session.deviceId
                )
            }

            updateConnectionState(.connected)

            #if DEBUG
            print("[MatrixService] Logged in as: \(userId ?? "unknown")")
            #endif
        } catch {
            updateConnectionState(.error(error.localizedDescription))
            throw MatrixError.loginFailed(error.localizedDescription)
        }
    }

    func restoreSession() async throws -> Bool {
        #if DEBUG
        print("[MatrixService] Attempting to restore session")
        #endif

        guard let client = client else {
            throw MatrixError.notInitialized
        }

        // Check for stored credentials
        guard let credentials = loadSessionCredentials() else {
            #if DEBUG
            print("[MatrixService] No stored credentials found")
            #endif
            return false
        }

        do {
            // Use the detected sliding sync version from client discovery
            let detectedSlidingSyncVersion = client.slidingSyncVersion()

            #if DEBUG
            print("[MatrixService] Restoring session with sliding sync version: \(detectedSlidingSyncVersion)")
            #endif

            // Include refresh token if available for automatic token refresh
            let session = Session(
                accessToken: credentials.accessToken,
                refreshToken: credentials.refreshToken,
                userId: credentials.userId,
                deviceId: credentials.deviceId,
                homeserverUrl: credentials.homeserverUrl ?? homeserverURL ?? "",
                oidcData: nil,
                slidingSyncVersion: detectedSlidingSyncVersion
            )

            try await client.restoreSession(session: session)

            self.userId = credentials.userId
            updateConnectionState(.connected)

            #if DEBUG
            print("[MatrixService] Session restored for: \(credentials.userId)")
            print("[MatrixService] Refresh token available: \(credentials.refreshToken != nil)")
            #endif

            return true
        } catch {
            #if DEBUG
            print("[MatrixService] Session restore failed: \(error)")
            #endif
            clearSessionCredentials()
            return false
        }
    }

    func logout() async throws {
        #if DEBUG
        print("[MatrixService] Logging out")
        #endif

        // Stop sync properly and wait for cleanup
        await stopSyncAndWait()

        if let client = client {
            do {
                try await client.logout()
            } catch {
                #if DEBUG
                print("[MatrixService] Logout error: \(error)")
                #endif
            }
        }

        clearSessionCredentials()
        self.userId = nil
        self.client = nil
        roomCache.removeAll()
        updateConnectionState(.disconnected)

        #if DEBUG
        print("[MatrixService] Logged out")
        #endif
    }

    func clearCredentials() {
        #if DEBUG
        print("[MatrixService] Clearing stored credentials for session recovery")
        #endif
        clearSessionCredentials()
    }

    /// Stop sync and wait for cleanup to complete
    /// Use this instead of stopSync() when you need to ensure cleanup is done before continuing
    private func stopSyncAndWait() async {
        #if DEBUG
        print("[MatrixService] Stopping sync and waiting for cleanup")
        #endif

        // Cancel all timeline listeners first
        for (_, handle) in timelineListeners {
            handle.cancel()
        }
        timelineListeners.removeAll()
        roomTimelines.removeAll()
        seenTimelineEventIdsByRoom.removeAll()

        // Cancel room list stream handle and clear references (Issue #4774)
        roomListEntriesStreamHandle?.cancel()
        roomListEntriesStreamHandle = nil
        roomListStateHandle?.cancel()
        roomListStateHandle = nil
        syncServiceStateHandle?.cancel()
        syncServiceStateHandle = nil
        roomListController = nil
        roomList = nil

        // Stop sync service (but DON'T set to nil - causes Rust SDK panic on dealloc)
        try? await syncService?.stop()

        // Small delay to ensure Rust cleanup completes
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Clear room list service (must be after sync is stopped)
        roomListService = nil

        // NOTE: We intentionally do NOT set syncService = nil here
        // The Matrix Rust SDK's SyncService destructor can panic if deallocated
        // while tokio runtime still has active operations.
        // The syncService will be reused on next startSync() call.

        if connectionState == .syncing {
            updateConnectionState(.connected)
        }

        #if DEBUG
        print("[MatrixService] Sync stopped and cleaned up")
        #endif
    }

    // MARK: - Sync

    func startSync() async throws {
        #if DEBUG
        print("[MatrixService] Starting sync")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // Log sliding sync diagnostics before starting
        #if DEBUG
        let currentSlidingSyncVersion = client.slidingSyncVersion()
        print("[MatrixService] 📊 Current sliding sync version: \(currentSlidingSyncVersion)")

        let availableVersions = await client.availableSlidingSyncVersions()
        print("[MatrixService] 📊 Available sliding sync versions: \(availableVersions)")

        // Check for potential issues
        if availableVersions.isEmpty || availableVersions.contains(.none) && !availableVersions.contains(.native) {
            print("[MatrixService] ⚠️ Warning: Server may not support sliding sync - rooms may not sync properly")
        }
        #endif

        // If sync service already exists and is running, just return
        // Avoid recreating sync service as it causes Rust SDK panic on dealloc
        if syncService != nil {
            #if DEBUG
            print("[MatrixService] Sync service already exists, reusing existing sync")
            #endif
            // Make sure it's started
            if connectionState != .syncing {
                try? await syncService?.start()
                updateConnectionState(.syncing)
            }
            return
        }

        updateConnectionState(.syncing)

        do {
            // Create sync service
            let syncServiceBuilder = client.syncService()
            self.syncService = try await syncServiceBuilder
                .withCrossProcessLock()
                .finish()

            // Start sync
            try await syncService?.start()

            // Monitor sync service state for debugging
            setupSyncServiceStateObserver()

            // Room list service and observer for real-time room updates
            self.roomListService = syncService?.roomListService()
            setupRoomListObserver()

            #if DEBUG
            print("[MatrixService] Sync started successfully (room list observer enabled)")
            #endif

            // Auto-accept pending DM invites after a delay to ensure SDK is ready
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await self.acceptPendingDMInvites()
            }
        } catch {
            updateConnectionState(.error(error.localizedDescription))
            throw MatrixError.syncFailed(error.localizedDescription)
        }
    }

    /// Scan all rooms and auto-accept any pending DM invites
    @MainActor
    func acceptPendingDMInvites() async {
        guard let client = client else { return }

        #if DEBUG
        print("[MatrixService] Scanning for pending DM invites...")
        #endif

        let rooms = client.rooms()
        var acceptedCount = 0

        #if DEBUG
        print("[MatrixService] Total rooms from client: \(rooms.count)")
        #endif

        for room in rooms {
            do {
                let info = try await room.roomInfo()
                let roomId = room.id()

                #if DEBUG
                // Debug: print room state info
                print("[MatrixService] Room \(roomId): membership=\(info.membership), isDirect=\(info.isDirect)")
                #endif

                // Check if this is an invited DM room
                if info.membership == .invited && info.isDirect {
                    #if DEBUG
                    print("[MatrixService] Found pending DM invite: \(roomId)")
                    #endif

                    do {
                        _ = try await joinRoom(roomIdOrAlias: roomId)
                        acceptedCount += 1
                        #if DEBUG
                        print("[MatrixService] ✅ Accepted pending DM invite: \(roomId)")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[MatrixService] ❌ Failed to accept invite for \(roomId): \(error)")
                        #endif
                    }
                } else if info.membership == .invited {
                    #if DEBUG
                    print("[MatrixService] ⏸️ Non-DM invite found: \(roomId), skipping auto-accept")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[MatrixService] Error getting room info: \(error)")
                #endif
                continue
            }
        }

        #if DEBUG
        print("[MatrixService] Pending DM invite scan complete. Accepted: \(acceptedCount)")
        #endif
    }

    func stopSync() {
        #if DEBUG
        print("[MatrixService] Stopping sync")
        #endif

        // Cancel all timeline listeners first
        for (_, handle) in timelineListeners {
            handle.cancel()
        }
        timelineListeners.removeAll()
        roomTimelines.removeAll()
        seenTimelineEventIdsByRoom.removeAll()

        // Cancel room list stream handle and clear references (Issue #4774)
        roomListEntriesStreamHandle?.cancel()
        roomListEntriesStreamHandle = nil
        roomListStateHandle?.cancel()
        roomListStateHandle = nil
        syncServiceStateHandle?.cancel()
        syncServiceStateHandle = nil
        roomListController = nil
        roomList = nil

        // Stop sync service and clear references in correct order
        // This is done in a Task but we ensure proper ordering within it
        Task { @MainActor in
            // 1. Stop sync service first (but DON'T set to nil - causes Rust SDK panic)
            try? await syncService?.stop()

            // 2. Small delay to ensure Rust cleanup completes
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // 3. Clear room list service (must be after sync is stopped)
            roomListService = nil

            // NOTE: We intentionally do NOT set syncService = nil here
            // The Matrix Rust SDK's SyncService destructor can panic if deallocated
            // while tokio runtime still has active operations.

            #if DEBUG
            print("[MatrixService] Sync stopped and cleaned up")
            #endif
        }

        if connectionState == .syncing {
            updateConnectionState(.connected)
        }
    }

    // MARK: - Room Operations

    func createRoom(name: String?, isDirect: Bool, inviteUserIds: [String], isEncrypted: Bool) async throws -> String {
        #if DEBUG
        print("[MatrixService] Creating room: \(name ?? "Direct"), direct=\(isDirect), members=\(inviteUserIds.count)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // Convert Nova user IDs to Matrix user IDs
        let matrixUserIds = inviteUserIds.map { convertToMatrixUserId(novaUserId: $0) }

        do {
            let request = CreateRoomParameters(
                name: name,
                topic: nil,
                isEncrypted: isEncrypted,
                isDirect: isDirect,
                visibility: .private,
                preset: isDirect ? .trustedPrivateChat : .privateChat,
                invite: matrixUserIds,
                avatar: nil,
                powerLevelContentOverride: nil
            )

            let roomId = try await client.createRoom(request: request)

            #if DEBUG
            print("[MatrixService] Created room: \(roomId)")
            #endif

            return roomId
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func joinRoom(roomIdOrAlias: String) async throws -> String {
        #if DEBUG
        print("[MatrixService] Joining room: \(roomIdOrAlias)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            let room = try await client.joinRoomByIdOrAlias(
                roomIdOrAlias: roomIdOrAlias,
                serverNames: []
            )
            return room.id()
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func leaveRoom(roomId: String) async throws {
        #if DEBUG
        print("[MatrixService] Leaving room: \(roomId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }
            try await room.leave()
            roomCache.removeValue(forKey: roomId)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    // MARK: - Messaging

    func subscribeToRoomTimeline(roomId: String) async throws {
        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        if timelineListeners[roomId] != nil {
            return
        }

        guard let room = try client.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }

        let timeline = try await room.timeline()
        roomTimelines[roomId] = timeline

        let listener = RoomTimelineListener { [weak self] diffs in
            Task { @MainActor in
                self?.handleRoomTimelineDiff(roomId: roomId, diffs: diffs)
            }
        }

        let handle = await timeline.addListener(listener: listener)
        timelineListeners[roomId] = handle
    }

    func unsubscribeFromRoomTimeline(roomId: String) {
        if let handle = timelineListeners.removeValue(forKey: roomId) {
            handle.cancel()
        }
        roomTimelines.removeValue(forKey: roomId)
        seenTimelineEventIdsByRoom.removeValue(forKey: roomId)
    }

    func handleRoomTimelineDiff(roomId: String, diffs: [TimelineDiff]) {
        for diff in diffs {
            switch diff {
            case .append(let values):
                for item in values {
                    emitTimelineItem(item, roomId: roomId)
                }
            case .pushBack(let value):
                emitTimelineItem(value, roomId: roomId)
            case .pushFront(let value):
                emitTimelineItem(value, roomId: roomId)
            case .set(_, let value):
                emitTimelineItem(value, roomId: roomId)
            default:
                break
            }
        }
    }

    func emitTimelineItem(_ item: TimelineItem, roomId: String) {
        guard let message = convertTimelineItemToMessage(item, roomId: roomId) else { return }

        var seen = seenTimelineEventIdsByRoom[roomId] ?? Set()
        guard !seen.contains(message.id) else { return }
        seen.insert(message.id)
        seenTimelineEventIdsByRoom[roomId] = seen

        onMessageReceived?(message)
    }

    func sendMessage(roomId: String, content: String) async throws -> String {
        #if DEBUG
        print("[MatrixService] Sending message to room: \(roomId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Create text message content
            let messageContent = messageEventContentFromMarkdown(md: content)

            // Send message
            try await timeline.send(msg: messageContent)

            // The event ID will be returned asynchronously via timeline updates
            // For now, generate a local event ID
            let localEventId = "$local.\(UUID().uuidString)"

            #if DEBUG
            print("[MatrixService] Message sent: \(localEventId)")
            #endif

            return localEventId
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sendFailed(error.localizedDescription)
        }
    }

    func sendMedia(roomId: String, mediaURL: URL, mimeType: String, caption: String?) async throws -> String {
        #if DEBUG
        print("[MatrixService] Sending media to room: \(roomId), type: \(mimeType)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Read file data
            let data = try Data(contentsOf: mediaURL)
            _ = mediaURL.lastPathComponent  // Filename available for future use

            // Create upload parameters
            let uploadParams = UploadParameters(
                source: .file(filename: mediaURL.path),
                caption: caption,
                formattedCaption: nil,
                mentions: nil,
                inReplyTo: nil
            )

            // Determine media type and create appropriate content
            if mimeType.hasPrefix("image/") {
                // Send as image
                _ = try timeline.sendImage(
                    params: uploadParams,
                    thumbnailSource: nil,
                    imageInfo: ImageInfo(
                        height: nil,
                        width: nil,
                        mimetype: mimeType,
                        size: UInt64(data.count),
                        thumbnailInfo: nil,
                        thumbnailSource: nil,
                        blurhash: nil,
                        isAnimated: nil
                    )
                )
            } else if mimeType.hasPrefix("video/") {
                // Send as video
                _ = try timeline.sendVideo(
                    params: uploadParams,
                    thumbnailSource: nil,
                    videoInfo: VideoInfo(
                        duration: nil,
                        height: nil,
                        width: nil,
                        mimetype: mimeType,
                        size: UInt64(data.count),
                        thumbnailInfo: nil,
                        thumbnailSource: nil,
                        blurhash: nil
                    )
                )
            } else if mimeType.hasPrefix("audio/") {
                // Send as audio
                _ = try timeline.sendAudio(
                    params: uploadParams,
                    audioInfo: AudioInfo(
                        duration: nil,
                        size: UInt64(data.count),
                        mimetype: mimeType
                    )
                )
            } else {
                // Send as file
                _ = try timeline.sendFile(
                    params: uploadParams,
                    fileInfo: FileInfo(
                        mimetype: mimeType,
                        size: UInt64(data.count),
                        thumbnailInfo: nil,
                        thumbnailSource: nil
                    )
                )
            }

            let localEventId = "$local.\(UUID().uuidString)"

            #if DEBUG
            print("[MatrixService] Media sent: \(localEventId)")
            #endif

            return localEventId
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sendFailed(error.localizedDescription)
        }
    }

    func getRoomMessages(roomId: String, limit: Int, from: String?) async throws -> [MatrixMessage] {
        #if DEBUG
        print("[MatrixService] Getting messages for room: \(roomId), limit: \(limit)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Paginate backwards to load history
            try await timeline.paginateBackwards(numEvents: UInt16(limit))

            // Use a listener to collect timeline items
            let items = await withCheckedContinuation { (continuation: CheckedContinuation<[TimelineItem], Never>) in
                let listener = TimelineItemCollector { collectedItems in
                    continuation.resume(returning: collectedItems)
                }
                Task {
                    _ = await timeline.addListener(listener: listener)
                }
            }

            // Convert to MatrixMessage
            return items.compactMap { item -> MatrixMessage? in
                convertTimelineItemToMessage(item, roomId: roomId)
            }
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    // MARK: - Room Management

    func inviteUser(roomId: String, userId: String) async throws {
        #if DEBUG
        print("[MatrixService] Inviting user \(userId) to room \(roomId)")
        #endif

        guard let client = client, self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        let matrixUserId = convertToMatrixUserId(novaUserId: userId)

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }
            try await room.inviteUserById(userId: matrixUserId)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func kickUser(roomId: String, userId: String, reason: String?) async throws {
        #if DEBUG
        print("[MatrixService] Kicking user \(userId) from room \(roomId)")
        #endif

        guard let client = client, self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        let matrixUserId = convertToMatrixUserId(novaUserId: userId)

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }
            try await room.kickUser(userId: matrixUserId, reason: reason)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func updatePowerLevel(roomId: String, userId: String, powerLevel: Int) async throws {
        #if DEBUG
        print("[MatrixService] Updating power level for user \(userId) to \(powerLevel) in room \(roomId)")
        #endif

        guard let client = client, self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        let matrixUserId = convertToMatrixUserId(novaUserId: userId)

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let update = UserPowerLevelUpdate(
                userId: matrixUserId,
                powerLevel: Int64(powerLevel)
            )

            try await room.updatePowerLevelsForUsers(updates: [update])

            #if DEBUG
            print("[MatrixService] ✅ Power level updated successfully")
            #endif
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func setTyping(roomId: String, isTyping: Bool) async throws {
        guard let client = client, self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }
            try await room.typingNotice(isTyping: isTyping)
        } catch {
            // Typing indicator errors are not critical
            #if DEBUG
            print("[MatrixService] Typing notice error: \(error)")
            #endif
        }
    }

    func markRoomAsRead(roomId: String) async throws {
        guard let client = client, self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()
            try await timeline.markAsRead(receiptType: .read)
        } catch {
            #if DEBUG
            print("[MatrixService] Mark as read error: \(error)")
            #endif
        }
    }

    func getRoom(roomId: String) -> MatrixRoom? {
        return roomCache[roomId]
    }

    func getJoinedRooms() async throws -> [MatrixRoom] {
        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // Update room cache from client
        let rooms = client.rooms()

        #if DEBUG
        print("[MatrixService] 📊 client.rooms() returned \(rooms.count) rooms")
        for (index, room) in rooms.enumerated() {
            let roomId = room.id()
            let membership = room.membership()
            print("[MatrixService]   [\(index)] Room: \(roomId), membership: \(membership)")
        }
        #endif

        var matrixRooms: [MatrixRoom] = []
        var skippedCount = 0
        for room in rooms {
            if let matrixRoom = await convertSDKRoomToMatrixRoom(room) {
                roomCache[matrixRoom.id] = matrixRoom
                matrixRooms.append(matrixRoom)
            } else {
                skippedCount += 1
            }
        }

        #if DEBUG
        print("[MatrixService] ✅ Converted \(matrixRooms.count) rooms, skipped \(skippedCount)")
        #endif

        return matrixRooms
    }

    func getRoomMembers(roomId: String) async throws -> [MatrixRoomMember] {
        #if DEBUG
        print("[MatrixService] Getting members for room: \(roomId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            // Get room members iterator
            let membersIterator = try await room.members()

            var matrixMembers: [MatrixRoomMember] = []

            // Iterate through all members
            while let chunk = membersIterator.nextChunk(chunkSize: 100) {
                for member in chunk {
                    // Convert membership state
                    let membershipState: MatrixMembershipState
                    switch member.membership {
                    case .join: membershipState = .join
                    case .invite: membershipState = .invite
                    case .leave: membershipState = .leave
                    case .ban: membershipState = .ban
                    case .knock: membershipState = .knock
                    @unknown default: membershipState = .leave
                    }

                    // Only include joined members
                    guard membershipState == .join else { continue }

                    // Extract power level value from enum
                    let powerLevelInt: Int
                    switch member.powerLevel {
                    case .infinite:
                        powerLevelInt = Int.max
                    case .value(let value):
                        powerLevelInt = Int(value)
                    }
                    let matrixMember = MatrixRoomMember(
                        id: member.userId,
                        userId: member.userId,
                        displayName: member.displayName,
                        avatarUrl: member.avatarUrl,
                        powerLevel: powerLevelInt,
                        isAdmin: powerLevelInt >= 50,
                        membership: membershipState
                    )
                    matrixMembers.append(matrixMember)
                }
            }

            #if DEBUG
            print("[MatrixService] Found \(matrixMembers.count) members in room")
            #endif

            return matrixMembers
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    // MARK: - Message Edit/Delete/Reactions

    func editMessage(roomId: String, eventId: String, newContent: String) async throws {
        #if DEBUG
        print("[MatrixService] Editing message \(eventId) in room \(roomId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Create edited content
            let content = messageEventContentFromMarkdown(md: newContent)
            let editedContent = EditedContent.roomMessage(content: content)

            // Edit the message
            try await timeline.edit(
                eventOrTransactionId: .eventId(eventId: eventId),
                newContent: editedContent
            )

            #if DEBUG
            print("[MatrixService] Message edited successfully")
            #endif
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sendFailed("Edit failed: \(error.localizedDescription)")
        }
    }

    func redactMessage(roomId: String, eventId: String, reason: String?) async throws {
        #if DEBUG
        print("[MatrixService] Redacting message \(eventId) in room \(roomId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Redact the message
            try await timeline.redactEvent(
                eventOrTransactionId: .eventId(eventId: eventId),
                reason: reason
            )

            #if DEBUG
            print("[MatrixService] Message redacted successfully")
            #endif
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sendFailed("Redact failed: \(error.localizedDescription)")
        }
    }

    func toggleReaction(roomId: String, eventId: String, emoji: String) async throws {
        #if DEBUG
        print("[MatrixService] Toggling reaction \(emoji) on message \(eventId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = try client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Toggle reaction (add if not present, remove if present)
            try await timeline.toggleReaction(
                itemId: .eventId(eventId: eventId),
                key: emoji
            )

            #if DEBUG
            print("[MatrixService] Reaction toggled successfully")
            #endif
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.sendFailed("Toggle reaction failed: \(error.localizedDescription)")
        }
    }

    func sendReaction(roomId: String, eventId: String, emoji: String) async throws {
        #if DEBUG
        print("[MatrixService] Sending reaction \(emoji) on message \(eventId)")
        #endif

        // Matrix SDK uses toggleReaction - if reaction doesn't exist it will be added
        // This is the same as sending a new reaction
        try await toggleReaction(roomId: roomId, eventId: eventId, emoji: emoji)

        #if DEBUG
        print("[MatrixService] Reaction sent successfully (via toggleReaction)")
        #endif
    }

    func getReactions(roomId: String, eventId: String) async throws -> [MatrixReaction] {
        #if DEBUG
        print("[MatrixService] Getting reactions for message \(eventId)")
        #endif

        guard client != nil, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // Note: Matrix SDK provides reactions via timeline event relations
        // Reactions will be parsed from timeline events when received
        #if DEBUG
        print("[MatrixService] Note: Reactions are retrieved via timeline events")
        #endif

        return []
    }

    // MARK: - Helper Methods (internal for extension access)

    /// Convert Nova user ID (UUID) to Matrix user ID format
    /// Nova UUID: "b19b767d-59e5-4122-8388-a51670705ce6" -> Matrix: @nova-b19b767d-59e5-4122-8388-a51670705ce6:staging.gcp.icered.com
    /// If already Matrix format (@nova-...), returns as-is
    func convertToMatrixUserId(novaUserId: String) -> String {
        // If already in Matrix format, return as-is
        if novaUserId.hasPrefix("@nova-") {
            return novaUserId
        }

        // Extract domain from homeserver URL
        let domain = homeserverURL?
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first
            .map(String.init) ?? "staging.gcp.icered.com"

        // Extract just the domain name for Matrix server (remove "matrix." prefix if present)
        let serverName = domain.hasPrefix("matrix.") ? String(domain.dropFirst(7)) : domain

        // Convert to Matrix format: @nova-<uuid>:server (matches backend format)
        return "@nova-\(novaUserId):\(serverName)"
    }

    /// Convert Matrix user ID back to Nova user ID
    /// Matrix: @nova-<uuid>:server -> Nova: uuid-string
    func convertToNovaUserId(matrixUserId: String) -> String? {
        // Format: @nova-<uuid>:server
        guard matrixUserId.hasPrefix("@nova-") else {
            return nil
        }

        // Extract UUID portion
        let withoutPrefix = matrixUserId.dropFirst(6)  // Remove "@nova-"
        guard let colonIndex = withoutPrefix.firstIndex(of: ":") else {
            return nil
        }

        return String(withoutPrefix.prefix(upTo: colonIndex))
    }

    func updateConnectionState(_ state: MatrixConnectionState) {
        self.connectionState = state
        connectionStateSubject.send(state)
    }

    // MARK: - Sync Service State Observer

    private func setupSyncServiceStateObserver() {
        guard let syncService = syncService else { return }

        let observer = SyncServiceStateObserverImpl { [weak self] state in
            guard let self = self else { return }

            Task { @MainActor in
                self.currentSyncServiceState = state

                #if DEBUG
                print("[MatrixService] 🔄 SyncService state changed: \(state)")
                #endif

                // Log additional info based on state
                switch state {
                case .idle:
                    print("[MatrixService]   → SyncService is idle")
                case .running:
                    print("[MatrixService]   → SyncService is running")
                case .terminated:
                    print("[MatrixService]   ⚠️ SyncService terminated")
                case .error:
                    print("[MatrixService]   ❌ SyncService encountered an error")
                @unknown default:
                    print("[MatrixService]   → SyncService in unknown state: \(state)")
                }
            }
        }

        self.syncServiceStateHandle = syncService.state(listener: observer)
    }

    // MARK: - Room List Observer

    private func setupRoomListObserver() {
        guard let roomListService = roomListService else { return }

        Task {
            // Subscribe to room list service state to wait for Running state
            // This is more reliable than arbitrary delays
            #if DEBUG
            print("[MatrixService] 🔄 Setting up room list state observer...")
            #endif

            await waitForRoomListServiceRunning(roomListService: roomListService)

            // Double-check that sync service is still active
            guard self.syncService != nil, self.roomListService != nil else {
                #if DEBUG
                print("[MatrixService] Room list observer setup skipped - sync service no longer active")
                #endif
                return
            }

            // Check if sliding sync failed - fall back to client.rooms() if so
            if self.currentRoomListState == .terminated || self.currentRoomListState == .error {
                #if DEBUG
                print("[MatrixService] ⚠️ Sliding sync failed, falling back to client.rooms()...")
                #endif
                await self.populateRoomsFromClientFallback()
            }

            await setupRoomListObserverWithRetry(roomListService: roomListService, attempt: 1)
        }
    }

    /// Wait for RoomListService to reach the Running state
    /// This ensures sliding sync has fully initialized before we try to get rooms
    private func waitForRoomListServiceRunning(roomListService: RoomListService) async {
        // Create a continuation to wait for the Running state
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hasResumed = false

            let listener = RoomListServiceStateListenerImpl { [weak self] state in
                guard let self = self else { return }

                Task { @MainActor in
                    self.currentRoomListState = state

                    #if DEBUG
                    print("[MatrixService] 📊 RoomListService state changed: \(state)")
                    #endif

                    // Resume when we reach Running state (or Error/Terminated as fallback)
                    if !hasResumed {
                        switch state {
                        case .running:
                            hasResumed = true
                            #if DEBUG
                            print("[MatrixService] ✅ RoomListService reached Running state - proceeding with room list setup")
                            #endif
                            continuation.resume()
                        case .error, .terminated:
                            hasResumed = true
                            #if DEBUG
                            print("[MatrixService] ⚠️ RoomListService reached \(state) state - proceeding anyway")
                            #endif
                            continuation.resume()
                        case .initial, .settingUp, .recovering:
                            // Still waiting...
                            break
                        }
                    }
                }
            }

            // Store the state handle to keep it alive
            self.roomListStateHandle = roomListService.state(listener: listener)

            // Also add a timeout in case the state never reaches Running
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds max
                if !hasResumed {
                    hasResumed = true
                    #if DEBUG
                    print("[MatrixService] ⏱️ RoomListService state wait timed out after 30s - proceeding anyway")
                    #endif
                    continuation.resume()
                }
            }
        }
    }

    /// Fallback method to populate rooms when sliding sync fails
    /// Uses client.rooms() directly instead of RoomListService
    private func populateRoomsFromClientFallback() async {
        guard let client = client else {
            #if DEBUG
            print("[MatrixService] ❌ Cannot populate rooms - client is nil")
            #endif
            return
        }

        let rooms = client.rooms()

        #if DEBUG
        print("[MatrixService] 📊 Fallback: client.rooms() returned \(rooms.count) rooms")
        #endif

        for room in rooms {
            #if DEBUG
            let roomId = room.id()
            let membership = room.membership()
            print("[MatrixService]   - Fallback room: \(roomId), membership: \(membership)")
            #endif

            // Check for invited DM rooms and auto-accept
            await autoAcceptInviteIfNeeded(room)

            if let matrixRoom = await convertSDKRoomToMatrixRoom(room) {
                roomCache[room.id()] = matrixRoom
                onRoomUpdated?(matrixRoom)
            }
        }

        #if DEBUG
        print("[MatrixService] ✅ Fallback: Populated \(roomCache.count) rooms in cache")
        #endif
    }

    private func setupRoomListObserverWithRetry(roomListService: RoomListService, attempt: Int) async {
        let maxAttempts = 5  // Increased from 3 to 5 attempts

        // Safety check: verify we're still in a valid state
        guard self.client != nil, self.syncService != nil else {
            #if DEBUG
            print("[MatrixService] Room list observer setup aborted - client or sync service is nil")
            #endif
            return
        }

        do {
            #if DEBUG
            print("[MatrixService] Setting up room list observer (attempt \(attempt)/\(maxAttempts))")
            #endif

            // CRITICAL: Store roomList as property to prevent deallocation (Issue #4774)
            // If stored as local variable, SDK crashes with EXC_BAD_ACCESS
            self.roomList = try await roomListService.allRooms()

            guard let roomList = self.roomList else {
                #if DEBUG
                print("[MatrixService] ❌ Failed to get room list")
                #endif
                return
            }

            // Subscribe to room list updates using new API
            let listener = RoomListEntriesListenerImpl { [weak self] updates in
                Task { @MainActor in
                    await self?.handleRoomListUpdates(updates)
                }
            }

            // Use new entriesWithDynamicAdapters method
            let result = roomList.entriesWithDynamicAdapters(pageSize: 100, listener: listener)

            // CRITICAL: Store handles as properties to prevent deallocation (Issue #4774)
            // The SDK crashes if these objects go out of scope while streams are active
            self.roomListEntriesStreamHandle = result.entriesStream()
            self.roomListController = result.controller()

            // Set filter to include both joined rooms AND invited rooms
            // This is critical for auto-accepting DM invites
            let filterSet = self.roomListController?.setFilter(kind: .any(filters: [.joined, .invite])) ?? false
            #if DEBUG
            print("[MatrixService] ✅ Room list filter set (joined + invite): \(filterSet)")
            #endif
        } catch {
            #if DEBUG
            print("[MatrixService] ❌ Room list observer error (attempt \(attempt)): \(error)")
            #endif

            // Retry with exponential backoff if we haven't exceeded max attempts
            if attempt < maxAttempts {
                // Longer delays: 2s, 4s, 8s, 16s
                let delaySeconds = UInt64(pow(2.0, Double(attempt)))
                let delayNs = delaySeconds * 1_000_000_000
                #if DEBUG
                print("[MatrixService] Retrying room list observer setup in \(delaySeconds)s...")
                #endif
                try? await Task.sleep(nanoseconds: delayNs)

                // Re-check state before retry
                guard self.syncService != nil, self.roomListService != nil else {
                    #if DEBUG
                    print("[MatrixService] Room list retry skipped - services no longer active")
                    #endif
                    return
                }

                await setupRoomListObserverWithRetry(roomListService: roomListService, attempt: attempt + 1)
            } else {
                #if DEBUG
                print("[MatrixService] ⚠️ Room list observer setup failed after \(maxAttempts) attempts. Falling back to client.rooms().")
                #endif
                // Fall back to client.rooms() to at least populate the room cache
                await populateRoomsFromClientFallback()
            }
        }
    }

    private func handleRoomListUpdates(_ updates: [RoomListEntriesUpdate]) async {
        #if DEBUG
        print("[MatrixService] 🔄 handleRoomListUpdates called with \(updates.count) updates")
        #endif

        for update in updates {
            switch update {
            case .append(let rooms), .reset(let rooms):
                #if DEBUG
                let updateType = {
                    if case .append = update { return "append" }
                    return "reset"
                }()
                print("[MatrixService]   📥 \(updateType): \(rooms.count) rooms")
                for room in rooms {
                    print("[MatrixService]     - Room: \(room.id()), membership: \(room.membership())")
                }
                #endif

                // If reset with 0 rooms and cache is empty, try fallback
                if case .reset = update, rooms.isEmpty && roomCache.isEmpty {
                    #if DEBUG
                    print("[MatrixService] ⚠️ Received reset with 0 rooms - trying client.rooms() fallback")
                    #endif
                    await populateRoomsFromClientFallback()
                }

                for room in rooms {
                    // Check for invited DM rooms and auto-accept
                    await autoAcceptInviteIfNeeded(room)

                    if let matrixRoom = await convertSDKRoomToMatrixRoom(room) {
                        roomCache[room.id()] = matrixRoom
                        onRoomUpdated?(matrixRoom)
                    }
                }
            case .pushFront(let room), .pushBack(let room), .insert(_, let room), .set(_, let room):
                #if DEBUG
                print("[MatrixService]   📥 Single room update: \(room.id()), membership: \(room.membership())")
                #endif

                // Check for invited DM rooms and auto-accept
                await autoAcceptInviteIfNeeded(room)

                if let matrixRoom = await convertSDKRoomToMatrixRoom(room) {
                    roomCache[room.id()] = matrixRoom
                    onRoomUpdated?(matrixRoom)
                }
            case .remove(let index):
                // Handle room removal if needed
                #if DEBUG
                print("[MatrixService] Room removed at index: \(index)")
                #endif
            case .clear, .popFront, .popBack, .truncate:
                #if DEBUG
                print("[MatrixService]   ⚠️ Other update type: clear/popFront/popBack/truncate")
                #endif
                break
            }
        }

        #if DEBUG
        print("[MatrixService] 📊 After updates, roomCache has \(roomCache.count) rooms")
        #endif
    }

    /// Auto-accept room invitations for DM rooms
    private func autoAcceptInviteIfNeeded(_ room: Room) async {
        do {
            let info = try await room.roomInfo()

            // Check if this is an invited room (we haven't joined yet)
            guard info.membership == .invited else { return }

            let roomId = room.id()

            #if DEBUG
            print("[MatrixService] 🔔 Received room invite: \(roomId), isDirect: \(info.isDirect)")
            #endif

            // Auto-accept DM invites (direct messages)
            // For group rooms, we might want user confirmation, but for DMs we auto-accept
            if info.isDirect {
                #if DEBUG
                print("[MatrixService] ✅ Auto-accepting DM invite for room: \(roomId)")
                #endif

                do {
                    _ = try await joinRoom(roomIdOrAlias: roomId)
                    #if DEBUG
                    print("[MatrixService] ✅ Successfully joined DM room: \(roomId)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[MatrixService] ❌ Failed to auto-accept DM invite: \(error)")
                    #endif
                }
            } else {
                #if DEBUG
                print("[MatrixService] ⏸️ Non-DM room invite, not auto-accepting: \(roomId)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[MatrixService] Error checking room invite: \(error)")
            #endif
        }
    }

    func convertSDKRoomToMatrixRoom(_ room: Room) async -> MatrixRoom? {
        let roomId = room.id()
        let info: RoomInfo
        do {
            info = try await room.roomInfo()
        } catch {
            #if DEBUG
            print("[MatrixService] ⚠️ Failed to get roomInfo for \(roomId): \(error)")
            #endif
            return nil
        }

        let displayName = (await room.displayName()) ?? roomId

        return MatrixRoom(
            id: roomId,
            name: displayName,
            topic: info.topic,
            avatarURL: info.avatarUrl,
            isDirect: info.isDirect,
            isEncrypted: info.encryptionState == .encrypted,
            memberCount: Int(info.activeMembersCount),
            unreadCount: Int(info.numUnreadMessages),
            lastMessage: nil,  // Would need timeline access
            lastActivity: nil,
            novaConversationId: nil
        )
    }

    func convertTimelineItemToMessage(_ item: TimelineItem, roomId: String) -> MatrixMessage? {
        guard let eventItem = item.asEvent() else { return nil }

        // Extract event ID from EventOrTransactionId enum
        let eventId: String
        switch eventItem.eventOrTransactionId {
        case .eventId(let id):
            eventId = id
        case .transactionId(let id):
            eventId = id
        }

        let senderId = eventItem.sender
        let timestamp = Date(timeIntervalSince1970: Double(eventItem.timestamp) / 1000.0)

        // Extract content based on message type - new struct-based API
        let content = eventItem.content

        switch content {
        case .msgLike(let msgLikeContent):
            switch msgLikeContent.kind {
            case .message(let messageContent):
                let body = messageContent.body
                let isEdited = messageContent.isEdited
                let msgType: MatrixMessageType

                switch messageContent.msgType {
                case .text:
                    msgType = .text
                case .image:
                    msgType = .image
                case .video:
                    msgType = .video
                case .audio:
                    msgType = .audio
                case .file:
                    msgType = .file
                case .location:
                    msgType = .location
                case .notice:
                    msgType = .notice
                case .emote:
                    msgType = .emote
                case .gallery, .other:
                    msgType = .text
                }

                return MatrixMessage(
                    id: eventId,
                    roomId: roomId,
                    senderId: senderId,
                    content: body,
                    type: msgType,
                    timestamp: timestamp,
                    isEdited: isEdited,
                    replyTo: nil,
                    mediaURL: nil,
                    mediaInfo: nil
                )
            case .sticker, .poll, .redacted, .unableToDecrypt, .other:
                return nil
            }
        case .callInvite, .rtcNotification, .roomMembership, .profileChange, .state, .failedToParseMessageLike, .failedToParseState:
            return nil
        }
    }

    // MARK: - Session Storage

    private struct StoredCredentials: Codable {
        let userId: String
        let accessToken: String
        let deviceId: String
        let refreshToken: String?
        let homeserverUrl: String?

        init(userId: String, accessToken: String, deviceId: String, refreshToken: String? = nil, homeserverUrl: String? = nil) {
            self.userId = userId
            self.accessToken = accessToken
            self.deviceId = deviceId
            self.refreshToken = refreshToken
            self.homeserverUrl = homeserverUrl
        }
    }

    /// Session delegate for handling token refresh callbacks from the SDK
    private var sessionDelegate: MatrixSessionDelegateImpl?

    // Matrix session storage key for UserDefaults (not sensitive enough for Keychain)
    private static let matrixSessionKey = "matrix_session_data"

    private func storeSessionCredentials(userId: String, accessToken: String, deviceId: String, refreshToken: String? = nil, homeserverUrl: String? = nil) {
        let credentials = StoredCredentials(
            userId: userId,
            accessToken: accessToken,
            deviceId: deviceId,
            refreshToken: refreshToken,
            homeserverUrl: homeserverUrl ?? homeserverURL
        )

        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: Self.matrixSessionKey)
            #if DEBUG
            print("[MatrixService] Session credentials stored (refreshToken: \(refreshToken != nil ? "yes" : "no"))")
            #endif
        }
    }

    /// Store a full Session object (called by SDK on token refresh)
    func storeSession(_ session: Session) {
        storeSessionCredentials(
            userId: session.userId,
            accessToken: session.accessToken,
            deviceId: session.deviceId,
            refreshToken: session.refreshToken,
            homeserverUrl: session.homeserverUrl
        )
    }

    /// Load a full Session object (called by SDK to restore session)
    nonisolated func loadSession(userId: String) -> Session? {
        guard let credentials = loadSessionCredentials(),
              credentials.userId == userId,
              let homeserver = credentials.homeserverUrl else {
            return nil
        }

        return Session(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken,
            userId: credentials.userId,
            deviceId: credentials.deviceId,
            homeserverUrl: homeserver,
            oidcData: nil,
            slidingSyncVersion: .native
        )
    }

    private nonisolated func loadSessionCredentials() -> StoredCredentials? {
        guard let data = UserDefaults.standard.data(forKey: Self.matrixSessionKey),
              let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data) else {
            return nil
        }
        return credentials
    }

    private func clearSessionCredentials() {
        UserDefaults.standard.removeObject(forKey: Self.matrixSessionKey)
    }

    private func getOrCreateDeviceId() -> String {
        // Check for existing device ID
        if let credentials = loadSessionCredentials() {
            return credentials.deviceId
        }

        // Generate new device ID
        let deviceId = "NOVA_IOS_\(UUID().uuidString.prefix(8))"
        return deviceId
    }
}

// MARK: - Matrix Session Delegate
// Implements ClientSessionDelegate for automatic token refresh handling

#if MATRIX_SDK_ENABLED
/// Session delegate that handles token persistence for the Matrix SDK
/// The SDK calls this delegate when:
/// - Tokens are refreshed (saveSessionInKeychain)
/// - Session needs to be restored (retrieveSessionFromKeychain)
final class MatrixSessionDelegateImpl: ClientSessionDelegate, @unchecked Sendable {

    private weak var matrixService: MatrixService?

    init(matrixService: MatrixService) {
        self.matrixService = matrixService
    }

    /// Called by the SDK when tokens are refreshed and need to be persisted
    func saveSessionInKeychain(session: Session) {
        #if DEBUG
        print("[MatrixSessionDelegate] 🔄 Token refresh - saving new session")
        print("[MatrixSessionDelegate] User: \(session.userId)")
        print("[MatrixSessionDelegate] Has refresh token: \(session.refreshToken != nil)")
        #endif

        // Store the updated session with new tokens
        Task { @MainActor in
            matrixService?.storeSession(session)
        }
    }

    /// Called by the SDK to retrieve a stored session for a user
    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        #if DEBUG
        print("[MatrixSessionDelegate] 📥 Retrieving session for user: \(userId)")
        #endif

        // Try to load the session from our storage
        guard let session = matrixService?.loadSession(userId: userId) else {
            #if DEBUG
            print("[MatrixSessionDelegate] ❌ No stored session found for user: \(userId)")
            #endif
            // Throw an error that the SDK will handle
            throw MatrixError.sessionRestoreFailed
        }

        #if DEBUG
        print("[MatrixSessionDelegate] ✅ Session retrieved successfully")
        #endif

        return session
    }
}
#endif

// MARK: - Room List Entries Listener

private final class RoomListEntriesListenerImpl: RoomListEntriesListener, @unchecked Sendable {
    private let handler: ([RoomListEntriesUpdate]) -> Void

    init(handler: @escaping ([RoomListEntriesUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        handler(roomEntriesUpdate)
    }
}

// MARK: - Room List Service State Listener

private final class RoomListServiceStateListenerImpl: RoomListServiceStateListener, @unchecked Sendable {
    private let handler: (RoomListServiceState) -> Void

    init(handler: @escaping (RoomListServiceState) -> Void) {
        self.handler = handler
    }

    func onUpdate(state: RoomListServiceState) {
        handler(state)
    }
}

// MARK: - Sync Service State Observer

private final class SyncServiceStateObserverImpl: SyncServiceStateObserver, @unchecked Sendable {
    private let handler: (SyncServiceState) -> Void

    init(handler: @escaping (SyncServiceState) -> Void) {
        self.handler = handler
    }

    func onUpdate(state: SyncServiceState) {
        handler(state)
    }
}

// MARK: - Matrix Configuration

struct MatrixConfiguration {
    /// Nova staging Matrix homeserver URL
    /// Note: Updated to use public domain (matrix.staging.gcp.icered.com) for SSO flow
    /// Server name: staging.gcp.icered.com
    static let stagingHomeserver = "https://matrix.staging.gcp.icered.com"

    /// Nova production Matrix homeserver URL
    static let productionHomeserver = "https://matrix.nova.app"

    /// Sliding sync proxy URL (if using)
    static let slidingSyncProxy: String? = nil

    /// Session storage directory
    static var sessionPath: String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let matrixPath = documentsPath.appendingPathComponent("matrix_session", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: matrixPath, withIntermediateDirectories: true)

        return matrixPath.path
    }

    /// Get homeserver URL based on environment
    static var homeserverURL: String {
        switch APIConfig.current {
        case .development, .staging:
            return stagingHomeserver
        case .production:
            return productionHomeserver
        }
    }

    /// Staging SSO callback URL
    static let stagingCallbackURL = "nova-staging://matrix-sso-callback"

    /// Production SSO callback URL
    static let productionCallbackURL = "nova://matrix-sso-callback"

    /// SSO callback URL based on environment
    static var ssoCallbackURL: String {
        switch APIConfig.current {
        case .development, .staging:
            return stagingCallbackURL
        case .production:
            return productionCallbackURL
        }
    }
}
