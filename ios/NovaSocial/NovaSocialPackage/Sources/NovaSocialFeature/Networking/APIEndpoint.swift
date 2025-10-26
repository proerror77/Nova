import Foundation

/// API endpoints for Nova Social backend
enum APIEndpoint: Sendable {
    case feed(page: Int, limit: Int)
    case users(id: String)
    case searchUsers(query: String, page: Int, limit: Int)
    case notifications(page: Int, limit: Int)
    case conversations(page: Int, limit: Int)
    case createConversation
    case conversation(id: String)
    case messages(conversationId: String, limit: Int, offset: Int)
    case sendMessage(conversationId: String)
    case searchMessages(conversationId: String, query: String, limit: Int, offset: Int, sortBy: String)

    var description: String {
        switch self {
        case .feed:
            return "/api/v1/feed"
        case .users(let id):
            return "/api/v1/users/\(id)"
        case .searchUsers:
            return "/api/v1/search/users"
        case .notifications:
            return "/api/v1/notifications"
        case .conversations:
            return "/api/v1/conversations"
        case .createConversation:
            return "/api/v1/conversations"
        case .conversation(let id):
            return "/api/v1/conversations/\(id)"
        case .messages(let conversationId, _, _):
            return "/api/v1/conversations/\(conversationId)/messages"
        case .sendMessage(let conversationId):
            return "/api/v1/conversations/\(conversationId)/messages"
        case .searchMessages(let conversationId, _, _, _, _):
            return "/api/v1/conversations/\(conversationId)/messages/search"
        }
    }

    /// Builds the complete URL for this endpoint
    var url: URL {
        let baseURL = APIConfig.baseURL
        switch self {
        case .feed(let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/feed"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url!

        case .users(let id):
            return baseURL.appendingPathComponent("/api/v1/users/\(id)")

        case .searchUsers(let query, let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/search/users"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url!

        case .notifications(let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/notifications"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url!

        case .conversations(let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/conversations"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url!

        case .createConversation:
            return baseURL.appendingPathComponent("/api/v1/conversations")

        case .conversation(let id):
            return baseURL.appendingPathComponent("/api/v1/conversations/\(id)")

        case .messages(let conversationId, let limit, let offset):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/conversations/\(conversationId)/messages"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            return components.url!

        case .sendMessage(let conversationId):
            return baseURL.appendingPathComponent("/api/v1/conversations/\(conversationId)/messages")

        case .searchMessages(let conversationId, let query, let limit, let offset, let sortBy):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/conversations/\(conversationId)/messages/search"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "sort_by", value: sortBy)
            ]
            return components.url!
        }
    }

    /// Builds URLRequest for this endpoint
    var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = APIConfig.requestTimeout

        let headers = APIConfig.makeHeaders()
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        return request
    }
}
