import XCTest
@testable import NovaSocial

/// FeedRepositoryTests - Feed 仓库单元测试
///
/// 测试范围：
/// 1. Feed 加载和分页
/// 2. 缓存命中和失效
/// 3. 下拉刷新
/// 4. Explore Feed
/// 5. 请求去重
///
final class FeedRepositoryTests: XCTestCase {

    // MARK: - Properties

    var repository: FeedRepository!
    var apiClient: APIClient!
    var cache: FeedCache!
    var cacheManager: CacheManager!
    var deduplicator: RequestDeduplicator!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        apiClient = APIClient(
            baseURL: URL(string: "https://api.test.com")!,
            session: session
        )

        cache = FeedCache()
        cacheManager = CacheManager(defaultTTL: CacheTTL.feed)
        deduplicator = RequestDeduplicator()

        repository = FeedRepository(
            apiClient: apiClient,
            cache: cache,
            cacheManager: cacheManager,
            deduplicator: deduplicator
        )

        // 认证设置
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        MockURLProtocol.reset()
    }

    override func tearDown() {
        cache.clearCache()
        AuthManager.shared.clearAuth()
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Load Feed Tests

    /// 测试：首次加载 Feed 成功
    func testLoadFeed_WhenFirstLoad_ShouldReturnPosts() async throws {
        // Given: Mock 成功响应
        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = TestFixtures.makeFeedResponse(
            posts: mockPosts,
            nextCursor: "cursor_10"
        )

        try MockURLProtocol.mockJSON(mockResponse)

        // When: 加载 Feed
        let posts = try await repository.loadFeed(limit: 10)

        // Then: 返回帖子列表
        XCTAssertEqual(posts.count, 10)
        XCTAssertEqual(posts.first?.caption, "Test post 0")
    }

    /// 测试：分页加载
    func testLoadFeed_WithCursor_ShouldLoadNextPage() async throws {
        // Given: Mock 第二页数据
        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = TestFixtures.makeFeedResponse(
            posts: mockPosts,
            nextCursor: "cursor_20"
        )

        try MockURLProtocol.mockJSON(mockResponse)

        // When: 使用 cursor 加载
        let posts = try await repository.loadFeed(cursor: "cursor_10", limit: 10)

        // Then: 返回下一页数据
        XCTAssertEqual(posts.count, 10)
    }

    /// 测试：加载时网络错误
    func testLoadFeed_WhenNetworkError_ShouldThrowError() async throws {
        // Given: Mock 网络错误
        MockURLProtocol.mockNoConnection()

        // When & Then
        do {
            _ = try await repository.loadFeed()
            XCTFail("Should throw network error")
        } catch let error as APIError {
            XCTAssertEqual(error, .noConnection)
        }
    }

    // MARK: - Cache Tests

    /// 测试：缓存命中时返回缓存数据
    func testLoadFeed_WhenCacheHit_ShouldReturnCachedData() async throws {
        // Given: 先加载一次数据（填充缓存）
        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = TestFixtures.makeFeedResponse(posts: mockPosts)
        try MockURLProtocol.mockJSON(mockResponse)

        _ = try await repository.loadFeed()

        // 清除 Mock 以验证不会再次请求网络
        var networkRequestCount = 0
        MockURLProtocol.requestHandler = { _ in
            networkRequestCount += 1
            let response = TestFixtures.makeHTTPResponse()
            let data = try! TestFixtures.makeJSONData(mockResponse)
            return (response, data)
        }

        // When: 再次加载（应该从缓存返回）
        let cachedPosts = try await repository.loadFeed()

        // Then: 返回缓存数据
        XCTAssertEqual(cachedPosts.count, 10)

        // 等待后台刷新任务完成
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        // 后台应该触发了一次刷新请求
        XCTAssertGreaterThanOrEqual(networkRequestCount, 1, "Should trigger background refresh")
    }

    /// 测试：缓存过期后重新加载
    func testLoadFeed_WhenCacheExpired_ShouldRefetchData() async throws {
        // Given: 使用很短的 TTL
        let shortTTLCacheManager = CacheManager(defaultTTL: 0.1) // 0.1秒
        repository = FeedRepository(
            apiClient: apiClient,
            cache: cache,
            cacheManager: shortTTLCacheManager,
            deduplicator: deduplicator
        )

        // 第一次加载
        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = TestFixtures.makeFeedResponse(posts: mockPosts)
        try MockURLProtocol.mockJSON(mockResponse)
        _ = try await repository.loadFeed()

        // 等待缓存过期
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        var networkRequestCount = 0
        MockURLProtocol.requestHandler = { _ in
            networkRequestCount += 1
            let response = TestFixtures.makeHTTPResponse()
            let data = try! TestFixtures.makeJSONData(mockResponse)
            return (response, data)
        }

        // When: 再次加载
        _ = try await repository.loadFeed()

        // Then: 应该触发网络请求
        XCTAssertEqual(networkRequestCount, 1, "Should refetch when cache expired")
    }

    // MARK: - Refresh Tests

    /// 测试：下拉刷新清除缓存
    func testRefreshFeed_ShouldClearCacheAndFetchNew() async throws {
        // Given: 先加载一次（填充缓存）
        let oldPosts = TestFixtures.makePosts(count: 5)
        let oldResponse = TestFixtures.makeFeedResponse(posts: oldPosts)
        try MockURLProtocol.mockJSON(oldResponse)
        _ = try await repository.loadFeed()

        // 验证缓存存在
        let cachedBefore = cache.getCachedFeed()
        XCTAssertNotNil(cachedBefore)

        // Mock 新数据
        let newPosts = TestFixtures.makePosts(count: 8)
        let newResponse = TestFixtures.makeFeedResponse(posts: newPosts)
        try MockURLProtocol.mockJSON(newResponse)

        // When: 刷新
        let refreshedPosts = try await repository.refreshFeed()

        // Then: 返回新数据
        XCTAssertEqual(refreshedPosts.count, 8)
    }

    // MARK: - Explore Feed Tests

    /// 测试：加载 Explore Feed
    func testLoadExploreFeed_ShouldReturnPosts() async throws {
        // Given
        struct ExploreResponse: Codable {
            let posts: [Post]
            let hasMore: Bool

            enum CodingKeys: String, CodingKey {
                case posts
                case hasMore = "has_more"
            }
        }

        let mockPosts = TestFixtures.makePosts(count: 15)
        let mockResponse = ExploreResponse(posts: mockPosts, hasMore: true)
        try MockURLProtocol.mockJSON(mockResponse)

        // When
        let posts = try await repository.loadExploreFeed(page: 1, limit: 30)

        // Then
        XCTAssertEqual(posts.count, 15)
    }

    /// 测试：Explore Feed 分页
    func testLoadExploreFeed_WithPagination_ShouldLoadDifferentPages() async throws {
        // Given: Mock 第2页数据
        struct ExploreResponse: Codable {
            let posts: [Post]
            let hasMore: Bool

            enum CodingKeys: String, CodingKey {
                case posts
                case hasMore = "has_more"
            }
        }

        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = ExploreResponse(posts: mockPosts, hasMore: false)
        try MockURLProtocol.mockJSON(mockResponse)

        // When: 加载第2页
        let posts = try await repository.loadExploreFeed(page: 2)

        // Then
        XCTAssertEqual(posts.count, 10)
    }

    // MARK: - Request Deduplication Tests

    /// 测试：并发相同请求应该被去重
    func testLoadFeed_ConcurrentIdenticalRequests_ShouldDeduplicate() async throws {
        // Given
        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = TestFixtures.makeFeedResponse(posts: mockPosts)

        var requestCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            requestCount += 1
            lock.unlock()

            Thread.sleep(forTimeInterval: 0.1) // 模拟网络延迟

            let response = TestFixtures.makeHTTPResponse()
            let data = try! TestFixtures.makeJSONData(mockResponse)
            return (response, data)
        }

        // When: 10个并发的相同请求
        await withTaskGroup(of: [Post]?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await self.repository.loadFeed()
                }
            }

            // 等待所有任务完成
            for await _ in group { }
        }

        // Then: 去重后应该只发送少量请求
        print("📊 Deduplication test: \(requestCount) requests sent (expected: ~1-2)")
        XCTAssertLessThanOrEqual(requestCount, 3, "Should deduplicate concurrent requests")
    }

    // MARK: - Legacy Cache Tests

    /// 测试：Legacy Cache 向后兼容
    func testLoadFeed_ShouldUpdateLegacyCache() async throws {
        // Given
        let mockPosts = TestFixtures.makePosts(count: 10)
        let mockResponse = TestFixtures.makeFeedResponse(posts: mockPosts)
        try MockURLProtocol.mockJSON(mockResponse)

        // 清空 Legacy Cache
        cache.clearCache()
        XCTAssertNil(cache.getCachedFeed())

        // When: 加载 Feed
        _ = try await repository.loadFeed()

        // Then: Legacy Cache 应该被更新
        let legacyCached = cache.getCachedFeed()
        XCTAssertNotNil(legacyCached)
        XCTAssertEqual(legacyCached?.count, 10)
    }

    /// 测试：Legacy Cache 最大容量限制
    func testLegacyCache_ShouldRespectMaxSize() {
        // Given: 大量帖子
        let largePosts = TestFixtures.makePosts(count: 100)

        // When: 缓存
        cache.cacheFeed(largePosts)

        // Then: 只缓存最多 50 条
        let cached = cache.getCachedFeed()
        XCTAssertNotNil(cached)
        XCTAssertLessThanOrEqual(cached?.count ?? 0, 50)
    }

    // MARK: - Performance Tests

    /// 测试：Feed 加载性能
    func testLoadFeed_Performance() throws {
        // Given
        let mockPosts = TestFixtures.makePosts(count: 20)
        let mockResponse = TestFixtures.makeFeedResponse(posts: mockPosts)
        try MockURLProtocol.mockJSON(mockResponse)

        // 性能测试
        measure {
            let expectation = self.expectation(description: "Load feed")

            Task {
                _ = try await self.repository.loadFeed()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 2.0)
        }
    }
}
