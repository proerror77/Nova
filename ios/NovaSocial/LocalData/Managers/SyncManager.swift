import Foundation

// MARK: - SyncManager (同步管理器)

/// 同步管理器 - 处理本地和服务器数据同步
/// Linus 原则：状态机 + Last Write Wins 冲突解决
actor SyncManager {
    static let shared = SyncManager()

    private let storage = LocalStorageManager.shared

    private init() {}

    // MARK: - Sync Operations

    /// 同步 Posts
    func syncPosts(_ remotePosts: [Post]) async throws {
        for remotePost in remotePosts {
            let localPost = try await storage.fetchFirst(
                LocalPost.self,
                predicate: #Predicate { $0.id == remotePost.id.uuidString }
            )

            if let localPost = localPost {
                // 本地存在 - 检查冲突
                try await handleSyncConflict(local: localPost, remote: remotePost)
            } else {
                // 本地不存在 - 直接保存
                let newLocalPost = LocalPost.from(remotePost)
                try await storage.save(newLocalPost)
            }
        }
    }

    /// 同步 Users
    func syncUsers(_ remoteUsers: [User]) async throws {
        for remoteUser in remoteUsers {
            let localUser = try await storage.fetchFirst(
                LocalUser.self,
                predicate: #Predicate { $0.id == remoteUser.id.uuidString }
            )

            if let localUser = localUser {
                try await handleSyncConflict(local: localUser, remote: remoteUser)
            } else {
                let newLocalUser = LocalUser.from(remoteUser)
                try await storage.save(newLocalUser)
            }
        }
    }

    /// 同步 Comments
    func syncComments(_ remoteComments: [Comment]) async throws {
        for remoteComment in remoteComments {
            let localComment = try await storage.fetchFirst(
                LocalComment.self,
                predicate: #Predicate { $0.id == remoteComment.id.uuidString }
            )

            if let localComment = localComment {
                try await handleSyncConflict(local: localComment, remote: remoteComment)
            } else {
                let newLocalComment = LocalComment.from(remoteComment)
                try await storage.save(newLocalComment)
            }
        }
    }

    /// 同步 Notifications
    func syncNotifications(_ remoteNotifications: [Notification]) async throws {
        for remoteNotification in remoteNotifications {
            let localNotification = try await storage.fetchFirst(
                LocalNotification.self,
                predicate: #Predicate { $0.id == remoteNotification.id.uuidString }
            )

            if let localNotification = localNotification {
                try await handleSyncConflict(local: localNotification, remote: remoteNotification)
            } else {
                let newLocalNotification = LocalNotification.from(remoteNotification)
                try await storage.save(newLocalNotification)
            }
        }
    }

    // MARK: - Conflict Resolution (Last Write Wins)

    /// 处理 Post 同步冲突
    private func handleSyncConflict(local: LocalPost, remote: Post) async throws {
        switch local.syncState {
        case .synced:
            // 本地已同步 - 直接更新为远程数据
            updateLocalPost(local, from: remote)
            local.syncState = .synced
            try await storage.update(local)

        case .localOnly, .localModified:
            // 本地有修改 - Last Write Wins
            if let localModifiedAt = local.localModifiedAt {
                if localModifiedAt > remote.createdAt {
                    // 本地更新时间晚于远程 - 保留本地
                    local.syncState = .conflict
                    print("⚠️ Conflict detected for Post \(local.id) - keeping local (newer)")
                } else {
                    // 远程更新时间晚于本地 - 使用远程
                    updateLocalPost(local, from: remote)
                    local.syncState = .synced
                    print("✅ Conflict resolved for Post \(local.id) - using remote (newer)")
                }
            } else {
                // 本地没有修改时间戳 - 使用远程
                updateLocalPost(local, from: remote)
                local.syncState = .synced
            }
            try await storage.update(local)

        case .conflict:
            // 已经是冲突状态 - 保持不变
            print("⚠️ Post \(local.id) already in conflict state")
        }
    }

    /// 处理 User 同步冲突
    private func handleSyncConflict(local: LocalUser, remote: User) async throws {
        switch local.syncState {
        case .synced:
            updateLocalUser(local, from: remote)
            local.syncState = .synced
            try await storage.update(local)

        case .localOnly, .localModified:
            if let localModifiedAt = local.localModifiedAt {
                if localModifiedAt > remote.createdAt {
                    local.syncState = .conflict
                    print("⚠️ Conflict detected for User \(local.id) - keeping local (newer)")
                } else {
                    updateLocalUser(local, from: remote)
                    local.syncState = .synced
                    print("✅ Conflict resolved for User \(local.id) - using remote (newer)")
                }
            } else {
                updateLocalUser(local, from: remote)
                local.syncState = .synced
            }
            try await storage.update(local)

        case .conflict:
            print("⚠️ User \(local.id) already in conflict state")
        }
    }

    /// 处理 Comment 同步冲突
    private func handleSyncConflict(local: LocalComment, remote: Comment) async throws {
        switch local.syncState {
        case .synced:
            updateLocalComment(local, from: remote)
            local.syncState = .synced
            try await storage.update(local)

        case .localOnly, .localModified:
            if let localModifiedAt = local.localModifiedAt {
                if localModifiedAt > remote.createdAt {
                    local.syncState = .conflict
                    print("⚠️ Conflict detected for Comment \(local.id) - keeping local (newer)")
                } else {
                    updateLocalComment(local, from: remote)
                    local.syncState = .synced
                    print("✅ Conflict resolved for Comment \(local.id) - using remote (newer)")
                }
            } else {
                updateLocalComment(local, from: remote)
                local.syncState = .synced
            }
            try await storage.update(local)

        case .conflict:
            print("⚠️ Comment \(local.id) already in conflict state")
        }
    }

    /// 处理 Notification 同步冲突
    private func handleSyncConflict(local: LocalNotification, remote: Notification) async throws {
        switch local.syncState {
        case .synced:
            updateLocalNotification(local, from: remote)
            local.syncState = .synced
            try await storage.update(local)

        case .localOnly, .localModified:
            // Notifications 通常只读，直接使用远程
            updateLocalNotification(local, from: remote)
            local.syncState = .synced
            try await storage.update(local)

        case .conflict:
            print("⚠️ Notification \(local.id) already in conflict state")
        }
    }

    // MARK: - Update Helpers

    private func updateLocalPost(_ local: LocalPost, from remote: Post) {
        local.userId = remote.userId.uuidString
        local.caption = remote.caption
        local.imageUrl = remote.imageUrl
        local.thumbnailUrl = remote.thumbnailUrl
        local.likeCount = remote.likeCount
        local.commentCount = remote.commentCount
        local.isLiked = remote.isLiked
        local.createdAt = remote.createdAt
        local.updatedAt = Date()
        local.userUsername = remote.user?.username
        local.userDisplayName = remote.user?.displayName
        local.userAvatarUrl = remote.user?.avatarUrl
    }

    private func updateLocalUser(_ local: LocalUser, from remote: User) {
        local.username = remote.username
        local.email = remote.email
        local.displayName = remote.displayName
        local.bio = remote.bio
        local.avatarUrl = remote.avatarUrl
        local.isVerified = remote.isVerified
        local.createdAt = remote.createdAt
        local.updatedAt = Date()
    }

    private func updateLocalComment(_ local: LocalComment, from remote: Comment) {
        local.postId = remote.postId.uuidString
        local.userId = remote.userId.uuidString
        local.text = remote.text
        local.createdAt = remote.createdAt
        local.updatedAt = Date()
        local.userUsername = remote.user?.username
        local.userDisplayName = remote.user?.displayName
        local.userAvatarUrl = remote.user?.avatarUrl
    }

    private func updateLocalNotification(_ local: LocalNotification, from remote: Notification) {
        local.type = remote.type.rawValue
        local.actorId = remote.actorId.uuidString
        local.postId = remote.postId?.uuidString
        local.isRead = remote.isRead
        local.createdAt = remote.createdAt
        local.updatedAt = Date()
        local.actorUsername = remote.actor?.username
        local.actorDisplayName = remote.actor?.displayName
        local.actorAvatarUrl = remote.actor?.avatarUrl
        local.postImageUrl = remote.post?.imageUrl
        local.postThumbnailUrl = remote.post?.thumbnailUrl
    }

    // MARK: - State Management

    /// 标记为已同步
    func markSynced<T: Syncable>(_ item: T) async throws {
        var mutableItem = item
        mutableItem.syncState = .synced
        mutableItem.localModifiedAt = nil
    }

    /// 标记为本地修改
    func markLocalModified<T: Syncable>(_ item: T) async throws {
        var mutableItem = item
        mutableItem.syncState = .localModified
        mutableItem.localModifiedAt = Date()
    }

    /// 获取所有待同步项目
    func getPendingSyncItems() async throws -> SyncPendingItems {
        let posts = try await storage.fetch(
            LocalPost.self,
            predicate: #Predicate { $0.syncState == .localModified || $0.syncState == .localOnly }
        )

        let comments = try await storage.fetch(
            LocalComment.self,
            predicate: #Predicate { $0.syncState == .localModified || $0.syncState == .localOnly }
        )

        return SyncPendingItems(
            posts: posts,
            comments: comments
        )
    }
}

// MARK: - Sync Pending Items

struct SyncPendingItems {
    let posts: [LocalPost]
    let comments: [LocalComment]

    var isEmpty: Bool {
        posts.isEmpty && comments.isEmpty
    }

    var totalCount: Int {
        posts.count + comments.count
    }
}
