import Foundation

/// FeedRepository - Feed 业务逻辑层
/// 职责：处理 Feed 数据加载、缓存管理、离线支持
final class FeedRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let legacyCache: FeedCache // 向后兼容
    private let cacheManager: CacheManager
    private let deduplicator: RequestDeduplicator

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

    // MARK: - Public API

    /// 加载 Feed（支持分页）
    func loadFeed(cursor: String? = nil, limit: Int = 20) async throws -> [Post] {
        let cacheKey = CacheKey.feed(cursor: cursor)

        // 1. 如果是首次加载，先返回缓存数据（如果有）
        if cursor == nil {
            if let cachedPosts: [Post] = await cacheManager.get(forKey: cacheKey), !cachedPosts.isEmpty {
                Logger.log("📦 Returning cached feed (\(cachedPosts.count) posts)", level: .debug)

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
        await cacheManager.remove(forKey: cacheKey)
        legacyCache.clearCache()
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

        // 缓存首页数据
        if cursor == nil {
            let cacheKey = CacheKey.feed(cursor: nil)
            await cacheManager.set(response.posts, forKey: cacheKey, ttl: CacheTTL.feed)
            legacyCache.cacheFeed(response.posts) // 向后兼容
        }

        timer.stop(statusCode: 200)

        return response.posts
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
