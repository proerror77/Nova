import SwiftUI
import CoreLocation

/// ViewModel for individual chat conversations
/// Acts as a coordinator/facade, delegating to specialized handlers
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Dependencies

    // Use nonisolated(unsafe) to allow access in deinit
    // This is safe because ChatService handles its own thread safety
    nonisolated(unsafe) var chatService = ChatService()
    private let mediaService = MediaService()

    // MARK: - Handlers

    private var messageSender: ChatMessageSender?
    private var typingHandler: ChatTypingHandler?
    private var webSocketHandler: ChatWebSocketHandler?

    // MARK: - Core State

    @Published var messages: [ChatMessage] = []
    @Published var messageText = ""
    @Published var error: String?

    // MARK: - Loading States

    @Published var isLoadingHistory = false
    @Published var isSending = false
    @Published var isUploadingImage = false

    // MARK: - Pagination

    @Published var hasMoreMessages = true
    var nextCursor: String?

    // MARK: - Matrix/E2EE

    @Published var isMatrixE2EEEnabled = false

    // MARK: - Typing Indicator

    @Published var isOtherUserTyping = false
    @Published var typingUserName = ""

    // MARK: - Properties

    let conversationId: String
    let userName: String
    let otherUserId: String

    // MARK: - Computed

    var currentUserId: String {
        KeychainService.shared.get(.userId) ?? "unknown"
    }

    // MARK: - Init

    init(conversationId: String, userName: String, otherUserId: String = "") {
        self.conversationId = conversationId
        self.userName = userName
        self.otherUserId = otherUserId

        setupHandlers()
    }

    // MARK: - Handler Setup

    private func setupHandlers() {
        // Message Sender
        messageSender = ChatMessageSender(
            chatService: chatService,
            conversationId: conversationId
        )
        messageSender?.currentUserId = { [weak self] in
            self?.currentUserId ?? "unknown"
        }
        messageSender?.onMessageAdded = { [weak self] message in
            self?.messages.append(message)
        }
        messageSender?.onMessageUpdated = { [weak self] localId, confirmedMessage in
            guard let self = self else { return }
            if let index = self.messages.firstIndex(where: { $0.id == localId }) {
                self.messages[index] = confirmedMessage
            }
        }
        messageSender?.onMessageRemoved = { [weak self] messageId in
            self?.messages.removeAll { $0.id == messageId }
        }
        messageSender?.onSendingStateChanged = { [weak self] isSending in
            self?.isSending = isSending
        }
        messageSender?.onUploadingStateChanged = { [weak self] isUploading in
            self?.isUploadingImage = isUploading
        }
        messageSender?.onError = { [weak self] errorMessage in
            self?.error = errorMessage
        }

        // Typing Handler
        typingHandler = ChatTypingHandler(
            chatService: chatService,
            conversationId: conversationId,
            currentUserId: currentUserId
        )
        typingHandler?.onTypingStateChanged = { [weak self] isTyping, userName in
            self?.isOtherUserTyping = isTyping
            self?.typingUserName = userName
        }

        // WebSocket Handler
        webSocketHandler = ChatWebSocketHandler(
            chatService: chatService,
            conversationId: conversationId,
            currentUserId: currentUserId
        )
        webSocketHandler?.onMessageReceived = { [weak self] newMessage in
            guard let self = self else { return }
            // Avoid duplicates
            guard !self.messages.contains(where: { $0.id == newMessage.id }) else { return }
            self.messages.append(ChatMessage(from: newMessage, currentUserId: self.currentUserId))
            // Clear typing indicator when message is received
            self.isOtherUserTyping = false
            // Mark as read
            Task {
                try? await self.chatService.markAsRead(
                    conversationId: self.conversationId,
                    messageId: newMessage.id
                )
            }
        }
        webSocketHandler?.onTypingReceived = { [weak self] typingData in
            self?.typingHandler?.handleTypingIndicator(typingData)
        }
        webSocketHandler?.onMatrixTypingReceived = { [weak self] userIds in
            self?.typingHandler?.handleMatrixTypingIndicator(userIds: userIds)
        }
        webSocketHandler?.onMatrixE2EEStateChanged = { [weak self] isEnabled in
            self?.isMatrixE2EEEnabled = isEnabled
        }
    }

    // MARK: - Lifecycle Methods

    /// Load chat data (message history + WebSocket connection)
    func loadChatData() async {
        isLoadingHistory = true
        error = nil

        do {
            // 1. Setup connections (Matrix E2EE + WebSocket callbacks)
            webSocketHandler?.setupConnections()
            isMatrixE2EEEnabled = webSocketHandler?.isMatrixE2EEEnabled ?? false

            // 2. Get message history
            let response = try await chatService.getMessages(conversationId: conversationId, limit: 50)

            // 3. Convert to UI messages
            messages = response.messages.map { ChatMessage(from: $0, currentUserId: currentUserId) }

            // 4. Store pagination info
            hasMoreMessages = response.hasMore
            nextCursor = response.nextCursor

            // 5. Connect WebSocket
            webSocketHandler?.connect()

            // 6. Mark messages as read
            if let lastMessage = messages.last {
                try? await chatService.markAsRead(conversationId: conversationId, messageId: lastMessage.id)
            }

            #if DEBUG
            print("[ChatViewModel] Loaded \(messages.count) messages for conversation \(conversationId)")
            #endif

        } catch {
            self.error = "Failed to load messages: \(error.localizedDescription)"
            #if DEBUG
            print("[ChatViewModel] Load error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }

    /// Load more messages (pagination)
    func loadMoreMessages() async {
        guard hasMoreMessages, let cursor = nextCursor, !isLoadingHistory else { return }

        isLoadingHistory = true

        do {
            let response = try await chatService.getMessages(
                conversationId: conversationId,
                limit: 50,
                cursor: cursor
            )

            // Prepend older messages
            let olderMessages = response.messages.map { ChatMessage(from: $0, currentUserId: currentUserId) }
            messages.insert(contentsOf: olderMessages, at: 0)

            hasMoreMessages = response.hasMore
            nextCursor = response.nextCursor

        } catch {
            #if DEBUG
            print("[ChatViewModel] Load more error: \(error)")
            #endif
        }

        isLoadingHistory = false
    }

    // MARK: - Send Messages (Delegated to MessageSender)

    /// 發送文字訊息 - 使用 Matrix E2EE（端到端加密）
    func sendMessage() async {
        guard !isSending else { return }
        let text = messageText
        messageText = ""
        await messageSender?.sendTextMessage(text)
    }

    /// 發送圖片訊息 - 使用 Matrix SDK
    func sendImageMessage(_ image: UIImage) async {
        await messageSender?.sendImageMessage(image)
    }

    /// 發送位置訊息 - 使用 Matrix SDK
    func sendLocationMessage(_ location: CLLocationCoordinate2D) async {
        await messageSender?.sendLocationMessage(location)
    }

    /// 發送語音訊息 - 使用 Matrix SDK
    func sendVoiceMessage(audioData: Data, duration: TimeInterval, url: URL) async {
        await messageSender?.sendVoiceMessage(audioData: audioData, duration: duration, url: url)
    }

    // MARK: - Typing Indicator (Delegated to TypingHandler)

    /// Send typing start indicator
    func sendTypingStart() {
        typingHandler?.sendTypingStart()
    }

    /// Send typing stop indicator
    func sendTypingStop() {
        typingHandler?.sendTypingStop()
    }

    // MARK: - Cleanup

    /// Disconnect WebSocket when view disappears
    func cleanup() {
        webSocketHandler?.cleanup()
        typingHandler?.cleanup()

        #if DEBUG
        print("[ChatViewModel] Cleanup completed for conversation \(conversationId)")
        #endif
    }

    deinit {
        // Capture references for async cleanup
        let wsHandler = webSocketHandler
        let typeHandler = typingHandler
        let convId = conversationId

        Task { @MainActor in
            wsHandler?.cleanup()
            typeHandler?.cleanup()

            #if DEBUG
            print("[ChatViewModel] deinit - resources released for conversation \(convId)")
            #endif
        }
    }
}
