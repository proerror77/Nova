import Foundation
import Combine
import MatrixRustSDK

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

    /// Restore session from stored credentials
    func restoreSession() async throws -> Bool

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

    // MARK: - Private Properties

    /// Matrix client instance (from MatrixRustSDK)
    private var client: Client?

    /// Sync service for background updates
    private var syncService: SyncService?

    /// Room list service for efficient room updates
    private var roomListService: RoomListService?

    /// Session storage path
    private var sessionPath: String?

    /// Homeserver URL
    private var homeserverURL: String?

    /// Room cache
    private var roomCache: [String: MatrixRoom] = [:]

    /// Timeline listeners cache (room_id -> listener)
    private var timelineListeners: [String: TaskHandle] = [:]

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

            // Build client using ClientBuilder
            let clientBuilder = ClientBuilder()
                .homeserverUrl(url: homeserverURL)
                .sessionPath(path: sessionPath)
                .userAgent(userAgent: "NovaSocial-iOS/1.0")

            self.client = try await clientBuilder.build()

            updateConnectionState(.disconnected)

            #if DEBUG
            print("[MatrixService] Client initialized successfully")
            #endif
        } catch {
            updateConnectionState(.error(error.localizedDescription))
            throw MatrixError.sdkError(error.localizedDescription)
        }
    }

    func login(novaUserId: String, accessToken: String) async throws {
        #if DEBUG
        print("[MatrixService] Logging in Nova user: \(novaUserId)")
        #endif

        guard let client = client else {
            throw MatrixError.notInitialized
        }

        updateConnectionState(.connecting)

        // Convert Nova user ID to Matrix user ID format
        let matrixUserId = convertToMatrixUserId(novaUserId: novaUserId)

        do {
            // Extract device ID from stored session or generate new one
            let deviceId = getOrCreateDeviceId()

            // Restore session with access token
            let session = Session(
                accessToken: accessToken,
                refreshToken: nil,
                userId: matrixUserId,
                deviceId: deviceId,
                homeserverUrl: homeserverURL ?? "",
                oidcData: nil,
                slidingSyncVersion: .none
            )

            try await client.restoreSession(session: session)

            self.userId = matrixUserId

            // Store session for later restoration
            storeSessionCredentials(
                userId: matrixUserId,
                accessToken: accessToken,
                deviceId: deviceId
            )

            updateConnectionState(.connected)

            #if DEBUG
            print("[MatrixService] Logged in as: \(matrixUserId)")
            #endif
        } catch {
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

            self.userId = client.userId()

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
            let session = Session(
                accessToken: credentials.accessToken,
                refreshToken: nil,
                userId: credentials.userId,
                deviceId: credentials.deviceId,
                homeserverUrl: homeserverURL ?? "",
                oidcData: nil,
                slidingSyncVersion: .none
            )

            try await client.restoreSession(session: session)

            self.userId = credentials.userId
            updateConnectionState(.connected)

            #if DEBUG
            print("[MatrixService] Session restored for: \(credentials.userId)")
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

        stopSync()

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
        timelineListeners.removeAll()
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

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        updateConnectionState(.syncing)

        do {
            // Create sync service
            let syncServiceBuilder = client.syncService()
            self.syncService = try await syncServiceBuilder
                .withCrossProcessLock(appIdentifier: "com.novasocial.icered")
                .finish()

            // Start sync
            try await syncService?.start()

            // Setup room list service
            self.roomListService = syncService?.roomListService()

            // Subscribe to room list updates
            setupRoomListObserver()

            #if DEBUG
            print("[MatrixService] Sync started successfully")
            #endif
        } catch {
            updateConnectionState(.error(error.localizedDescription))
            throw MatrixError.syncFailed(error.localizedDescription)
        }
    }

    func stopSync() {
        #if DEBUG
        print("[MatrixService] Stopping sync")
        #endif

        Task {
            try? await syncService?.stop()
        }

        syncService = nil
        roomListService = nil

        // Cancel all timeline listeners
        for (_, handle) in timelineListeners {
            handle.cancel()
        }
        timelineListeners.removeAll()

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
            guard let room = client.getRoom(roomId: roomId) else {
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

    func sendMessage(roomId: String, content: String) async throws -> String {
        #if DEBUG
        print("[MatrixService] Sending message to room: \(roomId)")
        #endif

        guard let client = client, userId != nil else {
            throw MatrixError.notLoggedIn
        }

        do {
            guard let room = client.getRoom(roomId: roomId) else {
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
            guard let room = client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Read file data
            let data = try Data(contentsOf: mediaURL)
            let filename = mediaURL.lastPathComponent

            // Determine media type and create appropriate content
            if mimeType.hasPrefix("image/") {
                // Send as image
                try await timeline.sendImage(
                    url: mediaURL.path,
                    thumbnailUrl: nil,
                    imageInfo: ImageInfo(
                        height: nil,
                        width: nil,
                        mimetype: mimeType,
                        size: UInt64(data.count),
                        thumbnailInfo: nil,
                        thumbnailSource: nil,
                        blurhash: nil
                    ),
                    caption: caption,
                    formattedCaption: nil,
                    progressWatcher: nil
                )
            } else if mimeType.hasPrefix("video/") {
                // Send as video
                try await timeline.sendVideo(
                    url: mediaURL.path,
                    thumbnailUrl: nil,
                    videoInfo: VideoInfo(
                        duration: nil,
                        height: nil,
                        width: nil,
                        mimetype: mimeType,
                        size: UInt64(data.count),
                        thumbnailInfo: nil,
                        thumbnailSource: nil,
                        blurhash: nil
                    ),
                    caption: caption,
                    formattedCaption: nil,
                    progressWatcher: nil
                )
            } else if mimeType.hasPrefix("audio/") {
                // Send as audio
                try await timeline.sendAudio(
                    url: mediaURL.path,
                    audioInfo: AudioInfo(
                        duration: nil,
                        size: UInt64(data.count),
                        mimetype: mimeType
                    ),
                    caption: caption,
                    formattedCaption: nil,
                    progressWatcher: nil
                )
            } else {
                // Send as file
                try await timeline.sendFile(
                    url: mediaURL.path,
                    fileInfo: FileInfo(
                        mimetype: mimeType,
                        size: UInt64(data.count),
                        thumbnailInfo: nil,
                        thumbnailSource: nil
                    ),
                    progressWatcher: nil
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
            guard let room = client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }

            let timeline = try await room.timeline()

            // Paginate backwards to load history
            try await timeline.paginateBackwards(numEvents: UInt16(limit))

            // Get timeline items
            let items = timeline.getTimelineItems()

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
            guard let room = client.getRoom(roomId: roomId) else {
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
            guard let room = client.getRoom(roomId: roomId) else {
                throw MatrixError.roomNotFound(roomId)
            }
            try await room.kickUser(userId: matrixUserId, reason: reason)
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
            guard let room = client.getRoom(roomId: roomId) else {
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
            guard let room = client.getRoom(roomId: roomId) else {
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

        var matrixRooms: [MatrixRoom] = []
        for room in rooms {
            if let matrixRoom = await convertSDKRoomToMatrixRoom(room) {
                roomCache[matrixRoom.id] = matrixRoom
                matrixRooms.append(matrixRoom)
            }
        }

        return matrixRooms
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

    // MARK: - Room List Observer

    private func setupRoomListObserver() {
        guard let roomListService = roomListService else { return }

        Task {
            do {
                let roomList = try await roomListService.allRooms()

                // Subscribe to room list updates
                let listener = RoomListEntriesListener { [weak self] entries in
                    Task { @MainActor in
                        await self?.handleRoomListUpdate(entries)
                    }
                }

                let result = roomList.entries(listener: listener)

                // Process initial entries
                await handleRoomListUpdate(result.entries)
            } catch {
                #if DEBUG
                print("[MatrixService] Room list observer error: \(error)")
                #endif
            }
        }
    }

    private func handleRoomListUpdate(_ entries: [RoomListEntry]) async {
        for entry in entries {
            switch entry {
            case .filled(let roomId):
                if let room = client?.getRoom(roomId: roomId),
                   let matrixRoom = await convertSDKRoomToMatrixRoom(room) {
                    roomCache[roomId] = matrixRoom
                    onRoomUpdated?(matrixRoom)
                }
            case .empty, .invalidated:
                break
            }
        }
    }

    private func convertSDKRoomToMatrixRoom(_ room: Room) async -> MatrixRoom? {
        let roomId = room.id()
        let info = room.roomInfo()

        return MatrixRoom(
            id: roomId,
            name: room.displayName(),
            topic: info.topic,
            avatarURL: info.avatarUrl,
            isDirect: info.isDirect,
            isEncrypted: info.isEncrypted,
            memberCount: Int(info.activeMembersCount),
            unreadCount: Int(info.numUnreadMessages),
            lastMessage: nil,  // Would need timeline access
            lastActivity: nil,
            novaConversationId: nil
        )
    }

    private func convertTimelineItemToMessage(_ item: TimelineItem, roomId: String) -> MatrixMessage? {
        guard let eventItem = item.asEvent() else { return nil }

        let eventId = eventItem.eventId() ?? UUID().uuidString
        let senderId = eventItem.sender()
        let timestamp = Date(timeIntervalSince1970: Double(eventItem.timestamp()) / 1000.0)

        // Extract content based on message type
        guard let content = eventItem.content() else { return nil }

        switch content.kind() {
        case .message:
            if let msgContent = content.asMessage() {
                let body = msgContent.body()
                let msgType: MatrixMessageType

                switch msgContent.msgtype() {
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
                default:
                    msgType = .text
                }

                return MatrixMessage(
                    id: eventId,
                    roomId: roomId,
                    senderId: senderId,
                    content: body,
                    type: msgType,
                    timestamp: timestamp,
                    isEdited: false,
                    replyTo: nil,
                    mediaURL: nil,
                    mediaInfo: nil
                )
            }
        default:
            break
        }

        return nil
    }

    // MARK: - Session Storage

    private struct StoredCredentials: Codable {
        let userId: String
        let accessToken: String
        let deviceId: String
    }

    private func storeSessionCredentials(userId: String, accessToken: String, deviceId: String) {
        let credentials = StoredCredentials(
            userId: userId,
            accessToken: accessToken,
            deviceId: deviceId
        )

        if let data = try? JSONEncoder().encode(credentials) {
            KeychainService.shared.set(String(data: data, encoding: .utf8) ?? "", for: .matrixSession)
        }
    }

    private func loadSessionCredentials() -> StoredCredentials? {
        guard let jsonString = KeychainService.shared.get(.matrixSession),
              let data = jsonString.data(using: .utf8),
              let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data) else {
            return nil
        }
        return credentials
    }

    private func clearSessionCredentials() {
        KeychainService.shared.delete(.matrixSession)
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

// MARK: - Room List Entries Listener

private class RoomListEntriesListener: RoomListEntriesListenerProtocol {
    private let handler: ([RoomListEntry]) -> Void

    init(handler: @escaping ([RoomListEntry]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        // Extract entries from updates
        var entries: [RoomListEntry] = []
        for update in roomEntriesUpdate {
            switch update {
            case .append(let values):
                entries.append(contentsOf: values)
            case .set(_, let value):
                entries.append(value)
            case .insert(_, let value):
                entries.append(value)
            default:
                break
            }
        }
        handler(entries)
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

// MARK: - Keychain Extension for Matrix

extension KeychainService.Key {
    static let matrixSession = KeychainService.Key(rawValue: "matrix_session")
}
