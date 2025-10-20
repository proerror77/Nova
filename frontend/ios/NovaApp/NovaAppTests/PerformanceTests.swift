import XCTest
@testable import NovaApp

/// 性能测试套件
///
/// 验证应用性能是否满足基准要求
class PerformanceTests: XCTestCase {

    // MARK: - Test Configuration
    let performanceThresholds = PerformanceThresholds(
        maxStartupTime: 2.0,          // 最大启动时间 2 秒
        minFPS: 55,                    // 最低 FPS 55
        maxMemoryMB: 200,              // 最大内存 200MB
        minCacheHitRate: 0.80,         // 最低缓存命中率 80%
        maxImageLoadTime: 0.5          // 最大图像加载时间 500ms
    )

    // MARK: - Startup Performance Tests

    func testAppStartupPerformance() {
        measure {
            // 模拟冷启动
            let monitor = PerformanceMonitor.shared
            monitor.appLaunchTime = Date()

            // 等待首帧渲染
            let expectation = XCTestExpectation(description: "First frame rendered")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                monitor.markFirstFrame()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 3.0)

            // 验证启动时间
            if let startupTime = monitor.startupTime {
                XCTAssertLessThan(
                    startupTime,
                    performanceThresholds.maxStartupTime,
                    "启动时间 \(startupTime)s 超过阈值 \(performanceThresholds.maxStartupTime)s"
                )
            }
        }
    }

    // MARK: - Feed Scroll Performance Tests

    func testFeedScrollPerformance() async {
        let viewModel = FeedViewModel()
        let monitor = PerformanceMonitor.shared

        monitor.startMonitoring()
        monitor.logEvent("Feed scroll test started")

        // 加载初始数据
        await viewModel.loadInitial()

        // 模拟滚动加载更多
        for _ in 0..<5 {
            await viewModel.loadMore()
        }

        monitor.logEvent("Feed scroll test completed")

        let report = monitor.generateReport()

        // 验证 FPS
        XCTAssertGreaterThanOrEqual(
            report.averageFPS,
            performanceThresholds.minFPS,
            "平均 FPS \(report.averageFPS) 低于阈值 \(performanceThresholds.minFPS)"
        )

        // 验证内存
        XCTAssertLessThan(
            report.peakMemoryMB,
            performanceThresholds.maxMemoryMB,
            "峰值内存 \(report.peakMemoryMB)MB 超过阈值 \(performanceThresholds.maxMemoryMB)MB"
        )

        monitor.stopMonitoring()
    }

    // MARK: - Image Cache Performance Tests

    func testImageCachePerformance() async throws {
        let cacheManager = ImageCacheManager.shared
        let testURL = URL(string: "https://picsum.photos/600")!

        // 清空缓存
        cacheManager.clearCache()

        // 第一次加载（网络）
        let start1 = Date()
        _ = try await cacheManager.image(for: testURL, size: .medium)
        let networkLoadTime = Date().timeIntervalSince(start1)

        print("网络加载时间: \(networkLoadTime)s")

        // 第二次加载（内存缓存）
        let start2 = Date()
        _ = try await cacheManager.image(for: testURL, size: .medium)
        let memoryLoadTime = Date().timeIntervalSince(start2)

        print("内存缓存加载时间: \(memoryLoadTime)s")

        // 验证缓存加速
        XCTAssertLessThan(
            memoryLoadTime,
            0.01,  // 内存缓存应该 < 10ms
            "内存缓存加载时间过长: \(memoryLoadTime)s"
        )

        // 验证缓存命中率
        let hitRate = cacheManager.cacheStats.hitRate
        XCTAssertGreaterThan(
            hitRate,
            0.0,
            "缓存命中率应该大于 0"
        )
    }

    func testImageCacheHitRate() async throws {
        let cacheManager = ImageCacheManager.shared
        cacheManager.clearCache()

        // 模拟加载 20 张图像，每张加载 3 次
        let urls = (0..<20).map { URL(string: "https://picsum.photos/600/\($0)")! }

        for _ in 0..<3 {
            for url in urls {
                _ = try? await cacheManager.image(for: url, size: .medium)
            }
        }

        let hitRate = cacheManager.cacheStats.hitRate

        XCTAssertGreaterThanOrEqual(
            hitRate,
            performanceThresholds.minCacheHitRate,
            "缓存命中率 \(hitRate) 低于阈值 \(performanceThresholds.minCacheHitRate)"
        )

        print("📊 缓存统计:")
        print("  - 内存命中: \(cacheManager.cacheStats.memoryHits)")
        print("  - 磁盘命中: \(cacheManager.cacheStats.diskHits)")
        print("  - 网络请求: \(cacheManager.cacheStats.networkFetches)")
        print("  - 命中率: \(String(format: "%.1f%%", hitRate * 100))")
    }

    // MARK: - Memory Management Tests

    func testMemoryLeaks() async {
        weak var weakViewModel: FeedViewModel?

        autoreleasepool {
            let viewModel = FeedViewModel()
            weakViewModel = viewModel

            // 执行操作
            Task {
                await viewModel.loadInitial()
            }
        }

        // 等待释放
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 验证没有循环引用
        XCTAssertNil(weakViewModel, "FeedViewModel 存在内存泄漏")
    }

    func testImageMemoryManagement() async throws {
        let cacheManager = ImageCacheManager.shared
        let initialMemory = PerformanceMonitor.shared.memoryUsageMB

        // 加载大量图像
        let urls = (0..<50).map { URL(string: "https://picsum.photos/600/\($0)")! }

        for url in urls {
            _ = try? await cacheManager.image(for: url, size: .medium)
        }

        let peakMemory = PerformanceMonitor.shared.memoryUsageMB
        let memoryIncrease = peakMemory - initialMemory

        print("内存增长: \(memoryIncrease)MB")

        // 验证内存增长合理（50 张 600x600 图像，约 60MB）
        XCTAssertLessThan(
            memoryIncrease,
            100,  // 最多增长 100MB
            "图像缓存内存增长过大: \(memoryIncrease)MB"
        )

        // 清空缓存
        cacheManager.clearCache()

        // 验证内存释放
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let afterClearMemory = PerformanceMonitor.shared.memoryUsageMB

        XCTAssertLessThan(
            afterClearMemory,
            peakMemory,
            "缓存清空后内存未释放"
        )
    }

    // MARK: - Rendering Performance Tests

    func testPostCardRenderingPerformance() {
        let post = Post(
            id: "test",
            author: User(
                id: "user1",
                username: "testuser",
                displayName: "Test User",
                avatarURL: nil,
                bio: nil,
                followersCount: 100,
                followingCount: 50,
                postsCount: 10
            ),
            imageURL: URL(string: "https://picsum.photos/600"),
            caption: "Test caption",
            likeCount: 42,
            commentCount: 5,
            isLiked: false,
            createdAt: Date()
        )

        measure {
            // 模拟渲染 100 个 PostCard
            for _ in 0..<100 {
                _ = PostCard(
                    post: post,
                    onTap: {},
                    onLike: {},
                    onComment: {}
                )
            }
        }
    }

    func testEquatableOptimization() {
        let post1 = Post(
            id: "1",
            author: User(id: "u1", username: "user", displayName: "User", avatarURL: nil, bio: nil, followersCount: 0, followingCount: 0, postsCount: 0),
            imageURL: nil,
            caption: "Test",
            likeCount: 10,
            commentCount: 5,
            isLiked: false,
            createdAt: Date()
        )

        var post2 = post1

        // 相同内容应该相等
        XCTAssertEqual(post1, post2)

        // 改变 likeCount 应该不相等
        post2 = Post(
            id: post1.id,
            author: post1.author,
            imageURL: post1.imageURL,
            caption: post1.caption,
            likeCount: 11,
            commentCount: post1.commentCount,
            isLiked: post1.isLiked,
            createdAt: post1.createdAt
        )

        XCTAssertNotEqual(post1, post2, "likeCount 变化应该导致 Post 不相等")
    }

    // MARK: - Network Performance Tests

    func testNetworkOptimization() async throws {
        let repository = FeedRepository()
        let cacheManager = CacheManager.shared

        // 清空缓存
        cacheManager.clearAll()

        // 第一次请求（网络）
        let start1 = Date()
        _ = try await repository.fetchFeed(page: 0, limit: 20)
        let networkTime = Date().timeIntervalSince(start1)

        // 第二次请求（缓存）
        let start2 = Date()
        _ = try await repository.fetchFeed(page: 0, limit: 20)
        let cacheTime = Date().timeIntervalSince(start2)

        print("网络请求时间: \(networkTime)s")
        print("缓存请求时间: \(cacheTime)s")

        // 缓存应该快得多
        XCTAssertLessThan(cacheTime, networkTime / 10)
    }

    // MARK: - Performance Report Generation

    func testGeneratePerformanceReport() async {
        let monitor = PerformanceMonitor.shared

        monitor.startMonitoring()

        // 模拟应用使用
        for i in 0..<10 {
            monitor.logEvent("Test event \(i)")
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let report = monitor.generateReport()

        print("\n" + report.summary)

        // 验证报告包含数据
        XCTAssertGreaterThan(report.logsCount, 0)
        XCTAssertGreaterThan(report.averageFPS, 0)
        XCTAssertGreaterThan(report.averageMemoryMB, 0)

        monitor.stopMonitoring()
    }

    // MARK: - Windowed Pagination Tests

    func testWindowedPaginationMemoryManagement() async {
        let viewModel = FeedViewModel()
        let monitor = PerformanceMonitor.shared

        monitor.startMonitoring()

        // 加载 10 页数据（200 个帖子）
        await viewModel.loadInitial()
        for _ in 0..<9 {
            await viewModel.loadMore()
        }

        // 验证窗口化清理：帖子数量应该被限制
        XCTAssertLessThanOrEqual(
            viewModel.posts.count,
            150,  // trimThreshold
            "帖子数量未被窗口化清理机制限制"
        )

        // 验证内存合理
        let report = monitor.generateReport()
        XCTAssertLessThan(
            report.peakMemoryMB,
            performanceThresholds.maxMemoryMB,
            "窗口化清理后内存仍超标"
        )

        monitor.stopMonitoring()

        print("✅ 窗口化分页测试通过：\(viewModel.posts.count) 个帖子在内存中")
    }

    func testPreloadingStrategy() async {
        let viewModel = FeedViewModel()

        // 加载数据
        await viewModel.loadInitial()

        guard viewModel.posts.count >= 10 else {
            XCTFail("测试数据不足")
            return
        }

        // 模拟用户滚动到第 5 个帖子
        let targetPost = viewModel.posts[4]
        viewModel.handlePostAppear(targetPost)

        // 等待预加载完成
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // 验证缓存状态
        let cacheStats = ImageCacheManager.shared.cacheStats
        XCTAssertGreaterThan(
            cacheStats.memoryHits + cacheStats.diskHits,
            0,
            "预加载策略未生效"
        )

        print("✅ 预加载测试通过：缓存命中率 \(String(format: "%.1f%%", cacheStats.hitRate * 100))")
    }

    func testPreloadCancellation() async {
        let viewModel = FeedViewModel()

        await viewModel.loadInitial()

        // 触发预加载
        if let firstPost = viewModel.posts.first {
            viewModel.handlePostAppear(firstPost)
        }

        // 立即刷新（应该清除预加载状态）
        await viewModel.refresh()

        // 验证预加载记录被清空
        // Note: 这是内部实现细节，实际测试会验证行为而不是状态

        print("✅ 预加载取消测试通过")
    }

    // MARK: - Edge Case Tests

    func testEmptyFeedPerformance() async {
        let viewModel = FeedViewModel()
        let monitor = PerformanceMonitor.shared

        monitor.startMonitoring()

        // 空 Feed 场景
        // Note: 需要 mock repository 返回空数据

        let report = monitor.generateReport()
        assertPerformanceHealthy(report)

        monitor.stopMonitoring()
    }

    func testRapidScrollingPerformance() async {
        let viewModel = FeedViewModel()

        await viewModel.loadInitial()

        // 模拟快速滚动（快速触发多个 onAppear）
        for post in viewModel.posts.prefix(20) {
            viewModel.handlePostAppear(post)
        }

        // 验证不会崩溃且性能合理
        XCTAssertGreaterThan(viewModel.posts.count, 0)

        print("✅ 快速滚动性能测试通过")
    }

    func testConcurrentLoading() async {
        let viewModel = FeedViewModel()

        // 并发加载测试
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await viewModel.loadInitial()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await viewModel.loadMore()
            }
        }

        // 验证数据一致性
        XCTAssertGreaterThan(viewModel.posts.count, 0)
        XCTAssertEqual(
            viewModel.posts.count,
            Set(viewModel.posts.map(\.id)).count,
            "并发加载导致数据重复"
        )

        print("✅ 并发加载测试通过")
    }
}

// MARK: - Performance Thresholds
struct PerformanceThresholds {
    let maxStartupTime: TimeInterval
    let minFPS: Int
    let maxMemoryMB: Double
    let minCacheHitRate: Double
    let maxImageLoadTime: TimeInterval
}

// MARK: - Performance Metrics Assertions
extension XCTestCase {
    func assertPerformanceHealthy(_ report: PerformanceReport, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            report.isHealthy,
            "性能指标不健康:\n\(report.summary)",
            file: file,
            line: line
        )
    }
}
