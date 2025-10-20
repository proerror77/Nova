import Foundation

/// Represents a user in the Nova Social network
struct User: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let bio: String?
    let followersCount: Int
    let followingCount: Int
    let postsCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case bio
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case postsCount = "posts_count"
    }

    init(
        id: String,
        username: String,
        displayName: String,
        avatarUrl: String? = nil,
        bio: String? = nil,
        followersCount: Int = 0,
        followingCount: Int = 0,
        postsCount: Int = 0
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.postsCount = postsCount
    }
}
