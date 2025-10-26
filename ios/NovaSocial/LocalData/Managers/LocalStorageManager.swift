import Foundation
import SwiftData

// MARK: - LocalStorageManager (泛型本地存储管理器)

/// 泛型本地存储管理器
/// Linus 原则：一次实现，所有实体复用
actor LocalStorageManager {
    static let shared = LocalStorageManager()

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    // MARK: - 配置常量

    private let maxCacheAge: TimeInterval = 30 * 24 * 3600 // 30 天
    private let maxCacheCount: [String: Int] = [
        "LocalPost": 1000,
        "LocalComment": 5000,
        "LocalNotification": 500,
        "LocalUser": 100
    ]

    // MARK: - Initialization

    private init() {
        let schema = Schema([
            LocalPost.self,
            LocalUser.self,
            LocalComment.self,
            LocalNotification.self,
            LocalDraft.self,
            LocalMessage.self
        ])

        let persistentConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        if let container = try? ModelContainer(
            for: schema,
            configurations: [persistentConfig]
        ) {
            self.modelContainer = container
        } else {
            Logger.log(
                "Failed to create persistent SwiftData container. Falling back to in-memory store.",
                level: .warning
            )

            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true
            )

            guard let fallbackContainer = try? ModelContainer(
                for: schema,
                configurations: [fallbackConfig]
            ) else {
                Logger.log(
                    "Unable to create fallback in-memory SwiftData container. Local storage unavailable.",
                    level: .error
                )
                preconditionFailure("LocalStorageManager failed to initialize storage container.")
            }

            self.modelContainer = fallbackContainer
        }

        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = true
    }

    // MARK: - CRUD Operations (泛型实现)

    /// 保存单个项目
    func save<T: PersistentModel>(_ item: T) async throws {
        modelContext.insert(item)
        try modelContext.save()
    }

    /// 批量保存项目
    func save<T: PersistentModel>(_ items: [T]) async throws {
        for item in items {
            modelContext.insert(item)
        }
        try modelContext.save()
    }

    /// 获取所有项目
    func fetchAll<T: PersistentModel>(_ type: T.Type) async throws -> [T] {
        let descriptor = FetchDescriptor<T>()
        return try modelContext.fetch(descriptor)
    }

    /// 根据谓词获取项目
    func fetch<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = []
    ) async throws -> [T] {
        var descriptor = FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        return try modelContext.fetch(descriptor)
    }

    /// 根据谓词获取第一个项目
    func fetchFirst<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>
    ) async throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// 更新项目（自动保存）
    func update<T: PersistentModel>(_ item: T) async throws {
        try modelContext.save()
    }

    /// 删除单个项目
    func delete<T: PersistentModel>(_ item: T) async throws {
        modelContext.delete(item)
        try modelContext.save()
    }

    /// 批量删除项目
    func delete<T: PersistentModel>(_ items: [T]) async throws {
        for item in items {
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    /// 根据谓词删除项目
    func delete<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>
    ) async throws {
        let items = try await fetch(type, predicate: predicate)
        try await delete(items)
    }

    // MARK: - Maintenance Operations (维护操作)

    /// 删除过期数据（30 天前）
    func deleteExpired() async throws {
        let expiryDate = Date().addingTimeInterval(-maxCacheAge)

        // 删除过期的 Posts
        let expiredPosts = try await fetch(
            LocalPost.self,
            predicate: #Predicate { $0.createdAt < expiryDate }
        )
        try await delete(expiredPosts)

        // 删除过期的 Comments
        let expiredComments = try await fetch(
            LocalComment.self,
            predicate: #Predicate { $0.createdAt < expiryDate }
        )
        try await delete(expiredComments)

        // 删除过期的 Notifications
        let expiredNotifications = try await fetch(
            LocalNotification.self,
            predicate: #Predicate { $0.createdAt < expiryDate }
        )
        try await delete(expiredNotifications)

        Logger.log("Deleted expired data (older than 30 days)", level: .info)
    }

    /// 限制缓存大小（保留最新的 N 条）
    func truncate<T: PersistentModel & Syncable>(
        _ type: T.Type,
        maxCount: Int
    ) async throws {
        let sortDescriptor = SortDescriptor<T>(\.localModifiedAt, order: .reverse)
        let allItems = try await fetch(type, sortBy: [sortDescriptor])

        if allItems.count > maxCount {
            let itemsToDelete = Array(allItems.dropFirst(maxCount))
            try await delete(itemsToDelete)
            Logger.log("Truncated \(String(describing: type)) to \(maxCount) items (removed \(itemsToDelete.count))", level: .info)
        }
    }

    /// 清空所有数据
    func clearAll() async throws {
        try await delete(LocalPost.self, predicate: #Predicate { _ in true })
        try await delete(LocalUser.self, predicate: #Predicate { _ in true })
        try await delete(LocalComment.self, predicate: #Predicate { _ in true })
        try await delete(LocalNotification.self, predicate: #Predicate { _ in true })
        try await delete(LocalDraft.self, predicate: #Predicate { _ in true })
        Logger.log("Cleared all local data", level: .info)
    }

    /// 数据库真空（压缩数据库文件）
    func vacuum() async throws {
        // SwiftData 自动管理，无需手动真空
        // 但我们可以强制保存并清理上下文
        try modelContext.save()
        modelContext.reset()
        Logger.log("Database vacuum completed", level: .info)
    }

    // MARK: - Statistics (统计信息)

    /// 获取存储统计信息
    func getStorageStats() async throws -> StorageStats {
        let postCount = try await fetchAll(LocalPost.self).count
        let userCount = try await fetchAll(LocalUser.self).count
        let commentCount = try await fetchAll(LocalComment.self).count
        let notificationCount = try await fetchAll(LocalNotification.self).count
        let draftCount = try await fetchAll(LocalDraft.self).count

        return StorageStats(
            postCount: postCount,
            userCount: userCount,
            commentCount: commentCount,
            notificationCount: notificationCount,
            draftCount: draftCount
        )
    }
}

// MARK: - Storage Stats

struct StorageStats {
    let postCount: Int
    let userCount: Int
    let commentCount: Int
    let notificationCount: Int
    let draftCount: Int

    var totalCount: Int {
        postCount + userCount + commentCount + notificationCount + draftCount
    }
}
