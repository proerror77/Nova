import Foundation

// MARK: - Message Operations Extension

extension MatrixBridgeService {

    // MARK: - Send Operations

    /// Send message via Matrix (E2EE)
    func sendMessage(
        conversationId: String,
        content: String,
        mediaURL: URL? = nil,
        mimeType: String? = nil
    ) async throws -> String {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)

        let eventId: String
        if let mediaURL = mediaURL, let mimeType = mimeType {
            eventId = try await matrixService.sendMedia(
                roomId: roomId,
                mediaURL: mediaURL,
                mimeType: mimeType,
                caption: content.isEmpty ? nil : content
            )
        } else {
            eventId = try await matrixService.sendMessage(
                roomId: roomId,
                content: content
            )
        }

        #if DEBUG
        print("[MatrixBridge] Sent message \(eventId) to room \(roomId)")
        #endif

        return eventId
    }

    /// Send location via Matrix (E2EE)
    func sendLocation(
        conversationId: String,
        latitude: Double,
        longitude: Double,
        description: String? = nil
    ) async throws -> String {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        // TODO: Implement location sharing via Matrix
        // For now, send as a text message with location coordinates
        let locationText = description ?? "Location: \(latitude), \(longitude)"
        return try await sendMessage(conversationId: conversationId, content: locationText)
    }

    // MARK: - Read Operations

    /// Get messages for a conversation via Matrix
    func getMessages(
        conversationId: String,
        limit: Int = 50,
        from: String? = nil
    ) async throws -> [MatrixMessage] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.subscribeToRoomTimeline(roomId: roomId)
        return try await matrixService.getRoomMessages(roomId: roomId, limit: limit, from: from)
    }

    func stopListening(conversationId: String) async {
        guard isInitialized else { return }
        guard let roomId = try? await resolveRoomId(for: conversationId) else { return }
        matrixService.unsubscribeFromRoomTimeline(roomId: roomId)
    }

    // MARK: - Typing & Read Status

    /// Set typing indicator for a conversation
    func setTyping(conversationId: String, isTyping: Bool) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.setTyping(roomId: roomId, isTyping: isTyping)
    }

    /// Mark conversation as read
    func markAsRead(conversationId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.markRoomAsRead(roomId: roomId)
    }

    // MARK: - Edit/Delete Operations

    /// Edit a message in a conversation
    func editMessage(conversationId: String, messageId: String, newContent: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.editMessage(roomId: roomId, eventId: messageId, newContent: newContent)

        #if DEBUG
        print("[MatrixBridge] Edited message \(messageId) in conversation \(conversationId)")
        #endif
    }

    /// Delete/redact a message in a conversation
    func deleteMessage(conversationId: String, messageId: String, reason: String? = nil) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.redactMessage(roomId: roomId, eventId: messageId, reason: reason)

        #if DEBUG
        print("[MatrixBridge] Deleted message \(messageId) in conversation \(conversationId)")
        #endif
    }

    /// Recall (unsend) a message - same as delete but with different semantic
    func recallMessage(conversationId: String, messageId: String) async throws {
        try await deleteMessage(conversationId: conversationId, messageId: messageId, reason: "Message recalled by sender")
    }

    // MARK: - Reactions

    /// Toggle reaction on a message (add if not present, remove if present)
    func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.toggleReaction(roomId: roomId, eventId: messageId, emoji: emoji)

        #if DEBUG
        print("[MatrixBridge] Toggled reaction \(emoji) on message \(messageId)")
        #endif
    }

    /// Add a reaction to a message
    func addReaction(conversationId: String, messageId: String, emoji: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.sendReaction(roomId: roomId, eventId: messageId, emoji: emoji)

        #if DEBUG
        print("[MatrixBridge] Added reaction \(emoji) to message \(messageId)")
        #endif
    }

    /// Remove a reaction from a message (uses toggle since Matrix doesn't have direct remove)
    func removeReaction(conversationId: String, messageId: String, emoji: String) async throws {
        // In Matrix, toggleReaction will remove if already present
        try await toggleReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
    }

    /// Get reactions for a message
    func getReactions(conversationId: String, messageId: String) async throws -> [MatrixReaction] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        return try await matrixService.getReactions(roomId: roomId, eventId: messageId)
    }
}
