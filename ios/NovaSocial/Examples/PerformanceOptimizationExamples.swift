import Foundation

/// 性能优化系统使用示例
/// 展示如何使用 CacheManager, RequestDeduplicator, NetworkMonitor 等组件
final class PerformanceOptimizationExamples {

    // MARK: - Example 1: 基础缓存使用

    func example1_BasicCacheUsage() async {
        let cache = CacheManager(defaultTTL: 300)

        // 存储数据
        await cache.set("Hello, World!", forKey: "greeting", ttl: 60)

        // 读取数据
        if let greeting: String = await cache.get(forKey: "greeting") {
            print("✅ Cache hit: \(greeting)")
        } else {
            print("❌ Cache miss")
        }

        // 移除数据
        await cache.remove(forKey: "greeting")

        // 清空所有缓存
        await cache.clear()
    }

    // MARK: - Example 2: 请求去重

    func example2_RequestDeduplication() async throws {
        let deduplicator = RequestDeduplicator()

        // 模拟慢速 API 请求
        func slowAPICall() async throws -> String {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 秒
            return "API Result"
        }

        // 并发发起 5 个相同请求，但只会执行 1 次实际请求
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await deduplicator.deduplicate(key: "slow_api") {
                        try await slowAPICall()
                    }
                }
            }

            var results: [String] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        print("✅ All 5 requests completed with single API call")
        print("Results: \(results)")
    }

    // MARK: - Example 3: 性能监控

    func example3_PerformanceMonitoring() async {
        let timer = PerformanceTimer(path: "/api/posts", method: .get)

        // 模拟 API 请求
        do {
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            timer.stop(statusCode: 200, bytesTransferred: 1024)
        } catch {
            timer.stop(statusCode: 500)
        }

        // 查看统计
        let stats = await PerformanceMetrics.shared.getStats()
        print(stats.description)

        // 查看慢请求
        let slowRequests = await PerformanceMetrics.shared.getSlowRequests(threshold: 1.0)
        slowRequests.forEach { print($0.description) }
    }

    // MARK: - Example 4: 网络监听

    func example4_NetworkMonitoring() {
        let monitor = NetworkMonitor.shared

        // 监听网络状态变化
        monitor.onConnectionChanged = { isConnected, connectionType in
            if isConnected {
                print("✅ Network connected via \(connectionType)")
                // 可以在这里触发待处理的请求
            } else {
                print("❌ Network disconnected")
                // 可以在这里显示离线提示
            }
        }

        // 检查当前状态
        if monitor.isConnected {
            print("Currently connected via \(monitor.connectionType)")
        }
    }

    // MARK: - Example 5: 带缓存的 Repository 模式

    final class UserRepository {
        private let cache = CacheManager(defaultTTL: CacheTTL.userProfile)
        private let deduplicator = RequestDeduplicator()

        func getUserProfile(userId: String) async throws -> UserProfile {
            let cacheKey = CacheKey.userProfile(userId: userId)

            // 先查缓存
            if let cachedProfile: UserProfile = await cache.get(forKey: cacheKey) {
                await PerformanceMetrics.shared.recordCacheHit()
                return cachedProfile
            }

            // 缓存未命中，发起网络请求（带去重）
            return try await deduplicator.deduplicate(key: cacheKey) {
                let timer = PerformanceTimer(path: "/users/\(userId)", method: .get)

                // 实际 API 请求
                let profile = try await self.fetchUserProfile(userId: userId)

                // 缓存结果
                await self.cache.set(profile, forKey: cacheKey, ttl: CacheTTL.userProfile)

                await PerformanceMetrics.shared.recordCacheMiss()
                timer.stop(statusCode: 200)

                return profile
            }
        }

        private func fetchUserProfile(userId: String) async throws -> UserProfile {
            // 实际 API 调用实现
            fatalError("Implement actual API call")
        }
    }

    // MARK: - Example 6: 智能预加载

    final class SmartPreloadingFeed {
        private let cache = CacheManager(defaultTTL: CacheTTL.feed)
        private let deduplicator = RequestDeduplicator()

        func loadFeedWithPreloading(page: Int) async throws -> [Post] {
            // 加载当前页
            let currentPage = try await loadPage(page)

            // 后台预加载下一页（不阻塞）
            Task {
                try? await self.preloadPage(page + 1)
            }

            return currentPage
        }

        private func loadPage(_ page: Int) async throws -> [Post] {
            let cacheKey = "feed_page_\(page)"

            if let cached: [Post] = await cache.get(forKey: cacheKey) {
                return cached
            }

            return try await deduplicator.deduplicate(key: cacheKey) {
                let posts = try await self.fetchPage(page)
                await self.cache.set(posts, forKey: cacheKey)
                return posts
            }
        }

        private func preloadPage(_ page: Int) async throws {
            let cacheKey = "feed_page_\(page)"

            // 只在缓存未命中时预加载
            if await cache.get(forKey: cacheKey) == nil {
                let posts = try await fetchPage(page)
                await cache.set(posts, forKey: cacheKey)
                print("📥 Preloaded page \(page)")
            }
        }

        private func fetchPage(_ page: Int) async throws -> [Post] {
            // 实际 API 调用
            fatalError("Implement actual API call")
        }
    }

    // MARK: - Example 7: 网络恢复自动重试

    func example7_AutoRetryOnNetworkRecovery() async throws {
        let retryManager = RetryManager()

        func importantAPICall() async throws {
            // 检查网络状态
            guard NetworkMonitor.shared.isConnected else {
                // 网络断开，添加到待重试队列
                await retryManager.addPendingRetry(key: "important_call") {
                    try await importantAPICall()
                }
                throw APIError.networkError(URLError(.notConnectedToInternet))
            }

            // 执行实际请求
            print("Executing important API call...")
        }

        do {
            try await importantAPICall()
        } catch {
            print("❌ Request failed, will retry when network recovers")
        }
    }

    // MARK: - Example 8: URLCache 图片缓存

    func example8_ImageCaching() async throws {
        // 配置 URLCache
        URLCacheConfig.configure()

        // 创建带缓存策略的请求
        let imageURL = URL(string: "https://example.com/image.jpg")!
        let request = URLRequest.cachedRequest(url: imageURL, cachePolicy: .returnCacheElseLoad)

        // 发起请求
        let (data, response) = try await URLSession.shared.data(for: request)

        // URLCache 会自动缓存响应
        print("✅ Image loaded, URLCache will cache automatically")

        // 查看缓存统计
        let stats = URLCacheConfig.shared.getCacheStats()
        print(stats.description)
    }

    // MARK: - Example 9: 性能调试

    func example9_PerformanceDebugging() async {
        #if DEBUG
        // 打印当前统计
        PerformanceDebugView.printStats()

        // 打印慢请求
        PerformanceDebugView.printSlowRequests(threshold: 1.0)

        // 获取优化建议
        PerformanceRecommendations.printRecommendations()

        // 启用自动日志（每 30 秒）
        PerformanceDebugView.startAutoLogging(interval: 30)

        // 清除所有缓存
        PerformanceDebugView.clearAllCaches()

        // 重置统计
        PerformanceDebugView.resetStats()
        #endif
    }

    // MARK: - Example 10: 完整集成示例

    final class OptimizedFeedViewModel {
        private let repository: FeedRepository
        private let networkMonitor: NetworkMonitor

        init() {
            // 初始化 Repository（自动包含缓存和去重）
            self.repository = FeedRepository()
            self.networkMonitor = NetworkMonitor.shared

            // 监听网络状态
            setupNetworkMonitoring()
        }

        func loadFeed() async throws -> [Post] {
            // Repository 内部已经处理：
            // 1. 缓存检查（带 TTL）
            // 2. 请求去重
            // 3. 性能监控
            return try await repository.loadFeed()
        }

        func refreshFeed() async throws -> [Post] {
            try await repository.refreshFeed()
        }

        private func setupNetworkMonitoring() {
            networkMonitor.onConnectionChanged = { [weak self] isConnected, _ in
                if isConnected {
                    // 网络恢复，可以重试失败的请求
                    Task {
                        try? await self?.loadFeed()
                    }
                }
            }
        }

        deinit {
            // NetworkMonitor 是单例，不需要手动清理
        }
    }
}

// MARK: - Mock Types (for examples)

struct UserProfile: Codable {
    let id: String
    let name: String
}

struct Post: Codable {
    let id: String
    let userId: String
    let content: String
    let imageUrl: String?
    let createdAt: Date
    let likesCount: Int
    let commentsCount: Int
    let isLiked: Bool
}

struct FeedResponse: Codable {
    let posts: [Post]
    let nextCursor: String?
    let hasMore: Bool
}
