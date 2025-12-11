import Foundation
import Combine

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
//
// NOTE: This file provides the interface. The actual MatrixRustSDK import
// is conditional on the package being added to the project.

// MARK: - Matrix Service Protocol

protocol MatrixServiceProtocol: AnyObject {
    /// Current connection state
    var connectionState: MatrixConnectionState { get }
    var connectionStatePublisher: AnyPublisher<MatrixConnectionState, Never> { get }

    /// Current user ID (if logged in)
    var userId: String? { get }

    /// Initialize the Matrix client with session data
    func initialize(homeserverURL: String, sessionPath: String) async throws

    /// Login with Nova credentials (bridges to Matrix)
    func login(novaUserId: String, accessToken: String) async throws

    /// Login with username/password directly
    func loginWithPassword(username: String, password: String) async throws

    /// Logout and clear session
    func logout() async throws

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

    /// Set typing indicator
    func setTyping(roomId: String, isTyping: Bool) async throws

    /// Mark room as read
    func markRoomAsRead(roomId: String) async throws

    /// Get room by ID
    func getRoom(roomId: String) -> MatrixRoom?

    /// Get all joined rooms
    func getJoinedRooms() async throws -> [MatrixRoom]
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
        }
    }
}

// MARK: - Matrix Service Implementation

/// Main Matrix service implementation
/// NOTE: Requires MatrixRustSDK package to be added to the project
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

    // MARK: - Private Properties

    /// Matrix client instance (from MatrixRustSDK)
    /// Type: ClientProtocol from MatrixRustSDK
    /// Uncomment when SDK is added:
    // private var client: ClientProtocol?

    /// Room list service for efficient room updates
    // private var roomListService: RoomListServiceProtocol?

    /// Sync task handle
    // private var syncTaskHandle: TaskHandle?

    /// Session storage path
    private var sessionPath: String?

    /// Homeserver URL
    private var homeserverURL: String?

    /// Room cache
    private var roomCache: [String: MatrixRoom] = [:]

    /// Message callbacks
    var onMessageReceived: ((MatrixMessage) -> Void)?
    var onRoomUpdated: ((MatrixRoom) -> Void)?
    var onTypingIndicator: ((String, [String]) -> Void)?  // roomId, userIds

    // MARK: - Initialization

    private init() {
        #if DEBUG
        print("[MatrixService] Initialized (SDK integration pending)")
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

        // TODO: Initialize MatrixRustSDK client
        // When SDK is added:
        /*
        let clientBuilder = ClientBuilder()
            .homeserverUrl(homeserverURL)
            .sessionPath(sessionPath)
            .slidingSyncVersionBuilder(.proxy(url: slidingSyncProxyURL))

        self.client = try await clientBuilder.build()
        */

        updateConnectionState(.disconnected)

        #if DEBUG
        print("[MatrixService] Client initialized (stub)")
        #endif
    }

    func login(novaUserId: String, accessToken: String) async throws {
        #if DEBUG
        print("[MatrixService] Logging in Nova user: \(novaUserId)")
        #endif

        guard homeserverURL != nil else {
            throw MatrixError.notInitialized
        }

        updateConnectionState(.connecting)

        // Convert Nova user ID to Matrix user ID format
        // Format: @nova-<uuid>:staging.nova.internal
        let matrixUserId = convertToMatrixUserId(novaUserId: novaUserId)

        // TODO: Login with access token from Nova backend
        // The Nova backend should provide a Matrix access token
        // after authenticating the user
        /*
        try await client?.restoreSession(session: MatrixSession(
            userId: matrixUserId,
            accessToken: accessToken,
            deviceId: deviceId
        ))
        */

        self.userId = matrixUserId
        updateConnectionState(.connected)

        #if DEBUG
        print("[MatrixService] Logged in as: \(matrixUserId) (stub)")
        #endif
    }

    func loginWithPassword(username: String, password: String) async throws {
        #if DEBUG
        print("[MatrixService] Logging in with password: \(username)")
        #endif

        guard homeserverURL != nil else {
            throw MatrixError.notInitialized
        }

        updateConnectionState(.connecting)

        // TODO: Login with username/password
        /*
        try await client?.login(
            username: username,
            password: password,
            initialDeviceDisplayName: UIDevice.current.name,
            deviceId: nil
        )

        self.userId = try await client?.userId()
        */

        // Stub for now
        self.userId = "@\(username):\(homeserverURL ?? "localhost")"
        updateConnectionState(.connected)

        #if DEBUG
        print("[MatrixService] Logged in (stub)")
        #endif
    }

    func logout() async throws {
        #if DEBUG
        print("[MatrixService] Logging out")
        #endif

        stopSync()

        // TODO: Logout from Matrix
        // try await client?.logout()

        self.userId = nil
        roomCache.removeAll()
        updateConnectionState(.disconnected)

        #if DEBUG
        print("[MatrixService] Logged out")
        #endif
    }

    // MARK: - Sync

    func startSync() async throws {
        #if DEBUG
        print("[MatrixService] Starting sync")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        updateConnectionState(.syncing)

        // TODO: Start sliding sync
        /*
        let syncSettings = SyncSettings()
        syncTaskHandle = client?.syncService().start(settings: syncSettings)

        // Listen for room updates
        roomListService = client?.roomListService()
        roomListService?.subscribeToRooms { [weak self] rooms in
            self?.handleRoomListUpdate(rooms)
        }
        */

        #if DEBUG
        print("[MatrixService] Sync started (stub)")
        #endif
    }

    func stopSync() {
        #if DEBUG
        print("[MatrixService] Stopping sync")
        #endif

        // TODO: Stop sync
        // syncTaskHandle?.cancel()
        // syncTaskHandle = nil

        if connectionState == .syncing {
            updateConnectionState(.connected)
        }
    }

    // MARK: - Room Operations

    func createRoom(name: String?, isDirect: Bool, inviteUserIds: [String], isEncrypted: Bool) async throws -> String {
        #if DEBUG
        print("[MatrixService] Creating room: \(name ?? "Direct"), direct=\(isDirect), members=\(inviteUserIds.count)")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // Convert Nova user IDs to Matrix user IDs
        let matrixUserIds = inviteUserIds.map { convertToMatrixUserId(novaUserId: $0) }

        // TODO: Create room via SDK
        /*
        let parameters = CreateRoomParameters(
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

        let roomId = try await client?.createRoom(request: parameters)

        // Wait for room to sync
        try await waitForRoomToSync(roomId: roomId)

        return roomId
        */

        // Stub: Return a fake room ID
        let stubRoomId = "!\(UUID().uuidString.prefix(18)):staging.nova.internal"

        #if DEBUG
        print("[MatrixService] Created room: \(stubRoomId) (stub)")
        #endif

        return stubRoomId
    }

    func joinRoom(roomIdOrAlias: String) async throws -> String {
        #if DEBUG
        print("[MatrixService] Joining room: \(roomIdOrAlias)")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Join room
        /*
        let room = try await client?.joinRoomByIdOrAlias(
            roomIdOrAlias: roomIdOrAlias,
            serverNames: []
        )
        return room.id()
        */

        return roomIdOrAlias
    }

    func leaveRoom(roomId: String) async throws {
        #if DEBUG
        print("[MatrixService] Leaving room: \(roomId)")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Leave room
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }
        try await room.leave()
        */

        roomCache.removeValue(forKey: roomId)
    }

    // MARK: - Messaging

    func sendMessage(roomId: String, content: String) async throws -> String {
        #if DEBUG
        print("[MatrixService] Sending message to room: \(roomId)")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Send message via SDK
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }

        let timeline = room.timeline()
        try await timeline.send(content: RoomMessageEventContentWithoutRelation.text(
            body: content,
            formatted: nil
        ))

        // Return the event ID from the send receipt
        return eventId
        */

        // Stub: Return a fake event ID
        let stubEventId = "$\(UUID().uuidString)"

        #if DEBUG
        print("[MatrixService] Message sent: \(stubEventId) (stub)")
        #endif

        return stubEventId
    }

    func sendMedia(roomId: String, mediaURL: URL, mimeType: String, caption: String?) async throws -> String {
        #if DEBUG
        print("[MatrixService] Sending media to room: \(roomId), type: \(mimeType)")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Upload and send media
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }

        // Read file data
        let data = try Data(contentsOf: mediaURL)

        // Upload to Matrix media server
        let uploadResponse = try await client?.uploadMedia(
            mimeType: mimeType,
            data: data,
            progressWatcher: nil
        )

        // Send media message
        let timeline = room.timeline()
        let content: RoomMessageEventContentWithoutRelation

        if mimeType.hasPrefix("image/") {
            content = .image(
                body: caption ?? mediaURL.lastPathComponent,
                source: MediaSource(url: uploadResponse.contentUri),
                info: nil
            )
        } else if mimeType.hasPrefix("video/") {
            content = .video(
                body: caption ?? mediaURL.lastPathComponent,
                source: MediaSource(url: uploadResponse.contentUri),
                info: nil
            )
        } else {
            content = .file(
                body: caption ?? mediaURL.lastPathComponent,
                source: MediaSource(url: uploadResponse.contentUri),
                info: nil
            )
        }

        try await timeline.send(content: content)
        return eventId
        */

        // Stub
        return "$\(UUID().uuidString)"
    }

    func getRoomMessages(roomId: String, limit: Int, from: String?) async throws -> [MatrixMessage] {
        #if DEBUG
        print("[MatrixService] Getting messages for room: \(roomId), limit: \(limit)")
        #endif

        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Fetch timeline
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }

        let timeline = room.timeline()
        let items = try await timeline.paginateBackwards(count: UInt16(limit))

        return items.compactMap { item -> MatrixMessage? in
            guard case .event(let eventItem) = item else { return nil }
            return convertToMatrixMessage(eventItem)
        }
        */

        // Stub: Return empty list
        return []
    }

    // MARK: - Room Management

    func inviteUser(roomId: String, userId: String) async throws {
        #if DEBUG
        print("[MatrixService] Inviting user \(userId) to room \(roomId)")
        #endif

        guard self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        let matrixUserId = convertToMatrixUserId(novaUserId: userId)

        // TODO: Invite user
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }
        try await room.inviteUserById(userId: matrixUserId)
        */
    }

    func kickUser(roomId: String, userId: String, reason: String?) async throws {
        #if DEBUG
        print("[MatrixService] Kicking user \(userId) from room \(roomId)")
        #endif

        guard self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        let matrixUserId = convertToMatrixUserId(novaUserId: userId)

        // TODO: Kick user
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }
        try await room.kickUser(userId: matrixUserId, reason: reason)
        */
    }

    func setTyping(roomId: String, isTyping: Bool) async throws {
        guard self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Set typing indicator
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }
        try await room.typingNotice(isTyping: isTyping)
        */
    }

    func markRoomAsRead(roomId: String) async throws {
        guard self.userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Mark as read
        /*
        guard let room = client?.getRoom(roomId: roomId) else {
            throw MatrixError.roomNotFound(roomId)
        }
        try await room.markAsRead(receiptType: .read)
        */
    }

    func getRoom(roomId: String) -> MatrixRoom? {
        return roomCache[roomId]
    }

    func getJoinedRooms() async throws -> [MatrixRoom] {
        guard userId != nil else {
            throw MatrixError.notLoggedIn
        }

        // TODO: Get joined rooms
        /*
        let rooms = try await roomListService?.allRooms()
        return rooms?.map { convertToMatrixRoom($0) } ?? []
        */

        return Array(roomCache.values)
    }

    // MARK: - Helper Methods

    /// Convert Nova user ID to Matrix user ID format
    /// Nova: uuid-string -> Matrix: @nova-<uuid>:staging.nova.internal
    private func convertToMatrixUserId(novaUserId: String) -> String {
        // If already in Matrix format, return as-is
        if novaUserId.hasPrefix("@") {
            return novaUserId
        }

        // Convert UUID to Matrix format
        let domain = homeserverURL?
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first
            .map(String.init) ?? "staging.nova.internal"

        return "@nova-\(novaUserId):\(domain)"
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

    private func updateConnectionState(_ state: MatrixConnectionState) {
        self.connectionState = state
        connectionStateSubject.send(state)
    }
}

// MARK: - Matrix Configuration

struct MatrixConfiguration {
    /// Nova staging Matrix homeserver URL
    static let stagingHomeserver = "https://matrix.staging.nova.internal"

    /// Nova production Matrix homeserver URL
    static let productionHomeserver = "https://matrix.nova.social"

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
        #if DEBUG
        return stagingHomeserver
        #else
        return productionHomeserver
        #endif
    }
}
