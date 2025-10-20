import Foundation

/// FeedRepositoryEnhanced - Feed 业务逻辑层（增强版）
/// 职责：处理 Feed 数据加载、缓存管理、离线支持、数据同步
///
/// Linus 原则：零破坏性集成，向后兼容现有 FeedRepository
/// - 先读本地缓存（快速）
/// - 后台同步（异步，不阻塞）
/// - 离线优先策略
final class FeedRepositoryEnhanced {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let legacyCache: FeedCache
    private let cacheManager: CacheManager
    private let deduplicator: RequestDeduplicator

    // 新增：本地存储和同步管理器
    private let localStorage = LocalStorageManager.shared
    private let syncManager = SyncManager.shared

    init(
        apiClient: APIClient? = nil,
        cache: FeedCache? = nil,
        cacheManager: CacheManager? = nil,
        deduplicator: RequestDeduplicator? = nil
    ) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
        self.legacyCache = cache ?? FeedCache()
        self.cacheManager = cacheManager ?? CacheManager(defaultTTL: CacheTTL.feed)
        self.deduplicator = deduplicator ?? RequestDeduplicator()
    }

    // MARK: - Public API (Enhanced)

    /// 加载 Feed（离线优先策略）
    func loadFeed(cursor: String? = nil, limit: Int = 20) async throws -> [Post] {
        let cacheKey = CacheKey.feed(cursor: cursor)

        // 1. 首次加载：优先返回本地缓存
        if cursor == nil {
            // 从 SwiftData 读取缓存
            let localPosts = try await localStorage.fetch(
                LocalPost.self,
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )

            if !localPosts.isEmpty {
                Logger.log("📦 Returning local cached feed (\(localPosts.count) posts)", level: .debug)

                // 转换为 Post 对象
                let cachedPosts = localPosts.compactMap { $0.toPost() }

                // 后台同步最新数据（不阻塞 UI）
                Task {
                    try? await syncFeedInBackground(limit: limit)
                }

                return cachedPosts
            }
        }

        // 2. 缓存未命中或分页加载：从网络加载
        return try await fetchAndCacheFeed(cursor: cursor, limit: limit)
    }

    /// 刷新 Feed（下拉刷新）
    func refreshFeed(limit: Int = 20) async throws -> [Post] {
        // 清空旧缓存
        let cacheKey = CacheKey.feed(cursor: nil)
        await cacheManager.remove(forKey: cacheKey)
        legacyCache.clearCache()

        // 清空本地缓存
        try await localStorage.delete(
            LocalPost.self,
            predicate: #Predicate { _ in true }
        )

        // 从服务器获取最新数据
        return try await fetchAndCacheFeed(cursor: nil, limit: limit)
    }

    /// 加载 Explore Feed（同样支持离线缓存）
    func loadExploreFeed(page: Int = 1, limit: Int = 30) async throws -> [Post] {
        let cacheKey = CacheKey.exploreFeed(page: page)

        // 检查内存缓存
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

            // 缓存数据（内存）
            await self.cacheManager.set(response.posts, forKey: cacheKey, ttl: CacheTTL.exploreFeed)

            timer.stop(statusCode: 200)

            return response.posts
        }
    }

    // MARK: - Private Helpers

    /// 从服务器获取 Feed 并缓存
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

        // 缓存首页数据
        if cursor == nil {
            // 1. 内存缓存（向后兼容）
            let cacheKey = CacheKey.feed(cursor: nil)
            await cacheManager.set(response.posts, forKey: cacheKey, ttl: CacheTTL.feed)
            legacyCache.cacheFeed(response.posts)

            // 2. 本地持久化缓存（新增）
            let localPosts = response.posts.map { LocalPost.from($0) }
            try await localStorage.save(localPosts)

            // 3. 同步数据（标记为已同步）
            try await syncManager.syncPosts(response.posts)

            Logger.log("💾 Cached \(response.posts.count) posts to local storage", level: .debug)
        }

        timer.stop(statusCode: 200)

        return response.posts
    }

    /// 后台同步 Feed（不阻塞 UI）
    private func syncFeedInBackground(limit: Int) async throws {
        let timer = PerformanceTimer(path: "/api/v1/feed", method: .get)

        let queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let endpoint = APIEndpoint(
            path: "/feed",
            method: .get,
            queryItems: queryItems
        )

        do {
            let response: FeedResponse = try await interceptor.executeWithRetry(endpoint)

            // 同步到本地存储
            try await syncManager.syncPosts(response.posts)

            timer.stop(statusCode: 200)

            Logger.log("✅ Background sync completed (\(response.posts.count) posts)", level: .debug)
        } catch {
            Logger.log("⚠️ Background sync failed: \(error.localizedDescription)", level: .warning)
            // 后台同步失败不影响主流程
        }
    }
}

// MARK: - Migration Helper (向后兼容)

extension FeedRepositoryEnhanced {
    /// 从旧版 FeedRepository 迁移（可选）
    static func migrate(from oldRepository: FeedRepository) -> FeedRepositoryEnhanced {
        // 创建新的增强版 Repository
        let enhanced = FeedRepositoryEnhanced()

        // TODO: 迁移旧缓存到新存储（如果需要）

        return enhanced
    }
}
