import SwiftUI
import CoreLocation

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Dependencies
    // Use nonisolated(unsafe) to allow access in deinit
    // This is safe because ChatService handles its own thread safety
    nonisolated(unsafe) var chatService = ChatService()
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
    // Use nonisolated(unsafe) for timer to allow invalidation in deinit
    nonisolated(unsafe) var typingTimer: Timer?

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

    /// 發送文字訊息 - 使用 Matrix E2EE（端到端加密）
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
            // 使用 Matrix SDK 發送訊息（E2EE 端到端加密）
            let sentMessage = try await chatService.sendSecureMessage(
                conversationId: conversationId,
                content: trimmedText,
                type: .text
            )

            // Replace local message with server response
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                messages[index] = ChatMessage(from: sentMessage, currentUserId: currentUserId)
            }

            #if DEBUG
            print("[ChatViewModel] ✅ Message sent via Matrix E2EE: \(sentMessage.id)")
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

    /// 發送圖片訊息 - 使用 Matrix SDK
    func sendImageMessage(_ image: UIImage) async {
        // 壓縮圖片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("[ChatViewModel] ❌ Failed to compress image")
            #endif
            error = "Failed to compress image"
            return
        }

        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, image: image)
        messages.append(localMessage)

        isUploadingImage = true

        do {
            // 確保 Matrix 已初始化
            guard MatrixBridgeService.shared.isInitialized else {
                throw NSError(domain: "ChatViewModel", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Matrix service not initialized"
                ])
            }

            #if DEBUG
            print("[ChatViewModel] 📤 Sending image via Matrix SDK")
            #endif

            // 將圖片數據保存到臨時文件
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "chat_image_\(UUID().uuidString).jpg"
            let tempFileURL = tempDir.appendingPathComponent(filename)
            try imageData.write(to: tempFileURL)

            // 使用 Matrix SDK 發送圖片（本地文件 URL）
            let eventId = try await MatrixBridgeService.shared.sendMessage(
                conversationId: conversationId,
                content: "",
                mediaURL: tempFileURL,
                mimeType: "image/jpeg"
            )

            // 清理臨時文件
            try? FileManager.default.removeItem(at: tempFileURL)

            let senderId = KeychainService.shared.get(.userId) ?? ""
            let sentMessage = Message(
                id: eventId,
                conversationId: conversationId,
                senderId: senderId,
                content: "",
                type: .image,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3  // Matrix E2EE
            )

            #if DEBUG
            print("[ChatViewModel] ✅ Image sent via Matrix: \(eventId)")
            #endif

            // 替換本地訊息為伺服器返回的訊息
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                updatedMessage.image = image  // 保留本地圖片用於顯示
                messages[index] = updatedMessage
            }

        } catch {
            #if DEBUG
            print("[ChatViewModel] ❌ Failed to send image: \(error)")
            #endif
            self.error = "Failed to send image"
            // 移除失敗的本地訊息
            messages.removeAll { $0.id == localMessage.id }
        }

        isUploadingImage = false
    }

    // MARK: - Send Location Message

    /// 發送位置訊息 - 使用 Matrix SDK
    func sendLocationMessage(_ location: CLLocationCoordinate2D) async {
        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, location: location)
        messages.append(localMessage)

        isSending = true

        do {
            // 確保 Matrix 已初始化
            guard MatrixBridgeService.shared.isInitialized else {
                throw NSError(domain: "ChatViewModel", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Matrix service not initialized"
                ])
            }

            #if DEBUG
            print("[ChatViewModel] 📍 Sending location via Matrix SDK")
            #endif

            // 使用 Matrix SDK 發送位置訊息
            let eventId = try await MatrixBridgeService.shared.sendLocation(
                conversationId: conversationId,
                latitude: location.latitude,
                longitude: location.longitude
            )

            let senderId = KeychainService.shared.get(.userId) ?? ""
            let sentMessage = Message(
                id: eventId,
                conversationId: conversationId,
                senderId: senderId,
                content: "geo:\(location.latitude),\(location.longitude)",
                type: .location,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3  // Matrix E2EE
            )

            #if DEBUG
            print("[ChatViewModel] ✅ Location sent via Matrix: \(eventId)")
            #endif

            // 替換本地訊息為伺服器返回的訊息
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                updatedMessage.location = location
                messages[index] = updatedMessage
            }

        } catch {
            #if DEBUG
            print("[ChatViewModel] ❌ Failed to send location: \(error)")
            #endif
            self.error = "Failed to share location"
            // 移除失敗的本地訊息
            messages.removeAll { $0.id == localMessage.id }
        }

        isSending = false
    }

    // MARK: - Send Voice Message

    /// 發送語音訊息 - 使用 Matrix SDK
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
            // 確保 Matrix 已初始化
            guard MatrixBridgeService.shared.isInitialized else {
                throw NSError(domain: "ChatViewModel", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Matrix service not initialized"
                ])
            }

            #if DEBUG
            print("[ChatViewModel] 📤 Sending voice via Matrix SDK: \(url)")
            #endif

            // 使用 Matrix SDK 發送語音訊息（本地文件 URL）
            let eventId = try await MatrixBridgeService.shared.sendMessage(
                conversationId: conversationId,
                content: String(format: "%.1f", duration),
                mediaURL: url,
                mimeType: "audio/mp4"
            )

            let senderId = KeychainService.shared.get(.userId) ?? ""
            let sentMessage = Message(
                id: eventId,
                conversationId: conversationId,
                senderId: senderId,
                content: String(format: "%.1f", duration),
                type: .audio,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3  // Matrix E2EE
            )

            #if DEBUG
            print("[ChatViewModel] ✅ Voice sent via Matrix: \(eventId)")
            #endif

            // 替換本地訊息為伺服器返回的訊息
            if let index = messages.firstIndex(where: { $0.id == localMessage.id }) {
                var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId)
                updatedMessage.audioData = audioData
                updatedMessage.audioDuration = duration
                updatedMessage.audioUrl = url
                messages[index] = updatedMessage
            }

        } catch {
            #if DEBUG
            print("[ChatViewModel] ❌ Failed to send voice: \(error)")
            #endif
            self.error = "Failed to send voice message"
            // 移除失敗的本地訊息
            messages.removeAll { $0.id == localMessage.id }
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
        // Clean up timer synchronously (timers are thread-safe)
        typingTimer?.invalidate()
        
        // Capture chatService reference for async cleanup
        let service = chatService
        let convId = conversationId
        
        // All MainActor-isolated cleanup must be async
        Task { @MainActor in
            // Clear ChatService callbacks
            service.onMessageReceived = nil
            service.onTypingIndicator = nil
            service.onReadReceipt = nil
            service.onConnectionStatusChanged = nil
            
            // Disconnect WebSocket
            service.disconnectWebSocket()
            
            // Clear Matrix callbacks
            MatrixBridgeService.shared.onMatrixMessage = nil
            MatrixBridgeService.shared.onTypingIndicator = nil
            
            #if DEBUG
            print("[ChatViewModel] deinit - resources released for conversation \(convId)")
            #endif
        }
    }
}
