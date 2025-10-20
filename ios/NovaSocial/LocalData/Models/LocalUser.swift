import Foundation
import SwiftData

// MARK: - LocalUser (本地缓存的用户)

@Model
final class LocalUser {
    @Attribute(.unique) var id: String
    var username: String
    var email: String
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var isVerified: Bool
    var createdAt: Date
    var updatedAt: Date

    // 同步相关字段
    var syncState: SyncState
    var localModifiedAt: Date?

    // 统计信息（可选，快照缓存）
    var postCount: Int?
    var followerCount: Int?
    var followingCount: Int?
    var isFollowing: Bool?

    init(
        id: String,
        username: String,
        email: String,
        displayName: String? = nil,
        bio: String? = nil,
        avatarUrl: String? = nil,
        isVerified: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncState: SyncState = .synced,
        localModifiedAt: Date? = nil,
        postCount: Int? = nil,
        followerCount: Int? = nil,
        followingCount: Int? = nil,
        isFollowing: Bool? = nil
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
        self.localModifiedAt = localModifiedAt
        self.postCount = postCount
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
    }
}

// MARK: - Syncable Conformance

extension LocalUser: Syncable {}

// MARK: - Conversion Extensions

extension LocalUser {
    /// 从 API User 转换为 LocalUser
    static func from(_ user: User) -> LocalUser {
        LocalUser(
            id: user.id.uuidString,
            username: user.username,
            email: user.email,
            displayName: user.displayName,
            bio: user.bio,
            avatarUrl: user.avatarUrl,
            isVerified: user.isVerified,
            createdAt: user.createdAt,
            updatedAt: Date(),
            syncState: .synced
        )
    }

    /// 转换为 API User
    func toUser() -> User? {
        guard let userId = UUID(uuidString: id) else {
            return nil
        }

        return User(
            id: userId,
            username: username,
            email: email,
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            isVerified: isVerified,
            createdAt: createdAt
        )
    }
}
