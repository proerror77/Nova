import Foundation

// MARK: - Search Service
// Handles search operations via SearchService backend (API v2)

class SearchService {
    private let client = APIClient.shared

    // MARK: - Request/Response Models

    struct SearchRequest: Codable {
        let query: String
        let limit: Int?
        let offset: Int?
    }

    struct SearchUsersResponse: Codable {
        let users: [UserSearchResult]
        let totalCount: Int?
        let hasMore: Bool?

        enum CodingKeys: String, CodingKey {
            case users
            case totalCount = "total_count"
            case hasMore = "has_more"
        }
    }

    struct SearchPostsResponse: Codable {
        let posts: [PostSearchResult]
        let totalCount: Int?
        let hasMore: Bool?

        enum CodingKeys: String, CodingKey {
            case posts
            case totalCount = "total_count"
            case hasMore = "has_more"
        }
    }

    struct UserSearchResult: Codable {
        let id: String
        let username: String
        let displayName: String?
        let avatarUrl: String?
        let isVerified: Bool?
        let followerCount: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case username
            case displayName = "display_name"
            case avatarUrl = "avatar_url"
            case isVerified = "is_verified"
            case followerCount = "follower_count"
        }
    }

    struct PostSearchResult: Codable {
        let id: String
        let content: String
        let creatorId: String
        let createdAt: Int64
        let likeCount: Int?
        let commentCount: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case content
            case creatorId = "creator_id"
            case createdAt = "created_at"
            case likeCount = "like_count"
            case commentCount = "comment_count"
        }
    }

    // MARK: - Search Methods

    /// Search across all content types (v2 API)
    /// GET /api/v2/search?q={query}&limit={limit}&offset={offset}
    func searchAll(query: String, filter: SearchFilter = .all, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        guard !query.isEmpty else {
            return []
        }

        // Apply filter
        switch filter {
        case .all:
            // Search users and posts separately and combine
            let users = try await searchUsers(query: query, limit: limit / 2, offset: offset)
            let posts = try await searchPosts(query: query, limit: limit / 2, offset: offset)
            return users + posts

        case .users:
            return try await searchUsers(query: query, limit: limit, offset: offset)

        case .posts:
            return try await searchPosts(query: query, limit: limit, offset: offset)

        case .hashtags:
            return try await searchHashtags(query: query, limit: limit, offset: offset)
        }
    }

    /// Search for users only (v2 API)
    /// GET /api/v2/search/users?q={query}&limit={limit}&offset={offset}
    func searchUsers(query: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        guard !query.isEmpty else {
            return []
        }

        let endpoint = "\(APIConfig.Search.searchUsers)?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&limit=\(limit)&offset=\(offset)"

        let response: SearchUsersResponse = try await client.request(
            endpoint: endpoint,
            method: "GET"
        )

        return response.users.map { user in
            .user(
                id: user.id,
                username: user.username,
                displayName: user.displayName ?? user.username,
                avatarUrl: user.avatarUrl,
                isVerified: user.isVerified ?? false,
                followerCount: user.followerCount ?? 0
            )
        }
    }

    /// Search for posts only (v2 API)
    /// GET /api/v2/search/posts?q={query}&limit={limit}&offset={offset}
    func searchPosts(query: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        guard !query.isEmpty else {
            return []
        }

        let endpoint = "\(APIConfig.Search.searchPosts)?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&limit=\(limit)&offset=\(offset)"

        let response: SearchPostsResponse = try await client.request(
            endpoint: endpoint,
            method: "GET"
        )

        return response.posts.map { post in
            .post(
                id: post.id,
                content: post.content,
                author: post.creatorId,
                createdAt: Date(timeIntervalSince1970: TimeInterval(post.createdAt)),
                likeCount: post.likeCount ?? 0,
                commentCount: post.commentCount ?? 0
            )
        }
    }

    /// Search for hashtags only
    func searchHashtags(query: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        // TODO: Implement when backend supports hashtag search
        // GET /api/v2/search/hashtags?q={query}
        return []
    }

    // MARK: - Suggestions

    /// Get search suggestions for autocomplete
    func getSuggestions(query: String, limit: Int = 10) async throws -> [SearchSuggestion] {
        // TODO: Implement when backend supports search suggestions
        // GET /api/v2/search/suggestions?q={query}&limit={limit}
        return []
    }

    /// Get trending topics/hashtags
    func getTrendingTopics(limit: Int = 10) async throws -> [SearchResult] {
        // TODO: Implement when backend supports trending topics
        // GET /api/v2/search/trending?limit={limit}
        return []
    }

    // MARK: - Recent Searches (Local Storage)

    private let recentSearchesKey = "recentSearches"
    private let maxRecentSearches = 20

    /// Get user's recent search history (from local storage)
    func getRecentSearches(limit: Int = 10) async throws -> [String] {
        let searches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
        return Array(searches.prefix(limit))
    }

    /// Save a search query to history (local storage)
    func saveRecentSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var searches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []

        // Remove duplicate if exists
        searches.removeAll { $0 == query }

        // Insert at beginning
        searches.insert(query, at: 0)

        // Keep only recent searches
        searches = Array(searches.prefix(maxRecentSearches))

        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
    }

    /// Clear recent search history (local storage)
    func clearRecentSearches() {
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }
}
