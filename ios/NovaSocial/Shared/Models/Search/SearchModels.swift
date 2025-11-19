import Foundation

// MARK: - Search Models

/// Unified search result that can represent different types
enum SearchResult: Identifiable {
    case user(id: String, username: String, displayName: String, avatarUrl: String?, isVerified: Bool, followerCount: Int)
    case post(id: String, content: String, author: String, createdAt: Date, likeCount: Int, commentCount: Int)
    case hashtag(tag: String, postCount: Int)

    var id: String {
        switch self {
        case .user(let id, _, _, _, _, _):
            return "user_\(id)"
        case .post(let id, _, _, _, _, _):
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
struct SearchSuggestion: Identifiable {
    let id: String
    let text: String
    let type: SearchSuggestionType
    var count: Int?
}

/// Type of search suggestion
enum SearchSuggestionType: String {
    case user
    case hashtag
    case recent
}
