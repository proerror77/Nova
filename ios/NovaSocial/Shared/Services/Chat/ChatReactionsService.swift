import Foundation

// MARK: - Chat Reactions Service
/// Handles message reaction operations for chat
/// Extracted from ChatService for better separation of concerns

final class ChatReactionsService {
    private let client = APIClient.shared

    // MARK: - Add Reaction

    /// Add emoji reaction to a message - prioritizes Matrix SDK
    @MainActor
    func addReaction(conversationId: String, messageId: String, emoji: String) async throws {
        // Prioritize Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            do {
                try await MatrixBridgeService.shared.addReaction(
                    conversationId: conversationId,
                    messageId: messageId,
                    emoji: emoji
                )
                #if DEBUG
                print("[ChatReactions] ✅ Reaction added via Matrix SDK: \(emoji) to message \(messageId)")
                #endif
                return
            } catch {
                #if DEBUG
                print("[ChatReactions] Matrix addReaction failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        let request = AddReactionRequest(emoji: emoji)
        let _: MessageReaction = try await client.request(
            endpoint: APIConfig.Chat.addReaction(messageId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatReactions] Reaction added via REST API: \(emoji) to message \(messageId)")
        #endif
    }

    // MARK: - Toggle Reaction

    /// Toggle emoji reaction (add if not exists, remove if exists) - prioritizes Matrix SDK
    @MainActor
    func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws {
        // Prioritize Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            do {
                try await MatrixBridgeService.shared.toggleReaction(
                    conversationId: conversationId,
                    messageId: messageId,
                    emoji: emoji
                )
                #if DEBUG
                print("[ChatReactions] ✅ Reaction toggled via Matrix SDK: \(emoji) for message \(messageId)")
                #endif
                return
            } catch {
                #if DEBUG
                print("[ChatReactions] Matrix toggleReaction failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API - check if reaction exists first
        let existingReactions = try await getReactions(conversationId: conversationId, messageId: messageId)
        let userId = KeychainService.shared.get(.userId) ?? ""

        if let existingReaction = existingReactions.reactions.first(where: { $0.emoji == emoji && $0.userId == userId }) {
            // Exists, delete it
            try await deleteReaction(conversationId: conversationId, messageId: messageId, reactionId: existingReaction.id)
        } else {
            // Doesn't exist, add it
            try await addReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
        }
    }

    // MARK: - Get Reactions

    /// Get all emoji reactions for a message - prioritizes Matrix SDK
    @MainActor
    func getReactions(conversationId: String, messageId: String) async throws -> GetReactionsResponse {
        // Prioritize Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            do {
                let matrixReactions = try await MatrixBridgeService.shared.getReactions(
                    conversationId: conversationId,
                    messageId: messageId
                )

                // Convert MatrixReaction to MessageReaction
                let reactions = matrixReactions.map { matrixReaction in
                    MessageReaction(
                        id: matrixReaction.id,
                        messageId: messageId,
                        userId: matrixReaction.senderId,
                        emoji: matrixReaction.emoji,
                        createdAt: matrixReaction.timestamp
                    )
                }

                #if DEBUG
                print("[ChatReactions] ✅ Fetched \(reactions.count) reactions via Matrix SDK for message \(messageId)")
                #endif

                return GetReactionsResponse(reactions: reactions, totalCount: reactions.count)
            } catch {
                #if DEBUG
                print("[ChatReactions] Matrix getReactions failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        let response: GetReactionsResponse = try await client.get(
            endpoint: APIConfig.Chat.getReactions(messageId)
        )

        #if DEBUG
        print("[ChatReactions] Fetched \(response.reactions.count) reactions via REST API for message \(messageId)")
        #endif

        return response
    }

    // MARK: - Delete Reaction

    /// Delete emoji reaction - prioritizes Matrix SDK
    @MainActor
    func deleteReaction(conversationId: String, messageId: String, reactionId: String) async throws {
        // Prioritize Matrix SDK (uses emoji as key)
        if MatrixBridgeService.shared.isInitialized {
            do {
                // In Matrix, we use emoji to identify reaction, not reactionId
                try await MatrixBridgeService.shared.removeReaction(
                    conversationId: conversationId,
                    messageId: messageId,
                    emoji: reactionId
                )
                #if DEBUG
                print("[ChatReactions] ✅ Reaction removed via Matrix SDK: \(reactionId)")
                #endif
                return
            } catch {
                #if DEBUG
                print("[ChatReactions] Matrix removeReaction failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.deleteReaction(messageId: messageId, reactionId: reactionId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatReactions] Reaction deleted via REST API: \(reactionId)")
        #endif
    }

    // MARK: - Deprecated Methods (backward compatibility)

    @available(*, deprecated, message: "Use addReaction(conversationId:messageId:emoji:) instead")
    @MainActor
    func addReaction(messageId: String, emoji: String) async throws -> MessageReaction {
        let request = AddReactionRequest(emoji: emoji)

        let reaction: MessageReaction = try await client.request(
            endpoint: APIConfig.Chat.addReaction(messageId),
            method: "POST",
            body: request
        )

        return reaction
    }

    @available(*, deprecated, message: "Use getReactions(conversationId:messageId:) instead")
    @MainActor
    func getReactions(messageId: String) async throws -> GetReactionsResponse {
        let response: GetReactionsResponse = try await client.get(
            endpoint: APIConfig.Chat.getReactions(messageId)
        )
        return response
    }

    @available(*, deprecated, message: "Use deleteReaction(conversationId:messageId:reactionId:) instead")
    @MainActor
    func deleteReaction(messageId: String, reactionId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.deleteReaction(messageId: messageId, reactionId: reactionId),
            method: "DELETE"
        )
    }
}
