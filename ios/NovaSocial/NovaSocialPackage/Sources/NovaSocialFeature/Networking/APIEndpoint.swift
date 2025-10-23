import Foundation

/// API endpoints for Nova Social backend
enum APIEndpoint: Sendable {
    case feed(page: Int, limit: Int)
    case users(id: String)
    case searchUsers(query: String, page: Int, limit: Int)
    case notifications(page: Int, limit: Int)

    var description: String {
        switch self {
        case .feed:
            return "/feed"
        case .users(let id):
            return "/api/v1/users/\(id)"
        case .searchUsers:
            return "/api/v1/search/users"
        case .notifications:
            return "/notifications"
        }
    }

    /// Builds the complete URL for this endpoint
    var url: URL {
        let baseURL = APIConfig.baseURL
        switch self {
        case .feed(let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/feed"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url!

        case .users(let id):
            return baseURL.appendingPathComponent("/users/\(id)")

        case .searchUsers(let query, let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/search/users"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
            return components.url!

        case .notifications(let page, let limit):
            var components = URLComponents(url: baseURL.appendingPathComponent("/notifications"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
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
