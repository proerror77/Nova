import XCTest
@testable import NovaSocial

/// 网络层单元测试
/// 遵循 TDD 原则：红-绿-重构
final class NetworkTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        // 清理测试环境
        AuthManager.shared.clearAuth()
    }

    override func tearDown() {
        AuthManager.shared.clearAuth()
        super.tearDown()
    }

    // MARK: - APIError Tests

    func testAPIErrorMapping() {
        // 测试 HTTP 状态码映射
        let error401 = APIError.from(statusCode: 401, data: nil)
        XCTAssertEqual(error401 as? APIError, .unauthorized)

        let error404 = APIError.from(statusCode: 404, data: nil)
        XCTAssertEqual(error404 as? APIError, .notFound)

        let error500 = APIError.from(statusCode: 500, data: nil)
        XCTAssertEqual(error500 as? APIError, .serverError)
    }

    func testAPIErrorDescription() {
        // 测试错误描述
        XCTAssertNotNil(APIError.unauthorized.errorDescription)
        XCTAssertEqual(APIError.unauthorized.errorDescription, "登录已过期，请重新登录")

        XCTAssertNotNil(APIError.noConnection.errorDescription)
        XCTAssertEqual(APIError.noConnection.errorDescription, "无网络连接，请检查网络后重试")
    }

    func testAPIErrorRetryLogic() {
        // 测试哪些错误应该重试
        XCTAssertTrue(APIError.timeout.shouldRetry)
        XCTAssertTrue(APIError.noConnection.shouldRetry)
        XCTAssertTrue(APIError.serverError.shouldRetry)

        XCTAssertFalse(APIError.unauthorized.shouldRetry)
        XCTAssertFalse(APIError.notFound.shouldRetry)
        XCTAssertFalse(APIError.invalidCredentials.shouldRetry)
    }

    // MARK: - AuthManager Tests

    func testAuthManagerSaveAndLoad() {
        // 创建测试数据
        let user = User(
            id: UUID(),
            username: "testuser",
            email: "test@example.com",
            displayName: "Test User",
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )

        let tokens = AuthTokens(
            accessToken: "test_access_token",
            refreshToken: "test_refresh_token",
            expiresIn: 900,
            tokenType: "Bearer"
        )

        // 保存认证信息
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // 验证状态
        XCTAssertTrue(AuthManager.shared.isAuthenticated)
        XCTAssertEqual(AuthManager.shared.currentUser?.username, "testuser")
        XCTAssertEqual(AuthManager.shared.accessToken, "test_access_token")
        XCTAssertEqual(AuthManager.shared.refreshToken, "test_refresh_token")
    }

    func testAuthManagerClearAuth() {
        // 先保存一些数据
        let user = User(
            id: UUID(),
            username: "testuser",
            email: "test@example.com",
            displayName: nil,
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )

        let tokens = AuthTokens(
            accessToken: "test_token",
            refreshToken: "test_refresh",
            expiresIn: 900,
            tokenType: "Bearer"
        )

        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // 清空认证
        AuthManager.shared.clearAuth()

        // 验证状态
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
        XCTAssertNil(AuthManager.shared.currentUser)
        XCTAssertNil(AuthManager.shared.accessToken)
        XCTAssertNil(AuthManager.shared.refreshToken)
    }

    func testAuthManagerTokenExpiry() {
        // 创建一个已过期的 Token
        let user = User(
            id: UUID(),
            username: "testuser",
            email: "test@example.com",
            displayName: nil,
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )

        let tokens = AuthTokens(
            accessToken: "test_token",
            refreshToken: "test_refresh",
            expiresIn: -1, // 已过期
            tokenType: "Bearer"
        )

        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // 验证 Token 过期状态
        XCTAssertTrue(AuthManager.shared.isTokenExpired)
    }

    // MARK: - APIEndpoint Tests

    func testAPIEndpointConstruction() {
        let endpoint = APIEndpoint(
            path: "/posts",
            method: .get,
            queryItems: [
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "cursor", value: "abc123")
            ]
        )

        XCTAssertEqual(endpoint.path, "/posts")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.queryItems?.count, 2)
    }

    // MARK: - Model Decoding Tests

    func testUserModelDecoding() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "username": "testuser",
            "email": "test@example.com",
            "display_name": "Test User",
            "bio": "Hello world",
            "avatar_url": "https://example.com/avatar.jpg",
            "is_verified": true,
            "created_at": "2024-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let user = try decoder.decode(User.self, from: data)

        XCTAssertEqual(user.username, "testuser")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.displayName, "Test User")
        XCTAssertTrue(user.isVerified)
    }

    func testPostModelDecoding() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "image_url": "https://cdn.example.com/image.jpg",
            "thumbnail_url": "https://cdn.example.com/thumb.jpg",
            "caption": "Test post",
            "like_count": 10,
            "comment_count": 5,
            "is_liked": false,
            "created_at": "2024-01-01T00:00:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let post = try decoder.decode(Post.self, from: data)

        XCTAssertEqual(post.caption, "Test post")
        XCTAssertEqual(post.likeCount, 10)
        XCTAssertEqual(post.commentCount, 5)
        XCTAssertFalse(post.isLiked)
    }

    // MARK: - FeedCache Tests

    func testFeedCacheSaveAndLoad() {
        let cache = FeedCache()

        // 创建测试帖子
        let posts = [
            Post(
                id: UUID(),
                userId: UUID(),
                imageUrl: "https://example.com/1.jpg",
                thumbnailUrl: nil,
                caption: "Post 1",
                likeCount: 10,
                commentCount: 5,
                isLiked: false,
                createdAt: Date(),
                user: nil
            ),
            Post(
                id: UUID(),
                userId: UUID(),
                imageUrl: "https://example.com/2.jpg",
                thumbnailUrl: nil,
                caption: "Post 2",
                likeCount: 20,
                commentCount: 10,
                isLiked: true,
                createdAt: Date(),
                user: nil
            )
        ]

        // 缓存数据
        cache.cacheFeed(posts)

        // 读取缓存
        let cachedPosts = cache.getCachedFeed()

        XCTAssertNotNil(cachedPosts)
        XCTAssertEqual(cachedPosts?.count, 2)
        XCTAssertEqual(cachedPosts?.first?.caption, "Post 1")
    }

    func testFeedCacheClear() {
        let cache = FeedCache()

        // 先缓存一些数据
        let posts = [
            Post(
                id: UUID(),
                userId: UUID(),
                imageUrl: "https://example.com/1.jpg",
                thumbnailUrl: nil,
                caption: "Post 1",
                likeCount: 10,
                commentCount: 5,
                isLiked: false,
                createdAt: Date(),
                user: nil
            )
        ]

        cache.cacheFeed(posts)

        // 清空缓存
        cache.clearCache()

        // 验证缓存已清空
        let cachedPosts = cache.getCachedFeed()
        XCTAssertNil(cachedPosts)
    }

    // MARK: - Logger Tests

    func testLogger() {
        // 日志测试（仅验证不会崩溃）
        Logger.log("Test debug message", level: .debug)
        Logger.log("Test info message", level: .info)
        Logger.log("Test warning message", level: .warning)
        Logger.log("Test error message", level: .error)
    }

    // MARK: - AppConfig Tests

    func testEnvironmentConfiguration() {
        XCTAssertNotNil(AppConfig.baseURL)
        XCTAssertGreaterThan(AppConfig.timeout, 0)
    }

    func testFeatureFlags() {
        XCTAssertTrue(FeatureFlags.enableOfflineMode)
        XCTAssertGreaterThan(FeatureFlags.maxRetryAttempts, 0)
        XCTAssertGreaterThan(FeatureFlags.feedPageSize, 0)
    }
}

// MARK: - Mock API Client (用于集成测试)

class MockAPIClient: APIClient {
    var shouldFail = false
    var mockResponse: Decodable?
    var mockError: APIError?

    override func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true
    ) async throws -> T {
        if shouldFail, let error = mockError {
            throw error
        }

        if let response = mockResponse as? T {
            return response
        }

        throw APIError.invalidResponse
    }
}

// MARK: - Token Refresh Concurrency Tests

/// 测试 Token 刷新的并发场景
/// 这是最关键的测试 - 验证多个 401 同时发生时的行为
final class TokenRefreshConcurrencyTests: XCTestCase {

    // MARK: - Setup

    private var mockClient: MockAPIClientForRefresh!
    private var interceptor: RequestInterceptor!

    override func setUp() {
        super.setUp()
        mockClient = MockAPIClientForRefresh()
        interceptor = RequestInterceptor(apiClient: mockClient)
        AuthManager.shared.clearAuth()

        // 设置过期的 Token（触发刷新）
        let user = User(
            id: UUID(),
            username: "testuser",
            email: "test@example.com",
            displayName: nil,
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )

        let tokens = AuthTokens(
            accessToken: "expired_token",
            refreshToken: "valid_refresh_token",
            expiresIn: -1, // 已过期
            tokenType: "Bearer"
        )

        AuthManager.shared.saveAuth(user: user, tokens: tokens)
    }

    override func tearDown() {
        AuthManager.shared.clearAuth()
        mockClient = nil
        interceptor = nil
        super.tearDown()
    }

    // MARK: - Concurrency Tests

    /// 测试：10个并发请求同时遇到 401，应该只刷新一次 Token
    func testConcurrent401RequestsShouldRefreshOnce() async throws {
        let expectation = XCTestExpectation(description: "All requests complete")
        expectation.expectedFulfillmentCount = 10

        // 模拟刷新成功
        mockClient.refreshShouldSucceed = true
        mockClient.refreshDelay = 1.0 // 模拟网络延迟

        var errors: [Error] = []
        let errorLock = NSLock()

        // 启动 10 个并发请求
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    do {
                        let _: MockResponse = try await self.interceptor.executeWithRetry(
                            APIEndpoint(path: "/test/\(i)", method: .get),
                            authenticated: true
                        )
                        expectation.fulfill()
                    } catch {
                        errorLock.lock()
                        errors.append(error)
                        errorLock.unlock()
                        expectation.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // 验证：应该只刷新了一次
        XCTAssertEqual(mockClient.refreshCallCount, 1, "Token should only be refreshed once")

        // 验证：所有请求都成功
        XCTAssertTrue(errors.isEmpty, "All requests should succeed after token refresh")
    }

    /// 测试：刷新失败时，所有等待的请求都应该收到错误
    func testConcurrent401WithRefreshFailure() async throws {
        let expectation = XCTestExpectation(description: "All requests fail")
        expectation.expectedFulfillmentCount = 5

        // 模拟刷新失败
        mockClient.refreshShouldSucceed = false
        mockClient.refreshDelay = 0.5

        var failureCount = 0
        let countLock = NSLock()

        // 启动 5 个并发请求
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    do {
                        let _: MockResponse = try await self.interceptor.executeWithRetry(
                            APIEndpoint(path: "/test/\(i)", method: .get),
                            authenticated: true,
                            maxRetries: 2 // 减少重试次数加快测试
                        )
                        expectation.fulfill()
                    } catch {
                        countLock.lock()
                        failureCount += 1
                        countLock.unlock()
                        expectation.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // 验证：所有请求都失败
        XCTAssertEqual(failureCount, 5, "All requests should fail when refresh fails")

        // 验证：只尝试刷新了一次
        XCTAssertEqual(mockClient.refreshCallCount, 1, "Should only attempt refresh once")
    }

    /// 测试：刷新超时场景
    func testTokenRefreshTimeout() async throws {
        // 模拟非常慢的刷新（超过超时时间）
        mockClient.refreshShouldSucceed = true
        mockClient.refreshDelay = 35.0 // 超过 30 秒超时

        do {
            let _: MockResponse = try await interceptor.executeWithRetry(
                APIEndpoint(path: "/test", method: .get),
                authenticated: true,
                maxRetries: 1
            )
            XCTFail("Should timeout")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout, "Should fail with timeout error")
        }
    }

    /// 测试：快速连续的刷新请求（第二个请求应该复用第一个刷新任务）
    func testRapidSuccessiveRefreshRequests() async throws {
        mockClient.refreshShouldSucceed = true
        mockClient.refreshDelay = 0.5

        let expectation = XCTestExpectation(description: "Both requests complete")
        expectation.expectedFulfillmentCount = 2

        // 第一个请求
        Task {
            _ = try? await interceptor.executeWithRetry(
                APIEndpoint(path: "/test1", method: .get),
                authenticated: true
            ) as MockResponse
            expectation.fulfill()
        }

        // 等待 0.1 秒，确保第一个请求已开始刷新
        try await Task.sleep(nanoseconds: 100_000_000)

        // 第二个请求（应该复用第一个刷新任务）
        Task {
            _ = try? await interceptor.executeWithRetry(
                APIEndpoint(path: "/test2", method: .get),
                authenticated: true
            ) as MockResponse
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        // 验证：只刷新了一次
        XCTAssertEqual(mockClient.refreshCallCount, 1, "Should reuse first refresh task")
    }
}

// MARK: - Mock API Client for Refresh Testing

/// 专门用于测试 Token 刷新的 Mock Client
class MockAPIClientForRefresh: APIClient {
    var refreshCallCount = 0
    var refreshShouldSucceed = true
    var refreshDelay: TimeInterval = 0

    private let countLock = NSLock()

    override func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true
    ) async throws -> T {
        // 模拟刷新端点
        if endpoint.path == "/auth/refresh" {
            countLock.lock()
            refreshCallCount += 1
            countLock.unlock()

            // 模拟网络延迟
            if refreshDelay > 0 {
                try await Task.sleep(nanoseconds: UInt64(refreshDelay * 1_000_000_000))
            }

            if refreshShouldSucceed {
                let refreshResponse = RefreshResponse(
                    accessToken: "new_access_token_\(UUID().uuidString)",
                    expiresIn: 900
                )

                if let response = refreshResponse as? T {
                    return response
                }
            }

            throw APIError.unauthorized
        }

        // 其他端点返回成功
        let mockResponse = MockResponse(success: true)
        if let response = mockResponse as? T {
            return response
        }

        throw APIError.invalidResponse
    }

    // 内部类型定义
    struct RefreshResponse: Codable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }
}

struct MockResponse: Codable {
    let success: Bool
}

// MARK: - Integration Tests (需要真实后端)

final class NetworkIntegrationTests: XCTestCase {

    // 这些测试需要真实的后端服务运行
    // 在 CI/CD 环境中应该跳过或使用 Mock Server

    func testLoginIntegration() async throws {
        // 跳过测试如果没有真实后端
        try XCTSkipIf(true, "Requires real backend")

        let authRepo = AuthRepository()

        do {
            let (user, tokens) = try await authRepo.login(
                email: "test@example.com",
                password: "password123"
            )

            XCTAssertNotNil(user)
            XCTAssertNotNil(tokens.accessToken)

        } catch {
            XCTFail("Login failed: \(error)")
        }
    }

    func testFeedLoadIntegration() async throws {
        try XCTSkipIf(true, "Requires real backend")

        let feedRepo = FeedRepository()

        do {
            let posts = try await feedRepo.loadFeed(limit: 10)

            XCTAssertNotNil(posts)
            XCTAssertLessThanOrEqual(posts.count, 10)

        } catch {
            XCTFail("Feed load failed: \(error)")
        }
    }
}
