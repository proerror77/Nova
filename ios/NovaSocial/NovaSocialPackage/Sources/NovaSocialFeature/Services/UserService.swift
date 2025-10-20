import Foundation

/// Service for managing user data and profiles
final class UserService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager

    init(httpClient: HTTPClientProtocol = HTTPClient(), cache: CacheManager = CacheManager()) {
        self.httpClient = httpClient
        self.cache = cache
    }

    /// Fetches user profile data
    func getUser(id: String) async throws -> User {
        let cacheKey = "user_\(id)"

        // Check cache first
        if let cached: User = cache.get(for: cacheKey) {
            return cached
        }

        // Fetch from API
        let user: User = try await httpClient.request(endpoint: .users(id: id))

        // Cache the result
        cache.set(user, for: cacheKey)

        return user
    }

    /// Fetches current user profile (for MVP, uses hardcoded ID)
    func getCurrentUser() async throws -> User {
        try await getUser(id: "current_user")
    }
}
