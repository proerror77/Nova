import Foundation
import SwiftData

// MARK: - LocalPost (本地缓存的帖子)

@Model
final class LocalPost {
    @Attribute(.unique) var id: String
    var userId: String
    var caption: String?
    var imageUrl: String
    var thumbnailUrl: String?
    var likeCount: Int
    var commentCount: Int
    var isLiked: Bool
    var createdAt: Date
    var updatedAt: Date

    // 同步相关字段
    var syncState: SyncState
    var localModifiedAt: Date?

    // 用户信息（嵌入式对象）
    var userUsername: String?
    var userDisplayName: String?
    var userAvatarUrl: String?

    init(
        id: String,
        userId: String,
        caption: String? = nil,
        imageUrl: String,
        thumbnailUrl: String? = nil,
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLiked: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncState: SyncState = .synced,
        localModifiedAt: Date? = nil,
        userUsername: String? = nil,
        userDisplayName: String? = nil,
        userAvatarUrl: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.caption = caption
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLiked = isLiked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
        self.localModifiedAt = localModifiedAt
        self.userUsername = userUsername
        self.userDisplayName = userDisplayName
        self.userAvatarUrl = userAvatarUrl
    }
}

// MARK: - Syncable Conformance

extension LocalPost: Syncable {}

// MARK: - Conversion Extensions

extension LocalPost {
    /// 从 API Post 转换为 LocalPost
    static func from(_ post: Post) -> LocalPost {
        LocalPost(
            id: post.id.uuidString,
            userId: post.userId.uuidString,
            caption: post.caption,
            imageUrl: post.imageUrl,
            thumbnailUrl: post.thumbnailUrl,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            isLiked: post.isLiked,
            createdAt: post.createdAt,
            updatedAt: Date(),
            syncState: .synced,
            userUsername: post.user?.username,
            userDisplayName: post.user?.displayName,
            userAvatarUrl: post.user?.avatarUrl
        )
    }

    /// 转换为 API Post
    func toPost() -> Post? {
        guard let postId = UUID(uuidString: id),
              let userId = UUID(uuidString: userId) else {
            return nil
        }

        var user: User? = nil
        if let username = userUsername {
            user = User(
                id: userId,
                username: username,
                email: "", // 缓存中不存储敏感信息
                displayName: userDisplayName,
                bio: nil,
                avatarUrl: userAvatarUrl,
                isVerified: false,
                createdAt: createdAt
            )
        }

        return Post(
            id: postId,
            userId: userId,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            caption: caption,
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
            createdAt: createdAt,
            user: user
        )
    }
}
