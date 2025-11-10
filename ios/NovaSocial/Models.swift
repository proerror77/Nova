import Foundation

// MARK: - User Model
struct User: Codable, Identifiable {
    let id: String
    let username: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let isVerified: Bool
    let followerCount: Int
    let followingCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, bio, isVerified, createdAt
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case followerCount = "follower_count"
        case followingCount = "following_count"
    }
}

// MARK: - Post Model
struct Post: Codable, Identifiable {
    let id: String
    let userId: String
    let caption: String?
    let imageUrl: String?
    let thumbnailUrl: String?
    let likeCount: Int
    let commentCount: Int
    let viewCount: Int
    let createdAt: Date

    // Relationship data (optional, fetched separately)
    var author: User?
    var isLiked: Bool?

    enum CodingKeys: String, CodingKey {
        case id, caption, createdAt
        case userId = "user_id"
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case viewCount = "view_count"
    }
}

// MARK: - Comment Model
struct Comment: Codable, Identifiable {
    let id: String
    let postId: String
    let userId: String
    let content: String
    let createdAt: Date

    // Relationship data
    var author: User?

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt
        case postId = "post_id"
        case userId = "user_id"
    }
}

// MARK: - Feed Response
struct FeedResponse: Codable {
    let posts: [Post]
    let cursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case posts, cursor
        case hasMore = "has_more"
    }
}

// MARK: - Auth Response
struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - API Error
struct APIError: Codable, Error {
    let code: String
    let message: String
    let metadata: [String: String]?
}

// MARK: - GraphQL Request/Response
struct GraphQLRequest: Codable {
    let query: String
    let variables: [String: AnyCodable]?
    let operationName: String?
}

struct GraphQLResponse<T: Codable>: Codable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Codable {
    let message: String
    let locations: [ErrorLocation]?
    let path: [String]?

    struct ErrorLocation: Codable {
        let line: Int
        let column: Int
    }
}

// MARK: - AnyCodable Helper (for dynamic JSON)
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
