import Foundation
import SwiftData

// MARK: - LocalComment (本地缓存的评论)

@Model
final class LocalComment {
    @Attribute(.unique) var id: String
    var postId: String
    var userId: String
    var text: String
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
        postId: String,
        userId: String,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncState: SyncState = .synced,
        localModifiedAt: Date? = nil,
        userUsername: String? = nil,
        userDisplayName: String? = nil,
        userAvatarUrl: String? = nil
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.text = text
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

extension LocalComment: Syncable {}

// MARK: - Conversion Extensions

extension LocalComment {
    /// 从 API Comment 转换为 LocalComment
    static func from(_ comment: Comment) -> LocalComment {
        LocalComment(
            id: comment.id.uuidString,
            postId: comment.postId.uuidString,
            userId: comment.userId.uuidString,
            text: comment.text,
            createdAt: comment.createdAt,
            updatedAt: Date(),
            syncState: .synced,
            userUsername: comment.user?.username,
            userDisplayName: comment.user?.displayName,
            userAvatarUrl: comment.user?.avatarUrl
        )
    }

    /// 转换为 API Comment
    func toComment() -> Comment? {
        guard let commentId = UUID(uuidString: id),
              let postId = UUID(uuidString: postId),
              let userId = UUID(uuidString: userId) else {
            return nil
        }

        var user: User? = nil
        if let username = userUsername {
            user = User(
                id: userId,
                username: username,
                email: "",
                displayName: userDisplayName,
                bio: nil,
                avatarUrl: userAvatarUrl,
                isVerified: false,
                createdAt: createdAt
            )
        }

        return Comment(
            id: commentId,
            postId: postId,
            userId: userId,
            text: text,
            createdAt: createdAt,
            user: user
        )
    }
}
