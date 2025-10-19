import Foundation

/// Post model (feed item)
struct Post: Identifiable, Codable, Hashable, Equatable {
    let id: String
    let author: User
    let imageURL: URL?
    let caption: String?
    let likeCount: Int
    let commentCount: Int
    var isLiked: Bool
    let createdAt: Date

    // MARK: - Equatable (性能优化：避免不必要的 View 重绘)
    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id &&
        lhs.likeCount == rhs.likeCount &&
        lhs.commentCount == rhs.commentCount &&
        lhs.isLiked == rhs.isLiked
        // 注意：author, imageURL, caption, createdAt 不变，不需要比较
    }

    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case id
        case author
        case imageURL = "image_url"
        case caption
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
    }
}

/// Comment model
struct Comment: Identifiable, Codable {
    let id: String
    let postId: String
    let author: User
    let text: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case author
        case text
        case createdAt = "created_at"
    }
}

/// Like model
struct Like: Codable {
    let userId: String
    let postId: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case postId = "post_id"
        case createdAt = "created_at"
    }
}

// MARK: - User Model
struct User: Identifiable, Codable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: URL?
    let bio: String?
    let followersCount: Int?
    let followingCount: Int?
    let postsCount: Int?

    var initials: String {
        displayName.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case postsCount = "posts_count"
    }
}

// MARK: - Date Extensions
extension Date {
    var timeAgo: String {
        let interval = Date().timeIntervalSince(self)
        let seconds = Int(interval)

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else if seconds < 604800 {
            let days = seconds / 86400
            return "\(days)d ago"
        } else {
            let weeks = seconds / 604800
            return "\(weeks)w ago"
        }
    }
}
