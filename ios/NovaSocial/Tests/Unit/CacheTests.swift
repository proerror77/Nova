import XCTest
@testable import NovaSocial

/// CacheTests - 缓存逻辑测试
///
/// 测试范围：
/// 1. 缓存命中和失效
/// 2. TTL 过期机制
/// 3. 缓存一致性
/// 4. 并发安全性
/// 5. 缓存清理
///
final class CacheTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - CacheManager Basic Tests

    /// 测试：缓存存储和读取
    func testCacheManager_SetAndGet_ShouldWork() async {
        // Given
        let cache = CacheManager()

        // When: 存储数据
        await cache.set("test_value", forKey: "test_key", ttl: 60)

        // Then: 应该能读取
        let value: String? = await cache.get(forKey: "test_key")
        XCTAssertNotNil(value)
        XCTAssertEqual(value, "test_value")
    }

    /// 测试：缓存未命中
    func testCacheManager_GetNonExistent_ShouldReturnNil() async {
        // Given
        let cache = CacheManager()

        // When: 读取不存在的 key
        let value: String? = await cache.get(forKey: "non_existent")

        // Then: 应该返回 nil
        XCTAssertNil(value)
    }

    /// 测试：缓存过期
    func testCacheManager_WhenExpired_ShouldReturnNil() async throws {
        // Given: 使用很短的 TTL
        let cache = CacheManager()
        await cache.set("test_value", forKey: "test_key", ttl: 0.1) // 0.1秒

        // When: 等待过期
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // Then: 应该返回 nil
        let value: String? = await cache.get(forKey: "test_key")
        XCTAssertNil(value)
    }

    /// 测试：缓存未过期时正常返回
    func testCacheManager_BeforeExpiration_ShouldReturnValue() async throws {
        // Given
        let cache = CacheManager()
        await cache.set("test_value", forKey: "test_key", ttl: 10) // 10秒

        // When: 立即读取
        let value: String? = await cache.get(forKey: "test_key")

        // Then: 应该返回数据
        XCTAssertNotNil(value)
        XCTAssertEqual(value, "test_value")
    }

    /// 测试：移除缓存
    func testCacheManager_Remove_ShouldDeleteEntry() async {
        // Given
        let cache = CacheManager()
        await cache.set("test_value", forKey: "test_key")

        // When: 移除
        await cache.remove(forKey: "test_key")

        // Then: 应该无法读取
        let value: String? = await cache.get(forKey: "test_key")
        XCTAssertNil(value)
    }

    /// 测试：清空所有缓存
    func testCacheManager_Clear_ShouldRemoveAllEntries() async {
        // Given: 添加多个缓存项
        let cache = CacheManager()
        await cache.set("value1", forKey: "key1")
        await cache.set("value2", forKey: "key2")
        await cache.set("value3", forKey: "key3")

        // When: 清空
        await cache.clear()

        // Then: 所有项都应该被删除
        let value1: String? = await cache.get(forKey: "key1")
        let value2: String? = await cache.get(forKey: "key2")
        let value3: String? = await cache.get(forKey: "key3")

        XCTAssertNil(value1)
        XCTAssertNil(value2)
        XCTAssertNil(value3)
    }

    // MARK: - Complex Data Type Tests

    /// 测试：缓存复杂类型
    func testCacheManager_ComplexTypes_ShouldWork() async {
        // Given
        let cache = CacheManager()
        let posts = TestFixtures.makePosts(count: 5)

        // When: 缓存数组
        await cache.set(posts, forKey: "posts_key")

        // Then: 应该能读取
        let cachedPosts: [Post]? = await cache.get(forKey: "posts_key")
        XCTAssertNotNil(cachedPosts)
        XCTAssertEqual(cachedPosts?.count, 5)
    }

    /// 测试：缓存字典类型
    func testCacheManager_Dictionary_ShouldWork() async {
        // Given
        let cache = CacheManager()
        let dict = ["key1": "value1", "key2": "value2"]

        // When
        await cache.set(dict, forKey: "dict_key")

        // Then
        let cachedDict: [String: String]? = await cache.get(forKey: "dict_key")
        XCTAssertNotNil(cachedDict)
        XCTAssertEqual(cachedDict?["key1"], "value1")
    }

    // MARK: - TTL Tests

    /// 测试：默认 TTL
    func testCacheManager_DefaultTTL_ShouldBeUsed() async throws {
        // Given: 默认 TTL 0.2秒
        let cache = CacheManager(defaultTTL: 0.2)
        await cache.set("test_value", forKey: "test_key") // 不指定 TTL

        // When: 等待超过默认 TTL
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒

        // Then: 应该过期
        let value: String? = await cache.get(forKey: "test_key")
        XCTAssertNil(value)
    }

    /// 测试：自定义 TTL 优先于默认 TTL
    func testCacheManager_CustomTTL_ShouldOverrideDefault() async throws {
        // Given: 默认 TTL 很短，但使用长的自定义 TTL
        let cache = CacheManager(defaultTTL: 0.1)
        await cache.set("test_value", forKey: "test_key", ttl: 10) // 自定义 10秒

        // When: 等待超过默认 TTL 但未超过自定义 TTL
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // Then: 应该仍然有效
        let value: String? = await cache.get(forKey: "test_key")
        XCTAssertNotNil(value)
    }

    // MARK: - Cleanup Tests

    /// 测试：清理过期条目
    func testCacheManager_Cleanup_ShouldRemoveExpiredEntries() async throws {
        // Given: 添加过期和未过期的条目
        let cache = CacheManager()
        await cache.set("expired_value", forKey: "expired_key", ttl: 0.1)
        await cache.set("valid_value", forKey: "valid_key", ttl: 10)

        // When: 等待部分条目过期
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // 执行清理
        await cache.cleanup()

        // Then: 过期的应该被删除，未过期的应该保留
        let expired: String? = await cache.get(forKey: "expired_key")
        let valid: String? = await cache.get(forKey: "valid_key")

        XCTAssertNil(expired)
        XCTAssertNotNil(valid)
    }

    // MARK: - Cache Stats Tests

    /// 测试：缓存统计
    func testCacheManager_Stats_ShouldReflectActualState() async {
        // Given
        let cache = CacheManager()

        // When: 添加多个条目
        await cache.set("value1", forKey: "key1")
        await cache.set("value2", forKey: "key2")
        await cache.set("value3", forKey: "key3")

        let stats = await cache.getStats()

        // Then
        XCTAssertEqual(stats.totalEntries, 3)

        // When: 删除一个
        await cache.remove(forKey: "key1")
        let statsAfterRemove = await cache.getStats()

        // Then
        XCTAssertEqual(statsAfterRemove.totalEntries, 2)
    }

    // MARK: - Concurrency Tests

    /// 测试：并发读写安全
    func testCacheManager_ConcurrentAccess_ShouldBeSafe() async {
        // Given
        let cache = CacheManager()

        // When: 并发读写
        await withTaskGroup(of: Void.self) { group in
            // 并发写入
            for i in 0..<50 {
                group.addTask {
                    await cache.set("value_\(i)", forKey: "key_\(i)")
                }
            }

            // 并发读取
            for i in 0..<50 {
                group.addTask {
                    let _: String? = await cache.get(forKey: "key_\(i)")
                }
            }

            // 并发删除
            for i in 0..<10 {
                group.addTask {
                    await cache.remove(forKey: "key_\(i)")
                }
            }
        }

        // Then: 应该不会崩溃（Actor 保证线程安全）
    }

    // MARK: - FeedCache Tests (Legacy)

    /// 测试：Legacy FeedCache 基本功能
    func testFeedCache_SetAndGet_ShouldWork() {
        // Given
        let cache = FeedCache()
        let posts = TestFixtures.makePosts(count: 10)

        // When
        cache.cacheFeed(posts)
        let cached = cache.getCachedFeed()

        // Then
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.count, 10)
    }

    /// 测试：Legacy FeedCache 最大容量
    func testFeedCache_MaxSize_ShouldBeLimited() {
        // Given
        let cache = FeedCache()
        let largePosts = TestFixtures.makePosts(count: 100)

        // When: 缓存大量数据
        cache.cacheFeed(largePosts)
        let cached = cache.getCachedFeed()

        // Then: 应该只保留最多 50 条
        XCTAssertNotNil(cached)
        XCTAssertLessThanOrEqual(cached?.count ?? 0, 50)
    }

    /// 测试：Legacy FeedCache 清空
    func testFeedCache_Clear_ShouldRemoveData() {
        // Given
        let cache = FeedCache()
        let posts = TestFixtures.makePosts(count: 10)
        cache.cacheFeed(posts)

        // When: 清空
        cache.clearCache()

        // Then: 应该无数据
        let cached = cache.getCachedFeed()
        XCTAssertNil(cached)
    }

    // MARK: - Cache Key Tests

    /// 测试：缓存键生成
    func testCacheKey_Generation_ShouldBeConsistent() {
        // Feed 键
        let feedKey1 = CacheKey.feed(cursor: nil)
        let feedKey2 = CacheKey.feed(cursor: nil)
        XCTAssertEqual(feedKey1, feedKey2, "Same parameters should generate same key")

        // 不同参数应该生成不同的键
        let feedKey3 = CacheKey.feed(cursor: "abc123")
        XCTAssertNotEqual(feedKey1, feedKey3)

        // Explore Feed 键
        let exploreKey1 = CacheKey.exploreFeed(page: 1)
        let exploreKey2 = CacheKey.exploreFeed(page: 1)
        XCTAssertEqual(exploreKey1, exploreKey2)

        // User Profile 键
        let userKey = CacheKey.userProfile(userId: "user123")
        XCTAssertTrue(userKey.contains("user123"))
    }

    // MARK: - Integration Tests

    /// 测试：缓存与实际业务集成
    func testCache_WithRealRepository_ShouldWork() async throws {
        // 这个测试在 FeedRepositoryTests 中已经覆盖
        // 这里可以添加更多集成场景
    }

    // MARK: - Performance Tests

    /// 测试：缓存读写性能
    func testCachePerformance_ReadWrite() {
        let cache = CacheManager()

        measure {
            Task {
                for i in 0..<100 {
                    await cache.set("value_\(i)", forKey: "key_\(i)")
                    let _: String? = await cache.get(forKey: "key_\(i)")
                }
            }
        }
    }
}
