import Foundation

// MARK: - Search Service
// Handles search operations via Search Service backend

class SearchService {
    private let client = APIClient.shared

    // MARK: - Search Methods

    /// Search across all content types (users, posts, hashtags)
    /// - Parameters:
    ///   - query: Search query string
    ///   - filter: Content type filter (all, users, posts, hashtags)
    ///   - limit: Maximum results per type
    ///   - offset: Pagination offset
    /// - Returns: Array of unified SearchResult enum
    func searchAll(query: String, filter: SearchFilter = .all, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        let response: SearchAllResponse = try await client.get(
            endpoint: APIConfig.Search.searchAll,
            queryParams: [
                "q": query,
                "filter": filter.rawValue.lowercased(),
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        // Convert response to unified SearchResult array
        var results: [SearchResult] = []

        // Add user results
        if let users = response.users {
            results += users.map { user in
                .user(
                    id: user.id,
                    username: user.username,
                    displayName: user.displayName,
                    avatarUrl: user.avatarUrl,
                    isVerified: user.isVerified
                )
            }
        }

        // Add post results
        if let posts = response.posts {
            results += posts.map { post in
                .post(
                    id: post.id,
                    content: post.content,
                    author: post.authorId,
                    createdAt: post.createdDate,
                    likeCount: post.likeCount ?? 0
                )
            }
        }

        // Add hashtag results
        if let hashtags = response.hashtags {
            results += hashtags.map { hashtag in
                .hashtag(tag: hashtag.tag, postCount: hashtag.postCount)
            }
        }

        return results
    }

    /// Search for users only
    /// - Parameters:
    ///   - query: Search query string
    ///   - limit: Maximum number of results
    ///   - offset: Pagination offset
    /// - Returns: Array of SearchResult.user cases
    func searchUsers(query: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        let response: SearchUsersResponse = try await client.get(
            endpoint: APIConfig.Search.searchUsers,
            queryParams: [
                "q": query,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return response.users.map { user in
            .user(
                id: user.id,
                username: user.username,
                displayName: user.displayName,
                avatarUrl: user.avatarUrl,
                isVerified: user.isVerified
            )
        }
    }

    /// Search for posts only
    /// - Parameters:
    ///   - query: Search query string
    ///   - limit: Maximum number of results
    ///   - offset: Pagination offset
    /// - Returns: Array of SearchResult.post cases
    func searchPosts(query: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        let response: SearchContentResponse = try await client.get(
            endpoint: APIConfig.Search.searchContent,
            queryParams: [
                "q": query,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return response.posts.map { post in
            .post(
                id: post.id,
                content: post.content,
                author: post.authorId,
                createdAt: post.createdDate,
                likeCount: post.likeCount ?? 0
            )
        }
    }

    /// Search for hashtags only
    /// - Parameters:
    ///   - query: Search query string
    ///   - limit: Maximum number of results
    ///   - offset: Pagination offset
    /// - Returns: Array of SearchResult.hashtag cases
    func searchHashtags(query: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchResult] {
        let response: SearchHashtagsResponse = try await client.get(
            endpoint: APIConfig.Search.searchHashtags,
            queryParams: [
                "q": query,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return response.hashtags.map { hashtag in
            .hashtag(tag: hashtag.tag, postCount: hashtag.postCount)
        }
    }

    // MARK: - Suggestions & Trending

    /// Get search suggestions for autocomplete
    /// - Parameters:
    ///   - query: Partial search query
    ///   - limit: Maximum number of suggestions
    /// - Returns: Array of SearchSuggestion objects
    func getSuggestions(query: String, limit: Int = 10) async throws -> [SearchSuggestion] {
        let response: SearchSuggestionsResponse = try await client.get(
            endpoint: APIConfig.Search.getSuggestions,
            queryParams: [
                "q": query,
                "limit": String(limit)
            ]
        )

        return response.suggestions
    }

    /// Get trending topics/hashtags
    /// - Parameter limit: Maximum number of trending topics
    /// - Returns: Array of SearchResult.hashtag cases
    func getTrendingTopics(limit: Int = 10) async throws -> [SearchResult] {
        let response: TrendingTopicsResponse = try await client.get(
            endpoint: APIConfig.Search.getTrending,
            queryParams: [
                "limit": String(limit)
            ]
        )

        return response.topics.map { hashtag in
            .hashtag(tag: hashtag.tag, postCount: hashtag.postCount)
        }
    }

    // MARK: - Recent Searches (Local Storage)

    private let recentSearchesKey = "recentSearches"
    private let maxRecentSearches = 20

    /// Get user's recent search history from local storage
    /// - Parameter limit: Maximum number of recent searches to return
    /// - Returns: Array of recent search queries
    func getRecentSearches(limit: Int = 10) async throws -> [String] {
        guard let searches = UserDefaults.standard.array(forKey: recentSearchesKey) as? [String] else {
            return []
        }
        return Array(searches.prefix(limit))
    }

    /// Save a search query to local history
    /// - Parameter query: Search query to save
    func saveRecentSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        var searches = (UserDefaults.standard.array(forKey: recentSearchesKey) as? [String]) ?? []

        // Remove if already exists (to move to front)
        searches.removeAll { $0 == query }

        // Add to front
        searches.insert(query, at: 0)

        // Limit to max recent searches
        if searches.count > maxRecentSearches {
            searches = Array(searches.prefix(maxRecentSearches))
        }

        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
    }

    /// Clear recent search history
    func clearRecentSearches() {
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    /// Delete a specific recent search
    /// - Parameter query: Query to remove from history
    func deleteRecentSearch(_ query: String) {
        guard var searches = UserDefaults.standard.array(forKey: recentSearchesKey) as? [String] else {
            return
        }

        searches.removeAll { $0 == query }
        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
    }
}
