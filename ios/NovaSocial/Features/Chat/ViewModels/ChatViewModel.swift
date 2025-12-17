import SwiftUI
import CoreLocation

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Dependencies
    @Published var chatService = ChatService()
    private let mediaService = MediaService()

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
    var typingTimer: Timer?

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
    }

    // MARK: - Lifecycle Methods

    /// Load chat data (message history + WebSocket connection)
    func loadChatData() async {
        isLoadingHistory = true
        error = nil

        do {
            // 0. 檢查並啟用 Matrix E2EE
            chatService.enableMatrixE2EE()
            isMatrixE2EEEnabled = MatrixBridgeService.shared.isInitialized

            #if DEBUG
            print("[ChatViewModel] Matrix E2EE enabled: \(isMatrixE2EEEnabled)")
            #endif

            // 1. Get message history
            let response = try await chatService.getMessages(conversationId: conversationId, limit: 50)

            // 2. Convert to UI messages
            messages = response.messages.map { ChatMessage(from: $0, currentUserId: currentUserId) }

            // 3. Store pagination info
            hasMoreMessages = response.hasMore
            nextCursor = response.nextCursor

            // 4. Setup WebSocket callbacks
            setupWebSocketCallbacks()

            // 5. Connect WebSocket
            chatService.connectWebSocket()

            // 6. Mark messages as read
            if let lastMessage = messages.last {
                try? await chatService.markAsRead(conversationId: conversationId, messageId: lastMessage.id)
            }

            // 7. Setup Matrix message handler (如果已啟用)
            if isMatrixE2EEEnabled {
                setupMatrixMessageHandler()
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

    /// Setup WebSocket event callbacks
    func setupWebSocketCallbacks() {
        // New message received
        chatService.onMessageReceived = { [weak self] newMessage in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Avoid duplicates
                guard !self.messages.contains(where: { $0.id == newMessage.id }) else { return }
                self.messages.append(ChatMessage(from: newMessage, currentUserId: self.currentUserId))

                // Clear typing indicator when message is received
                self.isOtherUserTyping = false

                // Mark as read
                try? await self.chatService.markAsRead(
                    conversationId: self.conversationId,
                    messageId: newMessage.id
                )
            }
        }

        // Typing indicator received
        chatService.onTypingIndicator = { [weak self] typingData in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only show if it's for this conversation and not from me
                guard typingData.conversationId == self.conversationId,
                      typingData.userId != self.currentUserId else { return }

                if typingData.isTyping {
                    self.startTypingIndicator(userName: typingData.username)
                } else {
                    self.stopTypingIndicator()
                }
            }
        }

        // Read receipt received
        chatService.onReadReceipt = { [weak self] readData in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard readData.conversationId == self.conversationId else { return }

                // Update message status to "read" for messages up to lastReadMessageId
                // This enables showing double checkmarks in the UI
                #if DEBUG
                print("[ChatViewModel] Read receipt: \(readData.userId) read up to \(readData.lastReadMessageId)")
                #endif
            }
        }
    }

    /// Setup Matrix Bridge message handler for E2EE messages
    func setupMatrixMessageHandler() {
        MatrixBridgeService.shared.onMatrixMessage = { [weak self] conversationId, matrixMessage in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // 只處理當前會話的訊息
                guard conversationId == self.conversationId else { return }

                // 避免重複
                guard !self.messages.contains(where: { $0.id == matrixMessage.id }) else { return }

                // 轉換 Matrix 訊息為 Nova 訊息格式
                let novaMessage = MatrixBridgeService.shared.convertToNovaMessage(
                    matrixMessage,
                    conversationId: conversationId
                )

                // 添加到 UI
                self.messages.append(ChatMessage(from: novaMessage, currentUserId: self.currentUserId))

                // 清除打字指示器
                self.isOtherUserTyping = false

                #if DEBUG
                print("[ChatViewModel] Matrix E2EE message received: \(matrixMessage.id)")
                #endif
            }
        }

        // Matrix 打字指示器
        MatrixBridgeService.shared.onTypingIndicator = { [weak self] conversationId, userIds in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard conversationId == self.conversationId else { return }
                guard !userIds.contains(self.currentUserId) else { return }

                if !userIds.isEmpty {
                    self.startTypingIndicator()
                } else {
                    self.stopTypingIndicator()
                }
            }
        }

        #if DEBUG
        print("[ChatViewModel] Matrix message handler setup complete")
        #endif
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

    // MARK: - Send Text Message

    /// 發送文字訊息，優先使用 Matrix E2EE（如果可用）
    func sendMessage() async {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSending else { return }

        // Stop typing indicator
        chatService.sendTypingStop(conversationId: conversationId)

        // Add to UI immediately (optimistic update)
        let localMessage = ChatMessage(localText: trimmedText, isFromMe: true)
        messages.append(localMessage)

        messageText = ""

        // Send to server asynchronously
        isSending = true
        do {
            // 使用 sendSecureMessage，自動嘗試 Matrix E2EE
            // 如果 Matrix 不可用，會自動 fallback 到 REST API
            let sentMessage = try await chatService.sendSecureMessage(
                conversationId: conversationId,
                content: trimmedText,
                type: .text,
                preferE2EE: true  // 優先使用端到端加密
            )

            // Replace local message with server response
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                messages[index] = ChatMessage(from: sentMessage, currentUserId: currentUserId)
            }

            #if DEBUG
            let encryptionStatus = sentMessage.encryptionVersion == 3 ? "Matrix E2EE" : "REST API"
            print("[ChatViewModel] Message sent via \(encryptionStatus): \(sentMessage.id)")
            #endif

        } catch {
            // Send failed - mark message as failed (TODO: add retry UI)
            #if DEBUG
            print("[ChatViewModel] Failed to send message: \(error)")
            #endif
            // Could remove failed message or add retry button here
        }
        isSending = false
    }

    // MARK: - Send Image Message

    /// 完整圖片上傳流程：壓縮 → 上傳到 MediaService → 發送消息
    func sendImageMessage(_ image: UIImage) async {
        // 壓縮圖片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("[ChatViewModel] Failed to compress image")
            #endif
            error = "Failed to compress image"
            return
        }

        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, image: image)
        messages.append(localMessage)

        // 異步上傳並發送
        isUploadingImage = true

        do {
            // 1. 上傳圖片到 MediaService
            let filename = "chat_image_\(UUID().uuidString).jpg"
            let mediaUrl = try await mediaService.uploadImage(imageData: imageData, filename: filename)

            #if DEBUG
            print("[ChatViewModel] Image uploaded: \(mediaUrl)")
            #endif

            // 2. 發送帶 mediaUrl 的消息到聊天服務
            let sentMessage = try await chatService.sendMessage(
                conversationId: conversationId,
                content: mediaUrl,  // 圖片 URL 作為內容
                type: .image,
                mediaUrl: mediaUrl
            )

            // 3. 替換本地消息為服務器返回的消息
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                // 保留本地圖片用於顯示，同時更新消息 ID
                var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                updatedMessage.image = image  // 保留本地圖片
                messages[index] = updatedMessage
            }

            #if DEBUG
            print("[ChatViewModel] Image message sent: \(sentMessage.id)")
            #endif

        } catch {
            #if DEBUG
            print("[ChatViewModel] Failed to send image: \(error)")
            #endif

            // 上傳失敗 - 標記消息為失敗狀態
            self.error = "Failed to send image"

            // 可選：移除失敗的消息或添加重試按鈕
            // messages.removeAll { $0.id == localMessage.id }
        }

        isUploadingImage = false
    }

    // MARK: - Send Location Message

    /// 發送位置消息到會話
    func sendLocationMessage(_ location: CLLocationCoordinate2D) async {
        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, location: location)
        messages.append(localMessage)

        isSending = true

        do {
            // 使用 ChatService 的位置分享 API
            try await chatService.shareLocation(
                conversationId: conversationId,
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: nil
            )

            #if DEBUG
            print("[ChatViewModel] Location shared: \(location.latitude), \(location.longitude)")
            #endif

        } catch {
            #if DEBUG
            print("[ChatViewModel] Failed to share location: \(error)")
            #endif
            self.error = "Failed to share location"
        }

        isSending = false
    }

    // MARK: - Send Voice Message

    /// 發送語音消息
    func sendVoiceMessage(audioData: Data, duration: TimeInterval, url: URL) async {
        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(
            localText: "",
            isFromMe: true,
            audioData: audioData,
            audioDuration: duration,
            audioUrl: url
        )
        messages.append(localMessage)

        isSending = true

        do {
            // 1. 上傳音頻到 MediaService
            let filename = "voice_\(UUID().uuidString).m4a"
            let mediaUrl = try await mediaService.uploadAudio(audioData: audioData, filename: filename)

            #if DEBUG
            print("[ChatViewModel] Voice uploaded: \(mediaUrl)")
            #endif

            // 2. 發送帶 mediaUrl 的消息到聊天服務
            let sentMessage = try await chatService.sendMessage(
                conversationId: conversationId,
                content: String(format: "%.1f", duration),  // 時長作為內容（用於預覽）
                type: .audio,
                mediaUrl: mediaUrl
            )

            // 3. 替換本地消息為服務器返回的消息
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                updatedMessage.audioData = audioData
                updatedMessage.audioDuration = duration
                updatedMessage.audioUrl = url
                messages[index] = updatedMessage
            }

            #if DEBUG
            print("[ChatViewModel] Voice message sent: \(sentMessage.id)")
            #endif

        } catch {
            #if DEBUG
            print("[ChatViewModel] Failed to send voice: \(error)")
            #endif
            self.error = "Failed to send voice message"
        }

        isSending = false
    }

    // MARK: - Typing Indicator

    /// Send typing start indicator
    func sendTypingStart() {
        chatService.sendTypingStart(conversationId: conversationId)
    }

    /// Send typing stop indicator
    func sendTypingStop() {
        chatService.sendTypingStop(conversationId: conversationId)
    }

    /// Start typing indicator with auto-hide timer
    /// - Parameter userName: Optional username to display
    private func startTypingIndicator(userName: String? = nil) {
        isOtherUserTyping = true
        if let userName = userName {
            typingUserName = userName
        }

        // Cancel existing timer and start new one
        typingTimer?.invalidate()
        typingTimer = nil
        typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isOtherUserTyping = false
                self?.typingTimer = nil
            }
        }
    }

    /// Stop typing indicator and cancel timer
    private func stopTypingIndicator() {
        isOtherUserTyping = false
        typingTimer?.invalidate()
        typingTimer = nil
    }

    // MARK: - Cleanup

    /// Disconnect WebSocket when view disappears
    func cleanup() {
        // Clear all callbacks first to break any potential retain cycles
        chatService.onMessageReceived = nil
        chatService.onTypingIndicator = nil
        chatService.onReadReceipt = nil
        chatService.onConnectionStatusChanged = nil
        
        // Clear Matrix callbacks
        MatrixBridgeService.shared.onMatrixMessage = nil
        MatrixBridgeService.shared.onTypingIndicator = nil
        
        // Disconnect WebSocket
        chatService.disconnectWebSocket()
        
        // Clean up timer
        typingTimer?.invalidate()
        typingTimer = nil
        
        #if DEBUG
        print("[ChatViewModel] Cleanup completed for conversation \(conversationId)")
        #endif
    }

    deinit {
        // Clear callbacks synchronously to prevent retain cycles
        // Note: These closures might hold weak references to self,
        // but setting them to nil ensures they're released immediately
        chatService.onMessageReceived = nil
        chatService.onTypingIndicator = nil
        chatService.onReadReceipt = nil
        chatService.onConnectionStatusChanged = nil
        
        // Clear Matrix callbacks
        MatrixBridgeService.shared.onMatrixMessage = nil
        MatrixBridgeService.shared.onTypingIndicator = nil
        
        // Clean up timer
        typingTimer?.invalidate()
        
        // Disconnect WebSocket asynchronously (won't block deinit)
        let service = chatService
        Task { @MainActor in
            service.disconnectWebSocket()
        }
        
        #if DEBUG
        print("[ChatViewModel] deinit - resources released for conversation \(conversationId)")
        #endif
    }
}
