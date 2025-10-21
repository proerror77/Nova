import Foundation

/// FeedRepository - Feed 业务逻辑层（统一版本）
/// 职责：处理 Feed 数据加载、缓存管理、离线支持、数据同步
///
/// 改进点：
/// 1. 合并了 FeedRepository 和 FeedRepositoryEnhanced 的功能
/// 2. 支持可选的本地存储缓存和后台同步
/// 3. 三层缓存架构：内存缓存 → 本地存储 → 网络
/// 4. Linus 原则：消除了 *Enhanced 特殊情况后缀
///
/// 使用示例：
/// ```
/// // 基础用法（无离线支持）
/// let repo = FeedRepository()
///
/// // 启用离线同步
/// let repoWithOffline = FeedRepository(enableOfflineSync: true)
/// ```
final class FeedRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let legacyCache: FeedCache // 向后兼容
    private let cacheManager: CacheManager
    private let deduplicator: RequestDeduplicator

    // 可选的本地存储和同步管理
    private let localStorage: LocalStorageManager?
    private let syncManager: SyncManager?
    private let enableOfflineSync: Bool

    init(
        apiClient: APIClient? = nil,
        cache: FeedCache? = nil,
        cacheManager: CacheManager? = nil,
        deduplicator: RequestDeduplicator? = nil,
        enableOfflineSync: Bool = false
    ) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
        self.legacyCache = cache ?? FeedCache()
        self.cacheManager = cacheManager ?? CacheManager(defaultTTL: CacheTTL.feed)
        self.deduplicator = deduplicator ?? RequestDeduplicator()
        self.enableOfflineSync = enableOfflineSync

        // 仅在启用离线同步时初始化存储管理器
        if enableOfflineSync {
            self.localStorage = LocalStorageManager.shared
            self.syncManager = SyncManager.shared
        } else {
            self.localStorage = nil
            self.syncManager = nil
        }
    }

    // MARK: - Public API

    /// 加载 Feed（支持分页和离线同步）
    ///
    /// 缓存策略（启用离线同步时）：
    /// 1. 本地存储缓存（SwiftData）- 最快
    /// 2. 内存缓存（CacheManager）- 中等速度
    /// 3. 网络请求 - 作为最后手段
    func loadFeed(cursor: String? = nil, limit: Int = 20) async throws -> [Post] {
        let cacheKey = CacheKey.feed(cursor: cursor)

        // 1. 首次加载时，优先检查缓存
        if cursor == nil {
            // 1a. 如果启用离线同步，先检查本地存储缓存
            if enableOfflineSync, let storage = localStorage {
                let localPosts = try await storage.fetch(
                    LocalPost.self,
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )

                if !localPosts.isEmpty {
                    Logger.log("📦 Returning local cached feed (\(localPosts.count) posts)", level: .debug)

                    let cachedPosts = localPosts.compactMap { $0.toPost() }

                    // 后台同步最新数据（不阻塞 UI）
                    Task {
                        try? await syncFeedInBackground(limit: limit)
                    }

                    return cachedPosts
                }
            }

            // 1b. 检查内存缓存
            if let cachedPosts: [Post] = await cacheManager.get(forKey: cacheKey), !cachedPosts.isEmpty {
                Logger.log("📦 Returning cached feed from memory (\(cachedPosts.count) posts)", level: .debug)

                // 后台刷新最新数据
                Task {
                    try? await fetchAndCacheFeed(cursor: nil, limit: limit)
                }

                return cachedPosts
            }
        }

        // 2. 从网络加载数据（带去重）
        return try await deduplicator.deduplicate(key: cacheKey) {
            try await self.fetchAndCacheFeed(cursor: cursor, limit: limit)
        }
    }

    /// 刷新 Feed（下拉刷新）
    func refreshFeed(limit: Int = 20) async throws -> [Post] {
        let cacheKey = CacheKey.feed(cursor: nil)

        // 清空所有缓存层
        await cacheManager.remove(forKey: cacheKey)
        legacyCache.clearCache()

        // 如果启用离线同步，清空本地缓存
        if enableOfflineSync, let storage = localStorage {
            try await storage.delete(
                LocalPost.self,
                predicate: #Predicate { _ in true }
            )
        }

        // 从服务器获取最新数据
        return try await fetchAndCacheFeed(cursor: nil, limit: limit)
    }

    /// 加载 Explore Feed
    func loadExploreFeed(page: Int = 1, limit: Int = 30) async throws -> [Post] {
        let cacheKey = CacheKey.exploreFeed(page: page)

        // 检查缓存
        if let cachedPosts: [Post] = await cacheManager.get(forKey: cacheKey) {
            Logger.log("📦 Returning cached explore feed (page \(page))", level: .debug)
            return cachedPosts
        }

        // 从网络加载（带去重）
        return try await deduplicator.deduplicate(key: cacheKey) {
            let timer = PerformanceTimer(path: "/api/v1/feed/explore", method: .get)

            let queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]

            let endpoint = APIEndpoint(
                path: "/api/v1/feed/explore",
                method: .get,
                queryItems: queryItems
            )

            struct ExploreResponse: Codable {
                let posts: [Post]
                let hasMore: Bool

                enum CodingKeys: String, CodingKey {
                    case posts
                    case hasMore = "has_more"
                }
            }

            let response: ExploreResponse = try await self.interceptor.executeWithRetry(endpoint)

            // 缓存数据
            await self.cacheManager.set(response.posts, forKey: cacheKey, ttl: CacheTTL.exploreFeed)

            timer.stop(statusCode: 200)

            return response.posts
        }
    }

    // MARK: - Private Helpers

    private func fetchAndCacheFeed(cursor: String?, limit: Int) async throws -> [Post] {
        let timer = PerformanceTimer(path: "/api/v1/feed", method: .get)

        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let endpoint = APIEndpoint(
            path: "/api/v1/feed",
            method: .get,
            queryItems: queryItems
        )

        let response: FeedResponse = try await interceptor.executeWithRetry(endpoint)

        // 缓存首页数据到所有层
        if cursor == nil {
            let cacheKey = CacheKey.feed(cursor: nil)

            // 1. 内存缓存（向后兼容）
            await cacheManager.set(response.posts, forKey: cacheKey, ttl: CacheTTL.feed)
            legacyCache.cacheFeed(response.posts)

            // 2. 本地存储缓存（如果启用离线同步）
            if enableOfflineSync, let storage = localStorage {
                let localPosts = response.posts.map { LocalPost.from($0) }
                try await storage.save(localPosts)

                // 3. 标记为已同步
                if let syncMgr = syncManager {
                    try await syncMgr.syncPosts(response.posts)
                }

                Logger.log("💾 Cached \(response.posts.count) posts to local storage", level: .debug)
            }
        }

        timer.stop(statusCode: 200)

        return response.posts
    }

    /// 后台同步 Feed（不阻塞 UI）
    private func syncFeedInBackground(limit: Int) async throws {
        guard enableOfflineSync, let syncMgr = syncManager else { return }

        let timer = PerformanceTimer(path: "/api/v1/feed", method: .get)

        let queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let endpoint = APIEndpoint(
            path: "/api/v1/feed",
            method: .get,
            queryItems: queryItems
        )

        do {
            let response: FeedResponse = try await interceptor.executeWithRetry(endpoint)

            // 同步到本地存储
            try await syncMgr.syncPosts(response.posts)

            timer.stop(statusCode: 200)

            Logger.log("✅ Background sync completed (\(response.posts.count) posts)", level: .debug)
        } catch {
            Logger.log("⚠️ Background sync failed: \(error.localizedDescription)", level: .warning)
            // 后台同步失败不影响主流程
        }
    }
}

// MARK: - Feed Cache

/// Feed 缓存管理
final class FeedCache {
    private let cacheKey = "feed_cache"
    private let maxCacheSize = 50 // 最多缓存 50 条 Feed

    func getCachedFeed() -> [Post]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let posts = try? JSONDecoder().decode([Post].self, from: data) else {
            return nil
        }
        return posts
    }

    func cacheFeed(_ posts: [Post]) {
        // 只缓存最新的 N 条
        let postsToCache = Array(posts.prefix(maxCacheSize))

        if let data = try? JSONEncoder().encode(postsToCache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
