import Foundation

// MARK: - Search Models

/// Unified search result that can represent different types
enum SearchResult: Identifiable {
    case user(id: String, username: String, displayName: String, avatarUrl: String?, isVerified: Bool)
    case post(id: String, content: String, author: String, createdAt: Date, likeCount: Int)
    case hashtag(tag: String, postCount: Int)

    var id: String {
        switch self {
        case .user(let id, _, _, _, _):
            return "user_\(id)"
        case .post(let id, _, _, _, _):
            return "post_\(id)"
        case .hashtag(let tag, _):
            return "hashtag_\(tag)"
        }
    }
}

/// Search filter options
enum SearchFilter: String, CaseIterable {
    case all = "All"
    case users = "Users"
    case posts = "Posts"
    case hashtags = "Hashtags"
}

/// Search suggestion for autocomplete
struct SearchSuggestion: Identifiable, Codable {
    let id: String
    let text: String
    let type: SearchSuggestionType
    var count: Int?
}

/// Type of search suggestion
enum SearchSuggestionType: String, Codable {
    case user
    case hashtag
    case recent
}

// MARK: - API Response Models

/// Response from /api/v2/search (global search)
struct SearchAllResponse: Codable {
    let users: [UserSearchResult]?
    let posts: [PostSearchResult]?
    let hashtags: [HashtagSearchResult]?
    let totalResults: Int?

    enum CodingKeys: String, CodingKey {
        case users, posts, hashtags
        case totalResults = "total_results"
    }
}

/// Response from /api/v2/search/users
struct SearchUsersResponse: Codable {
    let users: [UserSearchResult]
    let total: Int?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case users, total
        case hasMore = "has_more"
    }
}

/// Response from /api/v2/search/content
struct SearchContentResponse: Codable {
    let posts: [PostSearchResult]
    let total: Int?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case posts, total
        case hasMore = "has_more"
    }
}

/// Response from /api/v2/search/hashtags
struct SearchHashtagsResponse: Codable {
    let hashtags: [HashtagSearchResult]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case hashtags, total
    }
}

/// Response from /api/v2/search/suggestions
struct SearchSuggestionsResponse: Codable {
    let suggestions: [SearchSuggestion]
}

/// Response from /api/v2/search/trending
struct TrendingTopicsResponse: Codable {
    let topics: [HashtagSearchResult]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case topics, total
    }
}

// MARK: - Search Result Detail Models

/// User search result
struct UserSearchResult: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let bio: String?
    let isVerified: Bool
    let followerCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, bio
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isVerified = "is_verified"
        case followerCount = "follower_count"
    }
}

/// Post/Content search result
struct PostSearchResult: Codable, Identifiable {
    let id: String
    let content: String
    let authorId: String
    let authorName: String?
    let createdAt: String
    let likeCount: Int?
    let commentCount: Int?
    let mediaUrls: [String]?

    enum CodingKeys: String, CodingKey {
        case id, content
        case authorId = "author_id"
        case authorName = "author_name"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case mediaUrls = "media_urls"
    }

    /// Convert createdAt string to Date
    var createdDate: Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: createdAt) ?? Date()
    }
}

/// Hashtag search result
struct HashtagSearchResult: Codable, Identifiable {
    let tag: String
    let postCount: Int
    let trendingScore: Double?

    enum CodingKeys: String, CodingKey {
        case tag
        case postCount = "post_count"
        case trendingScore = "trending_score"
    }

    var id: String { tag }
}
