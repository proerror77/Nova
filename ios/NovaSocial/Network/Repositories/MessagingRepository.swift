import Foundation

/// MessagingRepository - REST operations for conversations and messages
final class MessagingRepository: @unchecked Sendable {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor

    init(apiClient: APIClient? = nil) {
        let client = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.apiClient = client
        self.interceptor = RequestInterceptor(apiClient: client)
    }

    // MARK: - Conversations

    func createDirectConversation(userA: UUID, userB: UUID) async throws -> ConversationResponse {
        struct Body: Encodable { let user_a: UUID; let user_b: UUID }
        let endpoint = APIEndpoint(
            path: "/conversations",
            method: .post,
            body: AnyCodable(value: Body(user_a: userA, user_b: userB))
        )
        let response: ConversationResponse = try await interceptor.executeWithRetry(endpoint, authenticated: false)
        return response
    }

    func getConversation(id: UUID) async throws -> ConversationResponse {
        let endpoint = APIEndpoint(path: "/conversations/\(id.uuidString)", method: .get)
        let response: ConversationResponse = try await interceptor.executeWithRetry(endpoint, authenticated: false)
        return response
    }

    // MARK: - Messages

    func fetchMessages(conversationId: UUID, limit: Int? = nil, before: UUID? = nil) async throws -> [MessageDto] {
        var items: [URLQueryItem] = []
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let before { items.append(URLQueryItem(name: "before", value: before.uuidString)) }
        let endpoint = APIEndpoint(path: "/conversations/\(conversationId.uuidString)/messages", method: .get, queryItems: items)
        let list: [MessageDto] = try await interceptor.executeWithRetry(endpoint, authenticated: false)
        return list
    }

    func sendMessage(conversationId: UUID, senderId: UUID, plaintext: String, idempotencyKey: UUID = UUID()) async throws -> MessageDto {
        struct Body: Encodable {
            let sender_id: UUID
            let plaintext: String // ENC:v1:... or clear text for non-E2E
            let idempotency_key: UUID
        }
        let body = Body(sender_id: senderId, plaintext: plaintext, idempotency_key: idempotencyKey)
        let endpoint = APIEndpoint(
            path: "/conversations/\(conversationId.uuidString)/messages",
            method: .post,
            body: AnyCodable(value: body)
        )
        let resp: MessageDto = try await interceptor.executeWithRetry(endpoint, authenticated: false)
        return resp
    }
}
