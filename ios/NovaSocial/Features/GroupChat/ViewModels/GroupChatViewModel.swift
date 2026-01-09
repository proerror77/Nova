import SwiftUI
import CoreLocation

// MARK: - Group Chat UI Message
/// UI-layer message model for group chats
/// Extends ChatMessage with sender display information
struct GroupChatUIMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let senderId: String
    let senderName: String
    let senderAvatarUrl: String?
    let isFromMe: Bool
    let timestamp: Date
    let messageType: ChatMessageType
    let status: MessageStatus

    // Media fields
    var mediaUrl: String?
    var matrixMediaSourceJson: String?
    var matrixMediaMimeType: String?
    var matrixMediaFilename: String?
    var image: UIImage?
    var audioData: Data?
    var audioDuration: TimeInterval?
    var audioUrl: URL?
    var location: CLLocationCoordinate2D?

    static func == (lhs: GroupChatUIMessage, rhs: GroupChatUIMessage) -> Bool {
        lhs.id == rhs.id
    }

    /// Create from a Matrix message with member info lookup
    init(
        from matrixMessage: MatrixMessage,
        conversationId: String,
        currentUserId: String,
        memberInfo: [String: GroupMemberInfo],
        myMatrixId: String? = nil
    ) {
        self.id = matrixMessage.id
        self.text = matrixMessage.content
        self.senderId = matrixMessage.senderId
        self.timestamp = matrixMessage.timestamp
        self.messageType = Self.mapMessageType(matrixMessage.type.rawValue)
        self.status = .sent
        self.mediaUrl = matrixMessage.mediaURL
        self.matrixMediaSourceJson = matrixMessage.mediaSourceJson
        self.matrixMediaMimeType = matrixMessage.mediaInfo?.mimeType
        self.matrixMediaFilename = matrixMessage.mediaFilename

        // Determine if message is from current user
        self.isFromMe = matrixMessage.senderId == myMatrixId || matrixMessage.senderId == currentUserId

        // Look up sender info from member cache
        if let member = memberInfo[matrixMessage.senderId] {
            self.senderName = member.displayName
            self.senderAvatarUrl = member.avatarUrl
        } else {
            // Fallback: extract display name from Matrix user ID
            self.senderName = Self.extractDisplayName(from: matrixMessage.senderId)
            self.senderAvatarUrl = nil
        }
    }

    /// Create a local message for optimistic UI update
    init(
        localText: String,
        senderId: String,
        senderName: String,
        senderAvatarUrl: String?,
        isFromMe: Bool = true,
        image: UIImage? = nil,
        audioData: Data? = nil,
        audioDuration: TimeInterval? = nil,
        audioUrl: URL? = nil,
        location: CLLocationCoordinate2D? = nil
    ) {
        self.id = UUID().uuidString
        self.text = localText
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatarUrl = senderAvatarUrl
        self.isFromMe = isFromMe
        self.timestamp = Date()
        self.status = .sending
        self.image = image
        self.audioData = audioData
        self.audioDuration = audioDuration
        self.audioUrl = audioUrl
        self.location = location
        self.matrixMediaSourceJson = nil
        self.matrixMediaMimeType = nil
        self.matrixMediaFilename = nil

        // Determine message type from content
        if image != nil {
            self.messageType = .image
        } else if location != nil {
            self.messageType = .location
        } else if audioData != nil || audioUrl != nil {
            self.messageType = .audio
        } else {
            self.messageType = .text
        }
    }

    private static func mapMessageType(_ type: String) -> ChatMessageType {
        switch type.lowercased() {
        case "m.image", "image": return .image
        case "m.video", "video": return .video
        case "m.audio", "audio": return .audio
        case "m.file", "file": return .file
        case "m.location", "location": return .location
        default: return .text
        }
    }

    private static func extractDisplayName(from matrixUserId: String) -> String {
        // Matrix user ID format: @username:domain
        if matrixUserId.hasPrefix("@") {
            let parts = matrixUserId.dropFirst().split(separator: ":")
            if let username = parts.first {
                return String(username)
            }
        }
        return matrixUserId
    }
}

// MARK: - Group Member Info
/// Cached member information for display
struct GroupMemberInfo {
    let userId: String
    let displayName: String
    let avatarUrl: String?
}

// MARK: - GroupChatViewModel
/// ViewModel for GroupChatView - handles state and business logic for group conversations
/// Uses MatrixBridgeService for E2EE messaging

@MainActor
@Observable
final class GroupChatViewModel {

    // MARK: - Configuration

    private(set) var conversationId: String = ""
    private(set) var groupName: String = ""
    private(set) var memberCount: Int = 0

    // MARK: - Services

    private let matrixBridge = MatrixBridgeService.shared
    private(set) var messageSender: GroupChatMessageSender?
    let audioRecorder = AudioRecorderService()

    // MARK: - Message State

    var messageText = ""
    var messages: [GroupChatUIMessage] = []

    // MARK: - Member Info Cache

    private var memberInfo: [String: GroupMemberInfo] = [:]

    // MARK: - UI State

    var showAttachmentOptions = false
    var showVoiceCall = false
    var showVideoCall = false
    var showFilePicker = false

    // MARK: - Loading States

    var isLoading = false
    var isSending = false
    var isRecordingVoice = false
    var isPreviewMode = false

    // MARK: - Pagination

    var hasMoreMessages = true

    // MARK: - Error State

    var error: String?

    // MARK: - Matrix Media Resolution

    private var resolvingMediaMessageIds = Set<String>()

    // MARK: - Voice Recording

    var voiceRecordDragOffset: CGFloat = 0
    let voiceCancelThreshold: CGFloat = -60

    // MARK: - Internal State

    private var matrixMessageHandlerSetup = false
    private var matrixMessageObserverToken: UUID?
    private var hasLoadedMemberInfo = false

    // MARK: - Computed Properties

    var currentUserId: String {
        KeychainService.shared.get(.userId) ?? "unknown"
    }

    var currentUserName: String {
        AuthenticationManager.shared.currentUser?.username ?? "Me"
    }

    var currentUserAvatarUrl: String? {
        AuthenticationManager.shared.currentUser?.avatarUrl
    }

    // MARK: - Static Properties

    #if DEBUG
    private static var usePreviewMode: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return false
        #endif
    }
    #endif

    // MARK: - Initialization

    init() {}

    func configure(
        conversationId: String,
        groupName: String,
        memberCount: Int
    ) {
        self.conversationId = conversationId
        self.groupName = groupName
        self.memberCount = memberCount

        // Initialize message sender
        self.messageSender = GroupChatMessageSender(conversationId: conversationId)
        setupMessageSenderCallbacks()
    }

    // MARK: - Message Sender Callbacks

    private func setupMessageSenderCallbacks() {
        messageSender?.onMessageAdded = { [weak self] message in
            Task { @MainActor in
                self?.messages.append(message)
            }
        }

        messageSender?.onMessageUpdated = { [weak self] localId, updatedMessage in
            Task { @MainActor in
                if let index = self?.messages.firstIndex(where: { $0.id == localId }) {
                    self?.messages[index] = updatedMessage
                }
            }
        }

        messageSender?.onMessageRemoved = { [weak self] messageId in
            Task { @MainActor in
                self?.messages.removeAll { $0.id == messageId }
            }
        }

        messageSender?.onSendingStateChanged = { [weak self] isSending in
            Task { @MainActor in
                self?.isSending = isSending
            }
        }

        messageSender?.onError = { [weak self] errorMessage in
            Task { @MainActor in
                self?.error = errorMessage
            }
        }

        messageSender?.getCurrentUserInfo = { [weak self] in
            guard let self = self else {
                return (id: "unknown", name: "Me", avatarUrl: nil)
            }
            return (
                id: self.currentUserId,
                name: self.currentUserName,
                avatarUrl: self.currentUserAvatarUrl
            )
        }
    }

    // MARK: - Load Messages

    func loadMessages() async {
        #if DEBUG
        if Self.usePreviewMode {
            print("🎨 [GroupChatViewModel] Preview Mode enabled - using mock data")
            loadMockMessages()
            isLoading = false
            error = nil
            isPreviewMode = true
            return
        }
        #endif

        isPreviewMode = false
        isLoading = true
        error = nil

        do {
            // Ensure Matrix is initialized
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Load member info (display names + avatars) before rendering messages
            await loadMemberInfoIfNeeded()

            // Setup real-time message handler
            setupMatrixMessageHandler()

            // Load messages from Matrix
            let matrixMessages = try await matrixBridge.getMessages(
                conversationId: conversationId,
                limit: 50
            )

            // Sort by timestamp
            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }

            // Convert to UI messages
            let myMatrixId = matrixBridge.matrixUserId
            messages = sorted.map { matrixMessage in
                GroupChatUIMessage(
                    from: matrixMessage,
                    conversationId: conversationId,
                    currentUserId: currentUserId,
                    memberInfo: memberInfo,
                    myMatrixId: myMatrixId
                )
            }

            resolveMatrixMediaForLoadedMessages()

            resolveMatrixMediaForLoadedMessages()

            hasMoreMessages = matrixMessages.count >= 50

            // Mark as read
            try? await matrixBridge.markAsRead(conversationId: conversationId)

            #if DEBUG
            print("[GroupChatViewModel] Loaded \(messages.count) messages for group \(conversationId)")
            #endif

        } catch {
            self.error = "Failed to load messages: \(error.localizedDescription)"
            #if DEBUG
            print("[GroupChatViewModel] Load error: \(error)")
            #endif
        }

        isLoading = false
    }

    private func loadMemberInfoIfNeeded() async {
        guard !hasLoadedMemberInfo else { return }
        hasLoadedMemberInfo = true

        do {
            let members = try await matrixBridge.getRoomMembers(roomId: conversationId)
            var updated: [String: GroupMemberInfo] = [:]
            updated.reserveCapacity(members.count)
            for member in members {
                let display = member.displayName?.isEmpty == false ? member.displayName! : extractDisplayName(from: member.userId)
                updated[member.userId] = GroupMemberInfo(
                    userId: member.userId,
                    displayName: display,
                    avatarUrl: member.avatarUrl
                )
            }
            memberInfo = updated
        } catch {
            #if DEBUG
            print("[GroupChatViewModel] ⚠️ Failed to load room members for \(conversationId): \(error)")
            #endif
        }
    }

    private func extractDisplayName(from matrixUserId: String) -> String {
        if matrixUserId.hasPrefix("@") {
            let parts = matrixUserId.dropFirst().split(separator: ":")
            if let localpart = parts.first {
                return String(localpart)
            }
        }
        return matrixUserId
    }

    private func resolveMatrixMediaForLoadedMessages() {
        for idx in messages.indices {
            resolveMatrixMediaIfNeeded(messageIndex: idx)
        }
    }

    private func resolveMatrixMediaIfNeeded(messageIndex: Int) {
        guard messages.indices.contains(messageIndex) else { return }

        let message = messages[messageIndex]
        guard message.mediaUrl == nil else { return }

        switch message.messageType {
        case .image, .video, .audio, .file:
            break
        default:
            return
        }

        guard let mediaSourceJson = message.matrixMediaSourceJson else { return }

        if resolvingMediaMessageIds.contains(message.id) { return }
        resolvingMediaMessageIds.insert(message.id)

        Task {
            defer { resolvingMediaMessageIds.remove(message.id) }

            do {
                let urlString = try await matrixBridge.resolveMediaURL(
                    mediaSourceJson: mediaSourceJson,
                    mimeType: message.matrixMediaMimeType,
                    filename: message.matrixMediaFilename,
                    cacheKey: message.id
                )

                if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[idx].mediaUrl = urlString
                    if messages[idx].messageType == .audio, let url = URL(string: urlString) {
                        messages[idx].audioUrl = url
                    }
                }
            } catch {
                #if DEBUG
                print("[GroupChatViewModel] ⚠️ Failed to resolve Matrix media for message \(message.id): \(error)")
                #endif
            }
        }
    }

    // MARK: - Matrix Message Handler

    private func setupMatrixMessageHandler() {
        guard !matrixMessageHandlerSetup else {
            #if DEBUG
            print("[GroupChatViewModel] ⚠️ Matrix message handler already setup, skipping")
            #endif
            return
        }

        matrixMessageHandlerSetup = true

        matrixMessageObserverToken = MatrixBridgeService.shared.addMatrixMessageObserver { [weak self] conversationId, matrixMessage in
            Task { @MainActor in
                guard let self = self else { return }
                guard conversationId == self.conversationId else { return }

                // Skip own messages (avoid duplicate with optimistic update)
                if let myMatrixId = MatrixBridgeService.shared.matrixUserId,
                   matrixMessage.senderId == myMatrixId {
                    #if DEBUG
                    print("[GroupChatViewModel] ✅ Skipping own message from Matrix sync: \(matrixMessage.id)")
                    #endif
                    return
                }

                // Avoid duplicates
                if self.messages.contains(where: { $0.id == matrixMessage.id }) {
                    #if DEBUG
                    print("[GroupChatViewModel] ⚠️ Skipping duplicate message: \(matrixMessage.id)")
                    #endif
                    return
                }

                let newMessage = GroupChatUIMessage(
                    from: matrixMessage,
                    conversationId: conversationId,
                    currentUserId: self.currentUserId,
                    memberInfo: self.memberInfo,
                    myMatrixId: MatrixBridgeService.shared.matrixUserId
                )

                // Double-check for race conditions
                if self.messages.contains(where: { $0.id == newMessage.id }) {
                    return
                }

                self.messages.append(newMessage)

                if let idx = self.messages.firstIndex(where: { $0.id == newMessage.id }) {
                    self.resolveMatrixMediaIfNeeded(messageIndex: idx)
                }

                #if DEBUG
                print("[GroupChatViewModel] ✅ Message added - ID: \(newMessage.id), Total: \(self.messages.count)")
                #endif

                // Mark as read
                try? await self.matrixBridge.markAsRead(conversationId: self.conversationId)
            }
        }

        #if DEBUG
        print("[GroupChatViewModel] Matrix message handler setup complete")
        #endif
    }

    func cleanup() {
        if let token = matrixMessageObserverToken {
            MatrixBridgeService.shared.removeMatrixMessageObserver(token)
        }
        matrixMessageObserverToken = nil
        matrixMessageHandlerSetup = false

        Task {
            await matrixBridge.stopListening(conversationId: conversationId)
        }

        audioRecorder.cleanupTempFiles()

        #if DEBUG
        print("[GroupChatViewModel] Cleanup completed for conversation \(conversationId)")
        #endif
    }

    // MARK: - Load More Messages

    func loadMoreMessages() async {
        guard !isLoading, hasMoreMessages else { return }

        isLoading = true
        let previousCount = messages.count

        do {
            let desiredLimit = messages.count + 50
            let matrixMessages = try await matrixBridge.getMessages(
                conversationId: conversationId,
                limit: desiredLimit
            )

            let sorted = matrixMessages.sorted { $0.timestamp < $1.timestamp }

            let myMatrixId = matrixBridge.matrixUserId
            messages = sorted.map { matrixMessage in
                GroupChatUIMessage(
                    from: matrixMessage,
                    conversationId: conversationId,
                    currentUserId: currentUserId,
                    memberInfo: memberInfo,
                    myMatrixId: myMatrixId
                )
            }

            hasMoreMessages = messages.count > previousCount && matrixMessages.count >= desiredLimit

            #if DEBUG
            print("[GroupChatViewModel] Loaded more messages: \(previousCount) -> \(messages.count), hasMore: \(hasMoreMessages)")
            #endif
        } catch {
            #if DEBUG
            print("[GroupChatViewModel] Load more error: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Send Messages

    func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        messageText = ""
        showAttachmentOptions = false

        Task {
            await messageSender?.sendTextMessage(trimmedText)
        }
    }

    func sendImageMessage(data: Data, mimeType: String = "image/jpeg") {
        showAttachmentOptions = false

        Task {
            await messageSender?.sendImageMessage(data: data, mimeType: mimeType)
        }
    }

    func sendVoiceMessage(data: Data, duration: TimeInterval) {
        showAttachmentOptions = false

        Task {
            await messageSender?.sendVoiceMessage(data: data, duration: duration)
            audioRecorder.cleanupTempFiles()
        }
    }

    func sendFileMessage(data: Data, filename: String, mimeType: String) {
        showAttachmentOptions = false

        Task {
            await messageSender?.sendFileMessage(data: data, filename: filename, mimeType: mimeType)
        }
    }

    // MARK: - Message Actions

    func retryFailedMessage(_ message: GroupChatUIMessage) {
        guard message.status == .failed else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }

        // Update status to sending
        var updatedMessage = messages[index]
        updatedMessage = GroupChatUIMessage(
            localText: updatedMessage.text,
            senderId: updatedMessage.senderId,
            senderName: updatedMessage.senderName,
            senderAvatarUrl: updatedMessage.senderAvatarUrl,
            isFromMe: updatedMessage.isFromMe
        )
        messages[index] = updatedMessage

        let messageId = message.id
        let messageText = message.text

        Task {
            do {
                let eventId = try await matrixBridge.sendMessage(
                    conversationId: conversationId,
                    content: messageText
                )

                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx] = GroupChatUIMessage(
                        localText: messageText,
                        senderId: currentUserId,
                        senderName: currentUserName,
                        senderAvatarUrl: currentUserAvatarUrl,
                        isFromMe: true
                    )
                }

                #if DEBUG
                print("[GroupChatViewModel] ✅ Message retry succeeded: \(eventId)")
                #endif
            } catch {
                // Mark as failed again
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx] = GroupChatUIMessage(
                        localText: messageText,
                        senderId: currentUserId,
                        senderName: currentUserName,
                        senderAvatarUrl: currentUserAvatarUrl,
                        isFromMe: true
                    )
                }
                self.error = "Failed to send message"

                #if DEBUG
                print("[GroupChatViewModel] ❌ Message retry failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - Grouped Messages

    var groupedMessages: [(date: Date, messages: [GroupChatUIMessage])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        return grouped.map { (date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Mock Data

    private func loadMockMessages() {
        let mockDate = Calendar.current.date(from: DateComponents(
            year: 2025, month: 10, day: 22, hour: 12, minute: 0
        )) ?? Date()

        messages = [
            GroupChatUIMessage(
                localText: "Has everyone come in?",
                senderId: "user1",
                senderName: "Alice",
                senderAvatarUrl: nil,
                isFromMe: false
            ),
            GroupChatUIMessage(
                localText: "yup!",
                senderId: "user2",
                senderName: "Bob",
                senderAvatarUrl: nil,
                isFromMe: false
            ),
            GroupChatUIMessage(
                localText: "I'm already in.",
                senderId: currentUserId,
                senderName: currentUserName,
                senderAvatarUrl: currentUserAvatarUrl,
                isFromMe: true
            ),
            GroupChatUIMessage(
                localText: "Let's proceed to the next step.",
                senderId: "user3",
                senderName: "Charlie",
                senderAvatarUrl: nil,
                isFromMe: false
            ),
        ]
    }
}
