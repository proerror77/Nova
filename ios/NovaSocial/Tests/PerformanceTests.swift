import XCTest
@testable import NovaSocial

/// 性能测试套件 - 验证缓存和优化效果
final class PerformanceTests: XCTestCase {
    var cacheManager: CacheManager!
    var deduplicator: RequestDeduplicator!
    var performanceMetrics: PerformanceMetrics!

    override func setUp() async throws {
        try await super.setUp()
        cacheManager = CacheManager(defaultTTL: 300)
        deduplicator = RequestDeduplicator()
        performanceMetrics = PerformanceMetrics.shared
        await performanceMetrics.reset()
    }

    override func tearDown() async throws {
        await cacheManager.clear()
        await deduplicator.cancelAll()
        try await super.tearDown()
    }

    // MARK: - Cache Performance Tests

    func testCacheManager_SetAndGet_Performance() async throws {
        let testData = (1...1000).map { "test_value_\($0)" }

        // 测试写入性能
        let writeStart = Date()
        for (index, value) in testData.enumerated() {
            await cacheManager.set(value, forKey: "key_\(index)", ttl: 300)
        }
        let writeDuration = Date().timeIntervalSince(writeStart)

        print("✅ Cache write: 1000 entries in \(Int(writeDuration * 1000))ms")
        XCTAssertLessThan(writeDuration, 1.0, "Cache write should complete in less than 1 second")

        // 测试读取性能
        let readStart = Date()
        for index in 0..<1000 {
            let value: String? = await cacheManager.get(forKey: "key_\(index)")
            XCTAssertNotNil(value)
        }
        let readDuration = Date().timeIntervalSince(readStart)

        print("✅ Cache read: 1000 entries in \(Int(readDuration * 1000))ms")
        XCTAssertLessThan(readDuration, 1.0, "Cache read should complete in less than 1 second")
    }

    func testCacheManager_TTL_Expiration() async throws {
        // 设置 1 秒过期的缓存
        await cacheManager.set("test_value", forKey: "test_key", ttl: 1.0)

        // 立即读取应该成功
        let value1: String? = await cacheManager.get(forKey: "test_key")
        XCTAssertEqual(value1, "test_value")

        // 等待过期
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 秒

        // 过期后读取应该失败
        let value2: String? = await cacheManager.get(forKey: "test_key")
        XCTAssertNil(value2, "Expired cache should return nil")
    }

    func testCacheManager_Cleanup_RemovesExpiredEntries() async throws {
        // 设置多个不同过期时间的缓存
        await cacheManager.set("short_lived", forKey: "key1", ttl: 0.5)
        await cacheManager.set("long_lived", forKey: "key2", ttl: 10.0)

        // 等待短期缓存过期
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒

        // 执行清理
        await cacheManager.cleanup()

        // 验证结果
        let value1: String? = await cacheManager.get(forKey: "key1")
        let value2: String? = await cacheManager.get(forKey: "key2")

        XCTAssertNil(value1, "Expired entry should be removed")
        XCTAssertNotNil(value2, "Valid entry should remain")
    }

    // MARK: - Request Deduplication Tests

    func testDeduplicator_PreventsDuplicateRequests() async throws {
        var requestCount = 0

        let mockRequest: () async throws -> String = {
            requestCount += 1
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "result"
        }

        // 并发发起 5 个相同请求
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await self.deduplicator.deduplicate(key: "test_request", request: mockRequest)
                }
            }

            var results: [String] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        // 验证只执行了一次实际请求
        XCTAssertEqual(requestCount, 1, "Should only execute request once")
        XCTAssertEqual(results.count, 5, "Should return result to all 5 callers")
        XCTAssertTrue(results.allSatisfy { $0 == "result" }, "All results should be identical")
    }

    func testDeduplicator_DifferentKeys_ExecuteSeparately() async throws {
        var requestCount = 0

        let mockRequest: () async throws -> String = {
            requestCount += 1
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            return "result"
        }

        // 并发发起不同 key 的请求
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<3 {
                group.addTask {
                    try await self.deduplicator.deduplicate(key: "key_\(i)", request: mockRequest)
                }
            }

            var results: [String] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        // 验证执行了 3 次请求（每个 key 一次）
        XCTAssertEqual(requestCount, 3, "Should execute request for each unique key")
        XCTAssertEqual(results.count, 3)
    }

    // MARK: - Performance Metrics Tests

    func testPerformanceMetrics_RecordRequest() async throws {
        // 记录多个请求
        await performanceMetrics.recordRequest(
            path: "/feed",
            method: .get,
            duration: 0.5,
            statusCode: 200,
            bytesTransferred: 1024,
            fromCache: false
        )

        await performanceMetrics.recordRequest(
            path: "/feed",
            method: .get,
            duration: 0.1,
            statusCode: 200,
            bytesTransferred: 1024,
            fromCache: true
        )

        // 获取统计
        let stats = await performanceMetrics.getStats()

        XCTAssertEqual(stats.totalRequests, 2)
        XCTAssertEqual(stats.cacheHitRate, 50.0, accuracy: 0.1)
        XCTAssertGreaterThan(stats.averageDuration, 0)
    }

    func testPerformanceMetrics_SlowRequestDetection() async throws {
        // 记录慢请求
        await performanceMetrics.recordRequest(
            path: "/slow-api",
            method: .get,
            duration: 2.5,
            statusCode: 200,
            bytesTransferred: 5000,
            fromCache: false
        )

        await performanceMetrics.recordRequest(
            path: "/fast-api",
            method: .get,
            duration: 0.1,
            statusCode: 200,
            bytesTransferred: 500,
            fromCache: false
        )

        // 获取慢请求
        let slowRequests = await performanceMetrics.getSlowRequests(threshold: 1.0)

        XCTAssertEqual(slowRequests.count, 1)
        XCTAssertEqual(slowRequests.first?.path, "/slow-api")
    }

    // MARK: - Integration Tests

    func testFeedRepository_CacheIntegration() async throws {
        let mockAPIClient = MockAPIClient()
        let repository = FeedRepository(
            apiClient: mockAPIClient,
            cacheManager: cacheManager,
            deduplicator: deduplicator
        )

        // 首次加载（从网络）
        let firstLoad = try await repository.loadFeed()
        XCTAssertEqual(mockAPIClient.requestCount, 1)

        // 第二次加载（从缓存）
        let secondLoad = try await repository.loadFeed()
        XCTAssertEqual(mockAPIClient.requestCount, 1, "Should use cache, not make new request")

        XCTAssertEqual(firstLoad.count, secondLoad.count)
    }

    func testFeedRepository_RequestDeduplication() async throws {
        let mockAPIClient = MockAPIClient()
        let repository = FeedRepository(
            apiClient: mockAPIClient,
            cacheManager: cacheManager,
            deduplicator: deduplicator
        )

        // 清空缓存，确保会发起网络请求
        await cacheManager.clear()

        // 并发发起 3 个相同请求
        let results = try await withThrowingTaskGroup(of: [Post].self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await repository.loadFeed()
                }
            }

            var results: [[Post]] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        // 验证只发起了一次网络请求
        XCTAssertEqual(mockAPIClient.requestCount, 1, "Should deduplicate concurrent requests")
        XCTAssertEqual(results.count, 3, "Should return results to all callers")
    }

    // MARK: - Benchmark Tests

    func testBenchmark_CacheVsNoCachePerformance() async throws {
        let mockAPIClient = MockAPIClient()
        let repositoryWithCache = FeedRepository(
            apiClient: mockAPIClient,
            cacheManager: cacheManager,
            deduplicator: deduplicator
        )

        let repositoryNoCache = FeedRepository(
            apiClient: mockAPIClient,
            cacheManager: nil,
            deduplicator: nil
        )

        // 测试带缓存的性能
        await cacheManager.clear()
        mockAPIClient.requestCount = 0

        let cacheStart = Date()
        _ = try await repositoryWithCache.loadFeed()
        _ = try await repositoryWithCache.loadFeed() // 从缓存加载
        let cacheDuration = Date().timeIntervalSince(cacheStart)

        // 测试不带缓存的性能
        mockAPIClient.requestCount = 0

        let noCacheStart = Date()
        _ = try await repositoryNoCache.loadFeed()
        _ = try await repositoryNoCache.loadFeed() // 重复网络请求
        let noCacheDuration = Date().timeIntervalSince(noCacheStart)

        print("📊 With cache: \(Int(cacheDuration * 1000))ms")
        print("📊 Without cache: \(Int(noCacheDuration * 1000))ms")
        print("📊 Improvement: \(Int((1 - cacheDuration / noCacheDuration) * 100))%")

        // 缓存版本应该更快
        XCTAssertLessThan(cacheDuration, noCacheDuration, "Cache should improve performance")
    }
}

// MARK: - Mock API Client

private final class MockAPIClient: APIClient {
    var requestCount = 0
    var shouldFail = false
    var delay: TimeInterval = 0.1

    override func request<T>(_ endpoint: APIEndpoint, authenticated: Bool) async throws -> T where T : Decodable {
        requestCount += 1

        // 模拟网络延迟
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        if shouldFail {
            throw APIError.networkError(URLError(.timedOut))
        }

        // 返回 mock 数据
        if T.self == FeedResponse.self {
            let mockResponse = FeedResponse(
                posts: [
                    Post(id: "1", userId: "user1", content: "Test post 1", imageUrl: nil, createdAt: Date(), likesCount: 0, commentsCount: 0, isLiked: false),
                    Post(id: "2", userId: "user2", content: "Test post 2", imageUrl: nil, createdAt: Date(), likesCount: 0, commentsCount: 0, isLiked: false)
                ],
                nextCursor: nil,
                hasMore: false
            )
            return mockResponse as! T
        }

        throw APIError.invalidResponse
    }
}
