import Foundation

/// Response structure for feed API
private struct FeedResponse: Decodable {
    let posts: [Post]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case posts
        case hasMore = "has_more"
    }
}

/// Service for managing feed data
final class FeedService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager

    init(httpClient: HTTPClientProtocol = HTTPClient(), cache: CacheManager = CacheManager()) {
        self.httpClient = httpClient
        self.cache = cache
    }

    /// Fetches the feed for a given page
    func getFeed(page: Int = 0, limit: Int = 20) async throws -> [Post] {
        let cacheKey = "feed_page_\(page)"

        // Check cache first
        if let cached: [Post] = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let response: FeedResponse = try await httpClient.request(endpoint: .feed(page: page, limit: limit))

        // Cache the results
        cache.set(response.posts, for: cacheKey)

        return response.posts
    }
}
