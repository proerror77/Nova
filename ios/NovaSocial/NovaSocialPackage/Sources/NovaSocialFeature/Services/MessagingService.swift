import Foundation

/// Response structure for conversation list
private struct ConversationsResponse: Decodable {
    let conversations: [Conversation]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case conversations
        case hasMore = "has_more"
    }
}

/// Response structure for message list
private struct MessagesResponse: Decodable {
    let messages: [Message]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case messages
        case total
        case hasMore = "has_more"
    }
}

/// Response structure for message search results
private struct MessageSearchResponse: Decodable {
    let results: [MessageSearchResult]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case results
        case total
        case hasMore = "has_more"
    }
}

/// Service for managing messaging and conversations
final class MessagingService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager

    init(httpClient: HTTPClientProtocol = HTTPClient(), cache: CacheManager = CacheManager()) {
        self.httpClient = httpClient
        self.cache = cache
    }

    // MARK: - Conversation Management

    /// Fetches the list of conversations for the current user
    func getConversations(page: Int = 0, limit: Int = 20) async throws -> [Conversation] {
        let cacheKey = "conversations_page_\(page)"

        // Check cache first
        if let cached: [Conversation] = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let response: ConversationsResponse = try await httpClient.request(
            endpoint: .conversations(page: page, limit: limit)
        )

        // Cache the results
        cache.set(response.conversations, for: cacheKey)

        return response.conversations
    }

    /// Fetches a specific conversation by ID
    func getConversation(id: String) async throws -> Conversation {
        let cacheKey = "conversation_\(id)"

        // Check cache first
        if let cached: Conversation = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let conversation: Conversation = try await httpClient.request(
            endpoint: .conversation(id: id)
        )

        // Cache the result
        cache.set(conversation, for: cacheKey)

        return conversation
    }

    /// Creates a new conversation
    /// Note: For MVP, this is simulated. Full implementation requires POST support in HTTPClient
    func createConversation(participantIds: [String], name: String? = nil) async throws -> Conversation {
        guard !participantIds.isEmpty else {
            throw MessagingError.emptyParticipants
        }

        // For MVP, simulate conversation creation
        // TODO: Implement real API endpoint POST /conversations
        let newConversation = Conversation(
            id: UUID().uuidString,
            name: name,
            participantCount: participantIds.count + 1, // +1 for current user
            lastMessage: nil,
            lastMessageAt: nil,
            lastMessageSenderName: nil,
            unreadCount: 0,
            isGroup: participantIds.count > 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            participants: nil
        )

        // Clear conversations cache
        cache.clearAll()

        return newConversation
    }

    // MARK: - Message Management

    /// Fetches message history for a conversation
    func getMessages(conversationId: String, limit: Int = 20, offset: Int = 0) async throws -> [Message] {
        let cacheKey = "messages_\(conversationId)_\(offset)_\(limit)"

        // Check cache first
        if let cached: [Message] = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let response: MessagesResponse = try await httpClient.request(
            endpoint: .messages(conversationId: conversationId, limit: limit, offset: offset)
        )

        // Cache the results
        cache.set(response.messages, for: cacheKey)

        return response.messages
    }

    /// Sends a message to a conversation
    /// Note: For MVP, this is simulated. Full implementation requires POST support in HTTPClient
    func sendMessage(conversationId: String, content: String) async throws -> SendMessageResponse {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MessagingError.emptyMessage
        }

        guard content.count <= Self.maxMessageLength else {
            throw MessagingError.messageTooLong(maxLength: Self.maxMessageLength)
        }

        // For MVP, simulate message sending
        // TODO: Implement real API endpoint POST /conversations/:id/messages
        let response = SendMessageResponse(
            id: UUID().uuidString,
            sequenceNumber: Int.random(in: 1...10000),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        // Clear message cache for this conversation
        cache.clearAll()

        return response
    }

    /// Searches messages in a conversation
    func searchMessages(
        conversationId: String,
        query: String,
        limit: Int = 20,
        offset: Int = 0,
        sortBy: String = "recent"
    ) async throws -> [MessageSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MessagingError.emptySearchQuery
        }

        let cacheKey = "search_\(conversationId)_\(query)_\(offset)_\(limit)_\(sortBy)"

        // Check cache first
        if let cached: [MessageSearchResult] = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let response: MessageSearchResponse = try await httpClient.request(
            endpoint: .searchMessages(
                conversationId: conversationId,
                query: query,
                limit: limit,
                offset: offset,
                sortBy: sortBy
            )
        )

        // Cache the results
        cache.set(response.results, for: cacheKey)

        return response.results
    }

    /// Marks a conversation as read up to a specific sequence number
    /// Note: For MVP, this is simulated
    func markAsRead(conversationId: String, lastReadSequence: Int) async throws {
        // For MVP, simulate marking as read
        // TODO: Implement real API endpoint POST /conversations/:id/mark-read

        // Clear unread count from cache
        cache.clear(for: "conversation_\(conversationId)")
    }

    /// Recalls a message
    /// Note: For MVP, this is simulated
    func recallMessage(conversationId: String, messageId: String) async throws {
        // For MVP, simulate message recall
        // TODO: Implement real API endpoint DELETE /conversations/:id/messages/:messageId or PUT with recall

        // Clear cache
        cache.clearAll()
    }

    /// Clears all messaging-related caches
    func clearCache() {
        cache.clearAll()
    }

    // MARK: - Constants

    static let maxMessageLength: Int = 5000
}

// MARK: - Error Types

enum MessagingError: LocalizedError {
    case emptyMessage
    case messageTooLong(maxLength: Int)
    case emptyParticipants
    case emptySearchQuery
    case conversationNotFound
    case messageNotFound
    case networkError
    case serverError

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Message cannot be empty"
        case .messageTooLong(let maxLength):
            return "Message is too long (max \(maxLength) characters)"
        case .emptyParticipants:
            return "Conversation must have at least one participant"
        case .emptySearchQuery:
            return "Search query cannot be empty"
        case .conversationNotFound:
            return "Conversation not found"
        case .messageNotFound:
            return "Message not found"
        case .networkError:
            return "Network error. Please try again"
        case .serverError:
            return "Server error. Please try again later"
        }
    }
}

