import SwiftUI

/// Handles all message sending operations for group chat
/// Follows ChatMessageSender pattern for consistency
@MainActor
final class GroupChatMessageSender {
    // MARK: - Dependencies

    private let matrixBridge = MatrixBridgeService.shared
    private let conversationId: String

    // MARK: - Callbacks

    /// Called when a message should be added to the UI (optimistic update)
    var onMessageAdded: ((GroupChatUIMessage) -> Void)?

    /// Called when a message should be updated (after server confirmation)
    var onMessageUpdated: ((String, GroupChatUIMessage) -> Void)?

    /// Called when a message should be removed (on failure)
    var onMessageRemoved: ((String) -> Void)?

    /// Called when sending state changes
    var onSendingStateChanged: ((Bool) -> Void)?

    /// Called when an error occurs
    var onError: ((String) -> Void)?

    /// Get current user info for message display
    var getCurrentUserInfo: () -> (id: String, name: String, avatarUrl: String?) = {
        let userId = KeychainService.shared.get(.userId) ?? "unknown"
        let name = AuthenticationManager.shared.currentUser?.username ?? "Me"
        let avatarUrl = AuthenticationManager.shared.currentUser?.avatarUrl
        return (id: userId, name: name, avatarUrl: avatarUrl)
    }

    // MARK: - Init

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    // MARK: - Send Text Message

    /// Send a text message via Matrix E2EE
    @discardableResult
    func sendTextMessage(_ text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        let userInfo = getCurrentUserInfo()

        // Add to UI immediately (optimistic update)
        let localMessage = GroupChatUIMessage(
            localText: trimmedText,
            senderId: userInfo.id,
            senderName: userInfo.name,
            senderAvatarUrl: userInfo.avatarUrl,
            isFromMe: true
        )
        onMessageAdded?(localMessage)

        // Send to server
        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            // Ensure Matrix is initialized
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Send via Matrix
            let eventId = try await matrixBridge.sendMessage(
                conversationId: conversationId,
                content: trimmedText
            )

            // Create confirmed message with server ID
            let confirmedMessage = GroupChatUIMessage(
                localText: trimmedText,
                senderId: userInfo.id,
                senderName: userInfo.name,
                senderAvatarUrl: userInfo.avatarUrl,
                isFromMe: true
            )

            onMessageUpdated?(localMessage.id, confirmedMessage)

            #if DEBUG
            print("[GroupChatMessageSender] ✅ Message sent via Matrix: \(eventId)")
            #endif

            return true

        } catch {
            #if DEBUG
            print("[GroupChatMessageSender] ❌ Failed to send message: \(error)")
            #endif
            onError?("Failed to send message")
            return false
        }
    }

    // MARK: - Send Image Message

    /// Send an image message via Matrix
    func sendImageMessage(data: Data, mimeType: String = "image/jpeg") async {
        let userInfo = getCurrentUserInfo()

        // Create local message with image
        var localMessage = GroupChatUIMessage(
            localText: "",
            senderId: userInfo.id,
            senderName: userInfo.name,
            senderAvatarUrl: userInfo.avatarUrl,
            isFromMe: true
        )
        localMessage.image = UIImage(data: data)
        onMessageAdded?(localMessage)

        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Save to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let ext = mimeType == "image/png" ? "png" : "jpg"
            let tempFileURL = tempDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try data.write(to: tempFileURL)

            // Send via Matrix
            let eventId = try await matrixBridge.sendMessage(
                conversationId: conversationId,
                content: "Image",
                mediaURL: tempFileURL,
                mimeType: mimeType
            )

            // Cleanup temp file
            try? FileManager.default.removeItem(at: tempFileURL)

            // Update message with confirmed ID
            var confirmedMessage = GroupChatUIMessage(
                localText: "",
                senderId: userInfo.id,
                senderName: userInfo.name,
                senderAvatarUrl: userInfo.avatarUrl,
                isFromMe: true
            )
            confirmedMessage.image = UIImage(data: data)
            onMessageUpdated?(localMessage.id, confirmedMessage)

            #if DEBUG
            print("[GroupChatMessageSender] ✅ Image sent via Matrix: \(eventId)")
            #endif

        } catch {
            #if DEBUG
            print("[GroupChatMessageSender] ❌ Failed to send image: \(error)")
            #endif
            onError?("Failed to send image")
            onMessageRemoved?(localMessage.id)
        }
    }

    // MARK: - Send Voice Message

    /// Send a voice message via Matrix
    func sendVoiceMessage(data: Data, duration: TimeInterval) async {
        let userInfo = getCurrentUserInfo()

        // Create local message
        let localMessage = GroupChatUIMessage(
            localText: "",
            senderId: userInfo.id,
            senderName: userInfo.name,
            senderAvatarUrl: userInfo.avatarUrl,
            isFromMe: true,
            audioData: data,
            audioDuration: duration
        )
        onMessageAdded?(localMessage)

        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Save to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")
            try data.write(to: tempFileURL)

            // Send via Matrix
            let eventId = try await matrixBridge.sendMessage(
                conversationId: conversationId,
                content: "Voice message (\(Int(duration))s)",
                mediaURL: tempFileURL,
                mimeType: "audio/mp4"
            )

            // Cleanup temp file
            try? FileManager.default.removeItem(at: tempFileURL)

            // Update message with confirmed ID
            let confirmedMessage = GroupChatUIMessage(
                localText: "",
                senderId: userInfo.id,
                senderName: userInfo.name,
                senderAvatarUrl: userInfo.avatarUrl,
                isFromMe: true,
                audioData: data,
                audioDuration: duration
            )
            onMessageUpdated?(localMessage.id, confirmedMessage)

            #if DEBUG
            print("[GroupChatMessageSender] ✅ Voice message sent via Matrix: \(eventId)")
            #endif

        } catch {
            #if DEBUG
            print("[GroupChatMessageSender] ❌ Failed to send voice message: \(error)")
            #endif
            onError?("Failed to send voice message")
            onMessageRemoved?(localMessage.id)
        }
    }

    // MARK: - Send File Message

    /// Send a file message via Matrix
    func sendFileMessage(data: Data, filename: String, mimeType: String) async {
        let userInfo = getCurrentUserInfo()

        // Create local message
        let localMessage = GroupChatUIMessage(
            localText: filename,
            senderId: userInfo.id,
            senderName: userInfo.name,
            senderAvatarUrl: userInfo.avatarUrl,
            isFromMe: true
        )
        onMessageAdded?(localMessage)

        onSendingStateChanged?(true)
        defer { onSendingStateChanged?(false) }

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Save to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(filename)
            try data.write(to: tempFileURL)

            // Send via Matrix
            let eventId = try await matrixBridge.sendMessage(
                conversationId: conversationId,
                content: filename,
                mediaURL: tempFileURL,
                mimeType: mimeType
            )

            // Cleanup temp file
            try? FileManager.default.removeItem(at: tempFileURL)

            // Update message with confirmed ID
            let confirmedMessage = GroupChatUIMessage(
                localText: filename,
                senderId: userInfo.id,
                senderName: userInfo.name,
                senderAvatarUrl: userInfo.avatarUrl,
                isFromMe: true
            )
            onMessageUpdated?(localMessage.id, confirmedMessage)

            #if DEBUG
            print("[GroupChatMessageSender] ✅ File sent via Matrix: \(eventId)")
            #endif

        } catch {
            #if DEBUG
            print("[GroupChatMessageSender] ❌ Failed to send file: \(error)")
            #endif
            onError?("Failed to send file")
            onMessageRemoved?(localMessage.id)
        }
    }
}
