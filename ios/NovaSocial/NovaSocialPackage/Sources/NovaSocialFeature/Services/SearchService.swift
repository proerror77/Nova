import Foundation

/// Response structure for search API
private struct SearchResponse: Decodable {
    let users: [User]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case users
        case hasMore = "has_more"
    }
}

/// Service for searching content and users
final class SearchService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager

    init(httpClient: HTTPClientProtocol = HTTPClient(), cache: CacheManager = CacheManager()) {
        self.httpClient = httpClient
        self.cache = cache
    }

    /// Searches for users by query
    func searchUsers(query: String, page: Int = 0, limit: Int = 20) async throws -> [User] {
        guard !query.isEmpty else {
            return []
        }

        let cacheKey = "search_users_\(query)_page_\(page)"

        // Check cache first
        if let cached: [User] = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let response: SearchResponse = try await httpClient.request(endpoint: .searchUsers(query: query, page: page, limit: limit))

        // Cache the results
        cache.set(response.users, for: cacheKey)

        return response.users
    }
}
