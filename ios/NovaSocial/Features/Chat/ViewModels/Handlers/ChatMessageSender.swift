import SwiftUI
import CoreLocation

/// Handles all message sending operations for chat
/// Extracted from ChatViewModel to follow Single Responsibility Principle
@MainActor
final class ChatMessageSender {
    // MARK: - Dependencies

    private let chatService: ChatService
    private let conversationId: String

    // MARK: - Callbacks

    /// Called when a message should be added to the UI (optimistic update)
    var onMessageAdded: ((ChatMessage) -> Void)?

    /// Called when a message should be updated (after server confirmation)
    var onMessageUpdated: ((String, ChatMessage) -> Void)?

    /// Called when a message should be removed (on failure)
    var onMessageRemoved: ((String) -> Void)?

    /// Called when sending state changes
    var onSendingStateChanged: ((Bool) -> Void)?

    /// Called when image uploading state changes
    var onUploadingStateChanged: ((Bool) -> Void)?

    /// Called when an error occurs
    var onError: ((String) -> Void)?

    /// Get current user ID
    var currentUserId: () -> String = { KeychainService.shared.get(.userId) ?? "unknown" }

    // MARK: - Init

    init(chatService: ChatService, conversationId: String) {
        self.chatService = chatService
        self.conversationId = conversationId
    }

    // MARK: - Send Text Message

    /// 發送文字訊息 - 使用 Matrix E2EE（端到端加密）
    /// - Parameters:
    ///   - text: The message text to send
    /// - Returns: Whether sending was initiated successfully
    @discardableResult
    func sendTextMessage(_ text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        // Stop typing indicator
        chatService.sendTypingStop(conversationId: conversationId)

        // Add to UI immediately (optimistic update)
        let localMessage = ChatMessage(localText: trimmedText, isFromMe: true)
        onMessageAdded?(localMessage)

        // Send to server asynchronously
        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            // 使用 Matrix SDK 發送訊息（E2EE 端到端加密）
            let sentMessage = try await chatService.sendSecureMessage(
                conversationId: conversationId,
                content: trimmedText,
                type: .text
            )

            // Replace local message with server response
            let confirmedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId())
            onMessageUpdated?(localMessage.id, confirmedMessage)

            #if DEBUG
            print("[ChatMessageSender] ✅ Message sent via Matrix E2EE: \(sentMessage.id)")
            #endif

            return true

        } catch {
            #if DEBUG
            print("[ChatMessageSender] Failed to send message: \(error)")
            #endif
            // Could remove failed message or add retry button here
            return false
        }
    }

    // MARK: - Send Image Message

    /// 發送圖片訊息 - 使用 Matrix SDK
    func sendImageMessage(_ image: UIImage) async {
        // 壓縮圖片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("[ChatMessageSender] ❌ Failed to compress image")
            #endif
            onError?("Failed to compress image")
            return
        }

        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, image: image)
        onMessageAdded?(localMessage)

        onUploadingStateChanged?(true)
        defer { onUploadingStateChanged?(false) }

        do {
            // 確保 Matrix 已初始化
            guard MatrixBridgeService.shared.isInitialized else {
                throw NSError(domain: "ChatMessageSender", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Matrix service not initialized"
                ])
            }

            #if DEBUG
            print("[ChatMessageSender] 📤 Sending image via Matrix SDK")
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

            let sentMessage = Message(
                id: eventId,
                conversationId: conversationId,
                senderId: currentUserId(),
                content: "",
                type: .image,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3  // Matrix E2EE
            )

            #if DEBUG
            print("[ChatMessageSender] ✅ Image sent via Matrix: \(eventId)")
            #endif

            // 替換本地訊息為伺服器返回的訊息
            var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId())
            updatedMessage.image = image  // 保留本地圖片用於顯示
            onMessageUpdated?(localMessage.id, updatedMessage)

        } catch {
            #if DEBUG
            print("[ChatMessageSender] ❌ Failed to send image: \(error)")
            #endif
            onError?("Failed to send image")
            // 移除失敗的本地訊息
            onMessageRemoved?(localMessage.id)
        }
    }

    // MARK: - Send Location Message

    /// 發送位置訊息 - 使用 Matrix SDK
    func sendLocationMessage(_ location: CLLocationCoordinate2D) async {
        // 立即添加到本地 UI（樂觀更新）
        let localMessage = ChatMessage(localText: "", isFromMe: true, location: location)
        onMessageAdded?(localMessage)

        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            // 確保 Matrix 已初始化
            guard MatrixBridgeService.shared.isInitialized else {
                throw NSError(domain: "ChatMessageSender", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Matrix service not initialized"
                ])
            }

            #if DEBUG
            print("[ChatMessageSender] 📍 Sending location via Matrix SDK")
            #endif

            // 使用 Matrix SDK 發送位置訊息
            let eventId = try await MatrixBridgeService.shared.sendLocation(
                conversationId: conversationId,
                latitude: location.latitude,
                longitude: location.longitude
            )

            let sentMessage = Message(
                id: eventId,
                conversationId: conversationId,
                senderId: currentUserId(),
                content: "geo:\(location.latitude),\(location.longitude)",
                type: .location,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3  // Matrix E2EE
            )

            #if DEBUG
            print("[ChatMessageSender] ✅ Location sent via Matrix: \(eventId)")
            #endif

            // 替換本地訊息為伺服器返回的訊息
            var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId())
            updatedMessage.location = location
            onMessageUpdated?(localMessage.id, updatedMessage)

        } catch {
            #if DEBUG
            print("[ChatMessageSender] ❌ Failed to send location: \(error)")
            #endif
            onError?("Failed to share location")
            // 移除失敗的本地訊息
            onMessageRemoved?(localMessage.id)
        }
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
        onMessageAdded?(localMessage)

        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            // 確保 Matrix 已初始化
            guard MatrixBridgeService.shared.isInitialized else {
                throw NSError(domain: "ChatMessageSender", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Matrix service not initialized"
                ])
            }

            #if DEBUG
            print("[ChatMessageSender] 📤 Sending voice via Matrix SDK: \(url)")
            #endif

            // 使用 Matrix SDK 發送語音訊息（本地文件 URL）
            let eventId = try await MatrixBridgeService.shared.sendMessage(
                conversationId: conversationId,
                content: String(format: "%.1f", duration),
                mediaURL: url,
                mimeType: "audio/mp4"
            )

            let sentMessage = Message(
                id: eventId,
                conversationId: conversationId,
                senderId: currentUserId(),
                content: String(format: "%.1f", duration),
                type: .audio,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3  // Matrix E2EE
            )

            #if DEBUG
            print("[ChatMessageSender] ✅ Voice sent via Matrix: \(eventId)")
            #endif

            // 替換本地訊息為伺服器返回的訊息
            var updatedMessage = ChatMessage(from: sentMessage, currentUserId: currentUserId())
            updatedMessage.audioData = audioData
            updatedMessage.audioDuration = duration
            updatedMessage.audioUrl = url
            onMessageUpdated?(localMessage.id, updatedMessage)

        } catch {
            #if DEBUG
            print("[ChatMessageSender] ❌ Failed to send voice: \(error)")
            #endif
            onError?("Failed to send voice message")
            // 移除失敗的本地訊息
            onMessageRemoved?(localMessage.id)
        }
    }
}
