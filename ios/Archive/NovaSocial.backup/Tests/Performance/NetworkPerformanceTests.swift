import XCTest
@testable import NovaSocial

/// NetworkPerformanceTests - 网络层性能和压力测试
///
/// 测试范围：
/// 1. 批量请求性能
/// 2. 缓存性能提升
/// 3. 并发请求吞吐量
/// 4. 内存使用和泄漏
/// 5. 去重性能
///
final class NetworkPerformanceTests: XCTestCase {

    // MARK: - Setup & Teardown

    var apiClient: APIClient!
    var repository: FeedRepository!
    var cache: CacheManager!

    override func setUp() {
        super.setUp()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        apiClient = APIClient(
            baseURL: URL(string: "https://api.test.com")!,
            session: session
        )

        cache = CacheManager()
        repository = FeedRepository(apiClient: apiClient, cacheManager: cache)

        // 认证
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        MockURLProtocol.reset()
    }

    override func tearDown() {
        AuthManager.shared.clearAuth()
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Batch Request Performance

    /// 测试：批量顺序请求性能
    func testPerformance_SequentialRequests() {
        // Given: Mock 响应
        let mockResponse = TestFixtures.makeFeedResponse()
        try! MockURLProtocol.mockJSON(mockResponse)

        // Measure: 100个顺序请求
        measure {
            let expectation = self.expectation(description: "Sequential requests")

            Task {
                for _ in 0..<100 {
                    _ = try? await self.repository.loadFeed()
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 30.0)
        }
    }

    /// 测试：批量并发请求性能
    func testPerformance_ConcurrentRequests() {
        // Given
        let mockResponse = TestFixtures.makeFeedResponse()
        try! MockURLProtocol.mockJSON(mockResponse)

        // Measure: 100个并发请求
        measure {
            let expectation = self.expectation(description: "Concurrent requests")

            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<100 {
                        group.addTask {
                            _ = try? await self.repository.loadFeed()
                        }
                    }
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 30.0)
        }
    }

    // MARK: - Cache Performance Tests

    /// 测试：缓存命中性能提升
    func testPerformance_CacheHitVsMiss() async throws {
        // Given: 填充缓存
        let mockResponse = TestFixtures.makeFeedResponse()
        try MockURLProtocol.mockJSON(mockResponse)
        _ = try await repository.loadFeed()

        // Measure: 缓存命中的读取速度
        let cacheHitStart = Date()
        for _ in 0..<1000 {
            _ = try await repository.loadFeed() // 应该从缓存读取
        }
        let cacheHitTime = Date().timeIntervalSince(cacheHitStart)

        // Clear cache and measure cache miss
        await cache.clear()
        MockURLProtocol.responseDelay = 0.01 // 模拟网络延迟

        let cacheMissStart = Date()
        for _ in 0..<10 { // 少量请求，因为有网络延迟
            _ = try? await repository.loadFeed()
        }
        let cacheMissTime = Date().timeIntervalSince(cacheMissStart)

        print("📊 Cache hit: \(cacheHitTime)s for 1000 requests")
        print("📊 Cache miss: \(cacheMissTime)s for 10 requests")

        // 缓存命中应该显著更快
        let hitPerRequest = cacheHitTime / 1000
        let missPerRequest = cacheMissTime / 10
        XCTAssertLessThan(hitPerRequest, missPerRequest / 10, "Cache should be at least 10x faster")
    }

    /// 测试：缓存管理器性能
    func testPerformance_CacheManager() {
        let cache = CacheManager()

        measure {
            Task {
                // 写入性能
                for i in 0..<1000 {
                    await cache.set("value_\(i)", forKey: "key_\(i)")
                }

                // 读取性能
                for i in 0..<1000 {
                    let _: String? = await cache.get(forKey: "key_\(i)")
                }
            }
        }
    }

    // MARK: - Deduplication Performance

    /// 测试：请求去重性能
    func testPerformance_RequestDeduplication() {
        // Given
        let mockResponse = TestFixtures.makeFeedResponse()

        var requestCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            requestCount += 1
            lock.unlock()

            Thread.sleep(forTimeInterval: 0.05) // 模拟延迟

            let response = TestFixtures.makeHTTPResponse()
            let data = try! TestFixtures.makeJSONData(mockResponse)
            return (response, data)
        }

        // Measure: 100个并发相同请求的去重效率
        measure {
            requestCount = 0

            let expectation = self.expectation(description: "Deduplication")

            Task {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<100 {
                        group.addTask {
                            _ = try? await self.repository.loadFeed()
                        }
                    }
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)

            print("📊 Deduplication: \(requestCount) actual requests for 100 concurrent calls")
        }
    }

    // MARK: - Memory Tests

    /// 测试：大量数据的内存使用
    func testMemory_LargeDataset() async throws {
        // Given: 大量帖子数据
        let largePosts = TestFixtures.makePosts(count: 1000)
        let largeResponse = TestFixtures.makeFeedResponse(posts: largePosts)

        try MockURLProtocol.mockJSON(largeResponse)

        // When: 多次加载
        for _ in 0..<10 {
            _ = try await repository.loadFeed()
        }

        // Then: 应该不会崩溃或内存溢出
        // 使用 Instruments 的 Allocations 工具检测内存使用
    }

    /// 测试：缓存的内存占用
    func testMemory_CacheUsage() async {
        let cache = CacheManager()

        // When: 缓存大量数据
        for i in 0..<10000 {
            let posts = TestFixtures.makePosts(count: 100)
            await cache.set(posts, forKey: "key_\(i)")
        }

        // Then: 检查内存使用（通过 Instruments）
        let stats = await cache.getStats()
        print("📊 Cache stats: \(stats.totalEntries) entries")
    }

    // MARK: - Throughput Tests

    /// 测试：API 吞吐量
    func testThroughput_RequestsPerSecond() async throws {
        // Given
        let mockResponse = TestFixtures.makeFeedResponse()
        try MockURLProtocol.mockJSON(mockResponse)

        // Measure throughput
        let startTime = Date()
        let requestCount = 100

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<requestCount {
                group.addTask {
                    _ = try? await self.repository.loadFeed()
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let throughput = Double(requestCount) / duration

        print("📊 Throughput: \(throughput) requests/second")
        XCTAssertGreaterThan(throughput, 10, "Should handle at least 10 requests/second")
    }

    // MARK: - Network Delay Simulation

    /// 测试：不同网络延迟下的性能
    func testPerformance_WithNetworkDelay() async throws {
        let delays: [TimeInterval] = [0.01, 0.05, 0.1, 0.2]

        for delay in delays {
            MockURLProtocol.responseDelay = delay

            let mockResponse = TestFixtures.makeFeedResponse()
            try MockURLProtocol.mockJSON(mockResponse)

            let start = Date()
            _ = try await repository.loadFeed()
            let duration = Date().timeIntervalSince(start)

            print("📊 Network delay \(delay)s -> Request duration: \(duration)s")

            // 验证延迟符合预期
            XCTAssertGreaterThanOrEqual(duration, delay, "Duration should include network delay")
        }
    }

    // MARK: - Retry Performance

    /// 测试：重试机制的性能影响
    func testPerformance_RetryImpact() async throws {
        // Given: 前2次失败，第3次成功
        var attemptCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            attemptCount += 1
            let count = attemptCount
            lock.unlock()

            if count < 3 {
                let response = TestFixtures.makeHTTPResponse(statusCode: 503)
                return (response, nil)
            }

            let response = TestFixtures.makeHTTPResponse()
            let data = try! TestFixtures.makeJSONData(TestFixtures.makeFeedResponse())
            return (response, data)
        }

        // Measure: 重试的时间开销
        let start = Date()
        _ = try await repository.loadFeed()
        let duration = Date().timeIntervalSince(start)

        print("📊 Retry impact: \(attemptCount) attempts in \(duration)s")

        // 应该经过了指数退避延迟
        XCTAssertGreaterThan(duration, 1.0, "Should have exponential backoff delay")
    }

    // MARK: - Concurrent User Simulation

    /// 测试：模拟多用户并发场景
    func testStress_MultipleUsersConcurrent() async throws {
        // Given: 模拟 50 个用户同时使用
        let userCount = 50
        let requestsPerUser = 10

        let mockResponse = TestFixtures.makeFeedResponse()
        try MockURLProtocol.mockJSON(mockResponse)

        // When: 每个用户发送多个请求
        let start = Date()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<userCount {
                group.addTask {
                    for _ in 0..<requestsPerUser {
                        _ = try? await self.repository.loadFeed()
                    }
                }
            }
        }

        let duration = Date().timeIntervalSince(start)
        let totalRequests = userCount * requestsPerUser

        print("📊 Stress test: \(totalRequests) requests in \(duration)s")
        print("📊 Throughput: \(Double(totalRequests) / duration) requests/second")

        // Should handle load without crashing
    }

    // MARK: - JSON Parsing Performance

    /// 测试：JSON 解析性能
    func testPerformance_JSONParsing() throws {
        // Given: 大量数据
        let largePosts = TestFixtures.makePosts(count: 1000)
        let jsonData = try TestFixtures.makeJSONData(largePosts)

        // Measure: 解析性能
        measure {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            _ = try? decoder.decode([Post].self, from: jsonData)
        }
    }

    // MARK: - Baseline Comparison

    /// 测试：建立性能基准
    func testBaseline_SingleRequest() {
        let mockResponse = TestFixtures.makeFeedResponse()
        try! MockURLProtocol.mockJSON(mockResponse)

        // 建立基准性能
        measure {
            let expectation = self.expectation(description: "Baseline")

            Task {
                _ = try? await self.repository.loadFeed()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }

        // 这个基准可以用于比较优化前后的性能
    }
}
