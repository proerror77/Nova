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

/// Service for searching content and users with debounce protection
actor SearchService {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager
    private let debounceDelay: UInt64
    private var currentRequestId: UUID?

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        cache: CacheManager = CacheManager(),
        debounceDelay: UInt64 = 300_000_000 // 300ms
    ) {
        self.httpClient = httpClient
        self.cache = cache
        self.debounceDelay = debounceDelay
    }

    /// Searches for users by query with caching and debounce
    func searchUsers(query: String, page: Int = 0, limit: Int = 20) async throws -> [User] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let cacheKey = "search_users_\(trimmedQuery)_page_\(page)"

        if let cached: [User] = cache.get(for: cacheKey) {
            return cached
        }

        let requestId = UUID()
        currentRequestId = requestId

        // Debounce to avoid hammering the API
        try await Task.sleep(nanoseconds: debounceDelay)

        guard currentRequestId == requestId else {
            throw CancellationError()
        }

        let response: SearchResponse = try await httpClient.request(
            endpoint: .searchUsers(query: trimmedQuery, page: page, limit: limit)
        )

        guard currentRequestId == requestId else {
            throw CancellationError()
        }

        cache.set(response.users, for: cacheKey)

        if currentRequestId == requestId {
            currentRequestId = nil
        }

        return response.users
    }
}
