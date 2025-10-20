import Foundation

/// Represents a social media post
struct Post: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let author: User
    let caption: String
    let imageUrl: String?
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case caption
        case imageUrl = "image_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
    }

    init(
        id: String,
        author: User,
        caption: String,
        imageUrl: String? = nil,
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLiked: Bool = false,
        createdAt: String
    ) {
        self.id = id
        self.author = author
        self.caption = caption
        self.imageUrl = imageUrl
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLiked = isLiked
        self.createdAt = createdAt
    }
}
