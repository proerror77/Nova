import Foundation
import SwiftData

// MARK: - LocalNotification (本地缓存的通知)

@Model
final class LocalNotification {
    @Attribute(.unique) var id: String
    var type: String // NotificationType.rawValue
    var actorId: String
    var postId: String?
    var isRead: Bool
    var createdAt: Date
    var updatedAt: Date

    // 同步相关字段
    var syncState: SyncState
    var localModifiedAt: Date?

    // Actor 用户信息（嵌入式对象）
    var actorUsername: String?
    var actorDisplayName: String?
    var actorAvatarUrl: String?

    // Post 信息（嵌入式对象）
    var postImageUrl: String?
    var postThumbnailUrl: String?

    init(
        id: String,
        type: String,
        actorId: String,
        postId: String? = nil,
        isRead: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncState: SyncState = .synced,
        localModifiedAt: Date? = nil,
        actorUsername: String? = nil,
        actorDisplayName: String? = nil,
        actorAvatarUrl: String? = nil,
        postImageUrl: String? = nil,
        postThumbnailUrl: String? = nil
    ) {
        self.id = id
        self.type = type
        self.actorId = actorId
        self.postId = postId
        self.isRead = isRead
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
        self.localModifiedAt = localModifiedAt
        self.actorUsername = actorUsername
        self.actorDisplayName = actorDisplayName
        self.actorAvatarUrl = actorAvatarUrl
        self.postImageUrl = postImageUrl
        self.postThumbnailUrl = postThumbnailUrl
    }
}

// MARK: - Syncable Conformance

extension LocalNotification: Syncable {}

// MARK: - Conversion Extensions

extension LocalNotification {
    /// 从 API Notification 转换为 LocalNotification
    static func from(_ notification: Notification) -> LocalNotification {
        LocalNotification(
            id: notification.id.uuidString,
            type: notification.type.rawValue,
            actorId: notification.actorId.uuidString,
            postId: notification.postId?.uuidString,
            isRead: notification.isRead,
            createdAt: notification.createdAt,
            updatedAt: Date(),
            syncState: .synced,
            actorUsername: notification.actor?.username,
            actorDisplayName: notification.actor?.displayName,
            actorAvatarUrl: notification.actor?.avatarUrl,
            postImageUrl: notification.post?.imageUrl,
            postThumbnailUrl: notification.post?.thumbnailUrl
        )
    }

    /// 转换为 API Notification
    func toNotification() -> Notification? {
        guard let notificationId = UUID(uuidString: id),
              let actorId = UUID(uuidString: actorId),
              let notificationType = NotificationType(rawValue: type) else {
            return nil
        }

        let postId = postId.flatMap { UUID(uuidString: $0) }

        var actor: User? = nil
        if let username = actorUsername {
            actor = User(
                id: actorId,
                username: username,
                email: "",
                displayName: actorDisplayName,
                bio: nil,
                avatarUrl: actorAvatarUrl,
                isVerified: false,
                createdAt: createdAt
            )
        }

        var post: Post? = nil
        if let postId = postId, let imageUrl = postImageUrl {
            post = Post(
                id: postId,
                userId: actorId,
                imageUrl: imageUrl,
                thumbnailUrl: postThumbnailUrl,
                caption: nil,
                likeCount: 0,
                commentCount: 0,
                isLiked: false,
                createdAt: createdAt,
                user: nil
            )
        }

        return Notification(
            id: notificationId,
            type: notificationType,
            actorId: actorId,
            postId: postId,
            isRead: isRead,
            createdAt: createdAt,
            actor: actor,
            post: post
        )
    }
}
