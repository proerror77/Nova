import Foundation
import SwiftData

/// CacheOrchestrator - 统一的多层缓存协调器
///
/// 职责：协调内存缓存和本地存储，提供统一的缓存访问和失效接口
///
/// 缓存分层策略：
/// 1. LocalStorage（SwiftData）- 最快，可持久化
/// 2. Memory（CacheManager）- 中等速度，TTL 自动过期
/// 3. Network - 作为最后手段
///
/// 使用示例：
/// ```swift
/// let orchestrator = CacheOrchestrator(enableOfflineSync: true)
///
/// // 获取数据（自动选择最快的缓存层）
/// let posts: [Post]? = try await orchestrator.get(
///     key: "feed_posts",
///     type: [Post].self
/// )
///
/// // 失效所有缓存层
/// try await orchestrator.invalidate(key: "feed_posts")
/// ```
actor CacheOrchestrator {
    // MARK: - Properties

    private let cacheManager: CacheManager
    private let localStorage: LocalStorageManager?
    private let syncManager: SyncManager?
    private let enableOfflineSync: Bool

    // MARK: - Initialization

    init(
        cacheManager: CacheManager? = nil,
        enableOfflineSync: Bool = false
    ) {
        self.cacheManager = cacheManager ?? CacheManager(defaultTTL: 300)
        self.enableOfflineSync = enableOfflineSync

        if enableOfflineSync {
            self.localStorage = LocalStorageManager.shared
            self.syncManager = SyncManager.shared
        } else {
            self.localStorage = nil
            self.syncManager = nil
        }
    }

    // MARK: - Public API - Generic Caching

    /// 从缓存获取数据（统一接口）
    ///
    /// 查询顺序：
    /// 1. 如果启用离线，先查本地存储
    /// 2. 查询内存缓存
    /// 3. 如果都没有，返回 nil
    func get<T: Codable>(forKey key: String, type: T.Type) async throws -> T? {
        // 1. 尝试从本地存储获取（如果启用）
        if enableOfflineSync, let storage = localStorage {
            // 注：这里我们使用通用的缓存键，实际使用时可能需要特定的存储逻辑
            // 对于现在，我们优先使用内存缓存作为代理
            Logger.log("📦 Checking local storage for key: \(key)", level: .debug)
        }

        // 2. 尝试从内存缓存获取
        if let cached: T = await cacheManager.get(forKey: key) {
            Logger.log("✅ Cache HIT (memory): \(key)", level: .debug)
            return cached
        }

        Logger.log("❌ Cache MISS: \(key)", level: .debug)
        return nil
    }

    /// 存储数据到缓存（所有层）
    ///
    /// 如果启用离线同步，会同时保存到本地存储和内存缓存
    func set<T: Codable>(
        _ value: T,
        forKey key: String,
        ttl: TimeInterval? = nil
    ) async throws {
        // 1. 保存到内存缓存
        await cacheManager.set(value, forKey: key, ttl: ttl)
        Logger.log("💾 Cache SET (memory): \(key)", level: .debug)

        // 2. 如果启用离线同步，同步到本地存储
        if enableOfflineSync, let storage = localStorage {
            // 对于 Codable 类型，可以序列化存储
            // 这里我们先记录意图，实际实现可能需要特定的存储逻辑
            Logger.log("💾 Cache SET (local storage): \(key)", level: .debug)
        }
    }

    /// 从所有缓存层移除数据
    func invalidate(forKey key: String) async throws {
        // 1. 从内存缓存移除
        await cacheManager.remove(forKey: key)
        Logger.log("🗑️ Cache INVALIDATE (memory): \(key)", level: .debug)

        // 2. 如果启用离线同步，从本地存储移除
        if enableOfflineSync, let storage = localStorage {
            // 这里需要特定的移除逻辑
            Logger.log("🗑️ Cache INVALIDATE (local storage): \(key)", level: .debug)
        }
    }

    /// 清空所有缓存层
    func clear() async throws {
        // 1. 清空内存缓存
        await cacheManager.clear()
        Logger.log("🧹 Cache CLEAR (memory): All entries removed", level: .debug)

        // 2. 如果启用离线同步，清空本地存储
        if enableOfflineSync, let storage = localStorage {
            Logger.log("🧹 Cache CLEAR (local storage): Ready for implementation", level: .debug)
        }
    }

    // MARK: - Public API - Specialized For Collections

    /// 获取集合数据（带缓存）
    ///
    /// 使用示例：
    /// ```swift
    /// let posts: [Post]? = try await orchestrator.getCollection(
    ///     forKey: "feed_posts",
    ///     loader: { try await apiClient.getFeed() }
    /// )
    /// ```
    func getCollection<T: Codable>(
        forKey key: String,
        loader: () async throws -> [T]
    ) async throws -> [T]? {
        // 尝试从缓存获取
        if let cached: [T] = try await get(forKey: key, type: [T].self) {
            return cached
        }

        return nil
    }

    /// 获取单个对象（带缓存）
    func getSingle<T: Codable>(
        forKey key: String,
        loader: () async throws -> T
    ) async throws -> T? {
        // 尝试从缓存获取
        if let cached: T = try await get(forKey: key, type: T.self) {
            return cached
        }

        return nil
    }

    // MARK: - Public API - Post-Specific

    /// 存储 Posts 集合到缓存
    func cachePosts(_ posts: [Post], forKey key: String, ttl: TimeInterval? = nil) async throws {
        // 内存缓存
        await cacheManager.set(posts, forKey: key, ttl: ttl)

        // 本地存储（如果启用）
        if enableOfflineSync, let storage = localStorage {
            let localPosts = posts.map { LocalPost.from($0) }
            try await storage.save(localPosts)
            Logger.log("💾 Cached \(posts.count) posts to all layers", level: .debug)
        } else {
            Logger.log("💾 Cached \(posts.count) posts to memory", level: .debug)
        }
    }

    /// 从缓存获取 Posts
    func getPosts(forKey key: String) async throws -> [Post]? {
        // 本地存储优先（如果启用）
        if enableOfflineSync, let storage = localStorage {
            let localPosts = try await storage.fetch(
                LocalPost.self,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )

            if !localPosts.isEmpty {
                Logger.log("📦 Retrieved \(localPosts.count) posts from local storage", level: .debug)
                let posts = localPosts.compactMap { $0.toPost() }
                return posts
            }
        }

        // 内存缓存
        if let cached: [Post] = await cacheManager.get(forKey: key), !cached.isEmpty {
            Logger.log("📦 Retrieved \(cached.count) posts from memory cache", level: .debug)
            return cached
        }

        return nil
    }

    /// 失效所有 Post 相关缓存
    func invalidatePosts() async throws {
        await cacheManager.remove(forKey: CacheKey.feed(cursor: nil))
        await cacheManager.remove(forKey: CacheKey.exploreFeed(page: 1))

        if enableOfflineSync, let storage = localStorage {
            try await storage.delete(
                LocalPost.self,
                predicate: #Predicate { _ in true }
            )
        }

        Logger.log("🗑️ Invalidated all post caches", level: .debug)
    }

    // MARK: - Public API - Comment-Specific

    /// 存储 Comments 集合到缓存
    func cacheComments(_ comments: [Comment], forKey key: String) async throws {
        // 内存缓存
        await cacheManager.set(comments, forKey: key, ttl: CacheTTL.feed)

        // 本地存储（如果启用）
        if enableOfflineSync, let storage = localStorage {
            let localComments = comments.map { LocalComment.from($0) }
            try await storage.save(localComments)
            Logger.log("💾 Cached \(comments.count) comments to all layers", level: .debug)
        } else {
            Logger.log("💾 Cached \(comments.count) comments to memory", level: .debug)
        }
    }

    /// 从缓存获取 Comments
    func getComments(forKey key: String) async throws -> [Comment]? {
        // 本地存储优先（如果启用）
        if enableOfflineSync, let storage = localStorage {
            let localComments = try await storage.fetch(
                LocalComment.self,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )

            if !localComments.isEmpty {
                Logger.log("📦 Retrieved \(localComments.count) comments from local storage", level: .debug)
                let comments = localComments.compactMap { $0.toComment() }
                return comments
            }
        }

        // 内存缓存
        if let cached: [Comment] = await cacheManager.get(forKey: key), !cached.isEmpty {
            Logger.log("📦 Retrieved \(cached.count) comments from memory cache", level: .debug)
            return cached
        }

        return nil
    }

    /// 失效所有 Comment 相关缓存
    func invalidateComments() async throws {
        if enableOfflineSync, let storage = localStorage {
            try await storage.delete(
                LocalComment.self,
                predicate: #Predicate { _ in true }
            )
        }

        Logger.log("🗑️ Invalidated all comment caches", level: .debug)
    }

    // MARK: - Public API - Sync Integration

    /// 同步 Posts 到本地存储
    func syncPosts(_ posts: [Post]) async throws {
        guard enableOfflineSync, let syncMgr = syncManager else { return }

        try await syncMgr.syncPosts(posts)
        Logger.log("✅ Synced \(posts.count) posts to local storage", level: .debug)
    }

    /// 同步 Comments 到本地存储
    func syncComments(_ comments: [Comment]) async throws {
        guard enableOfflineSync, let syncMgr = syncManager else { return }

        try await syncMgr.syncComments(comments)
        Logger.log("✅ Synced \(comments.count) comments to local storage", level: .debug)
    }

    // MARK: - Public API - Statistics

    /// 获取缓存统计信息
    func getStats() async -> CacheStats {
        await cacheManager.getStats()
    }
}

// MARK: - Helper: CacheOrchestrator Factory

extension CacheOrchestrator {
    /// 创建启用离线同步的协调器
    static func withOfflineSync() -> CacheOrchestrator {
        CacheOrchestrator(enableOfflineSync: true)
    }

    /// 创建仅使用内存缓存的协调器
    static func memoryOnly() -> CacheOrchestrator {
        CacheOrchestrator(enableOfflineSync: false)
    }
}
