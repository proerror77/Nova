import XCTest
@testable import NovaSocial

/// ErrorHandlingTests - 错误处理和重试机制测试
///
/// 测试范围：
/// 1. 各种 HTTP 错误码处理
/// 2. 网络超时和连接错误
/// 3. 自动重试机制
/// 4. 指数退避算法
/// 5. 错误恢复策略
///
final class ErrorHandlingTests: XCTestCase {

    // MARK: - Properties

    var apiClient: APIClient!
    var interceptor: RequestInterceptor!

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
        interceptor = RequestInterceptor(apiClient: apiClient)

        AuthManager.shared.clearAuth()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        AuthManager.shared.clearAuth()
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - HTTP Error Code Tests

    /// 测试：400 Bad Request
    func testHTTPError_400_ShouldMapToBadRequest() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 400)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest)
        }
    }

    /// 测试：401 Unauthorized
    func testHTTPError_401_ShouldMapToUnauthorized() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 401)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    /// 测试：403 Forbidden
    func testHTTPError_403_ShouldMapToForbidden() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 403)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden)
        }
    }

    /// 测试：404 Not Found
    func testHTTPError_404_ShouldMapToNotFound() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 404)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound)
        }
    }

    /// 测试：429 Too Many Requests
    func testHTTPError_429_ShouldMapToRateLimited() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 429)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .rateLimited)
        }
    }

    /// 测试：500 Internal Server Error
    func testHTTPError_500_ShouldMapToServerError() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 500)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .serverError)
        }
    }

    /// 测试：503 Service Unavailable
    func testHTTPError_503_ShouldMapToServiceUnavailable() async throws {
        // Given
        MockURLProtocol.mockError(statusCode: 503)

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .serviceUnavailable)
        }
    }

    // MARK: - Network Error Tests

    /// 测试：网络超时
    func testNetworkTimeout_ShouldMapToTimeout() async throws {
        // Given
        MockURLProtocol.mockTimeout()

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw timeout error")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout)
        }
    }

    /// 测试：无网络连接
    func testNoConnection_ShouldMapToNoConnection() async throws {
        // Given
        MockURLProtocol.mockNoConnection()

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await apiClient.request(endpoint, authenticated: false)
            XCTFail("Should throw no connection error")
        } catch let error as APIError {
            XCTAssertEqual(error, .noConnection)
        }
    }

    // MARK: - Retry Logic Tests

    /// 测试：可重试错误应该自动重试
    func testRetriableError_ShouldRetry() async throws {
        // Given: 前2次失败，第3次成功
        var attemptCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            attemptCount += 1
            let count = attemptCount
            lock.unlock()

            if count < 3 {
                // 前2次返回 503
                let response = TestFixtures.makeHTTPResponse(statusCode: 503)
                return (response, nil)
            } else {
                // 第3次成功
                struct SuccessResponse: Codable { let success: Bool }
                let response = TestFixtures.makeHTTPResponse(statusCode: 200)
                let data = try! TestFixtures.makeJSONData(SuccessResponse(success: true))
                return (response, data)
            }
        }

        // When
        let endpoint = APIEndpoint(path: "/test", method: .get)
        struct SuccessResponse: Codable { let success: Bool }
        let result: SuccessResponse = try await interceptor.executeWithRetry(
            endpoint,
            authenticated: false,
            maxRetries: 3
        )

        // Then: 应该成功（经过重试）
        XCTAssertTrue(result.success)
        XCTAssertEqual(attemptCount, 3, "Should retry twice before success")
    }

    /// 测试：不可重试错误不应该重试
    func testNonRetriableError_ShouldNotRetry() async throws {
        // Given: 返回 400 Bad Request
        var attemptCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            attemptCount += 1
            lock.unlock()

            let response = TestFixtures.makeHTTPResponse(statusCode: 400)
            return (response, nil)
        }

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await interceptor.executeWithRetry(
                endpoint,
                authenticated: false,
                maxRetries: 3
            )
            XCTFail("Should throw error")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest)
        }

        // 应该只尝试一次（不重试）
        XCTAssertEqual(attemptCount, 1, "Should not retry non-retriable errors")
    }

    /// 测试：重试次数用尽后失败
    func testRetry_WhenExceedMaxAttempts_ShouldFail() async throws {
        // Given: 始终返回 500
        var attemptCount = 0
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            attemptCount += 1
            lock.unlock()

            let response = TestFixtures.makeHTTPResponse(statusCode: 500)
            return (response, nil)
        }

        // When & Then
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await interceptor.executeWithRetry(
                endpoint,
                authenticated: false,
                maxRetries: 3
            )
            XCTFail("Should throw error after max retries")
        } catch let error as APIError {
            XCTAssertEqual(error, .serverError)
        }

        // 应该尝试3次
        XCTAssertEqual(attemptCount, 3, "Should retry max times")
    }

    // MARK: - Exponential Backoff Tests

    /// 测试：指数退避延迟增长
    func testExponentialBackoff_DelayShouldIncrease() async throws {
        // Given
        var attemptTimes: [Date] = []
        let lock = NSLock()

        MockURLProtocol.requestHandler = { request in
            lock.lock()
            attemptTimes.append(Date())
            lock.unlock()

            if attemptTimes.count < 3 {
                let response = TestFixtures.makeHTTPResponse(statusCode: 503)
                return (response, nil)
            }

            struct SuccessResponse: Codable { let success: Bool }
            let response = TestFixtures.makeHTTPResponse(statusCode: 200)
            let data = try! TestFixtures.makeJSONData(SuccessResponse(success: true))
            return (response, data)
        }

        // When
        let endpoint = APIEndpoint(path: "/test", method: .get)
        struct SuccessResponse: Codable { let success: Bool }
        _ = try await interceptor.executeWithRetry(
            endpoint,
            authenticated: false,
            maxRetries: 3
        )

        // Then: 验证延迟时间递增
        XCTAssertEqual(attemptTimes.count, 3)

        if attemptTimes.count >= 3 {
            let delay1 = attemptTimes[1].timeIntervalSince(attemptTimes[0])
            let delay2 = attemptTimes[2].timeIntervalSince(attemptTimes[1])

            // 第二次延迟应该大于第一次（指数退避）
            // 允许一些误差，因为有随机抖动
            print("📊 Backoff delays: \(delay1)s, \(delay2)s")
            XCTAssertGreaterThan(delay2, delay1 * 0.8, "Second delay should be longer than first")
        }
    }

    // MARK: - Error Recovery Tests

    /// 测试：401 错误应该触发 Token 刷新
    func testError401_ShouldTriggerTokenRefresh() async throws {
        // Given: 有效的 refresh token
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        var refreshCalled = false

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/auth/refresh" {
                refreshCalled = true

                struct RefreshResponse: Codable {
                    let accessToken: String
                    let expiresIn: Int

                    enum CodingKeys: String, CodingKey {
                        case accessToken = "access_token"
                        case expiresIn = "expires_in"
                    }
                }

                let response = TestFixtures.makeHTTPResponse(statusCode: 200)
                let refreshResponse = RefreshResponse(accessToken: "new_token", expiresIn: 900)
                let data = try! TestFixtures.makeJSONData(refreshResponse)
                return (response, data)
            }

            // 第一次返回 401，刷新后返回成功
            if !refreshCalled {
                let response = TestFixtures.makeHTTPResponse(statusCode: 401)
                return (response, nil)
            }

            struct SuccessResponse: Codable { let success: Bool }
            let response = TestFixtures.makeHTTPResponse(statusCode: 200)
            let data = try! TestFixtures.makeJSONData(SuccessResponse(success: true))
            return (response, data)
        }

        // When
        let endpoint = APIEndpoint(path: "/test", method: .get)
        struct SuccessResponse: Codable { let success: Bool }
        let result: SuccessResponse = try await interceptor.executeWithRetry(endpoint)

        // Then: 应该成功（经过 Token 刷新）
        XCTAssertTrue(result.success)
        XCTAssertTrue(refreshCalled, "Should trigger token refresh on 401")
    }

    /// 测试：Token 刷新失败应该清除认证
    func testTokenRefreshFailure_ShouldClearAuth() async throws {
        // Given
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/auth/refresh" {
                // Refresh 失败
                let response = TestFixtures.makeHTTPResponse(statusCode: 401)
                return (response, nil)
            }

            // 原始请求返回 401
            let response = TestFixtures.makeHTTPResponse(statusCode: 401)
            return (response, nil)
        }

        // When
        do {
            let endpoint = APIEndpoint(path: "/test", method: .get)
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await interceptor.executeWithRetry(endpoint)
            XCTFail("Should throw error")
        } catch {
            // Expected
        }

        // Then: 认证应该被清除
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
    }

    // MARK: - Error Metadata Tests

    /// 测试：错误应该包含描述信息
    func testAPIError_ShouldHaveDescription() {
        // Test all error cases
        XCTAssertNotNil(APIError.unauthorized.errorDescription)
        XCTAssertNotNil(APIError.notFound.errorDescription)
        XCTAssertNotNil(APIError.serverError.errorDescription)
        XCTAssertNotNil(APIError.timeout.errorDescription)
        XCTAssertNotNil(APIError.noConnection.errorDescription)

        // 验证描述不为空
        XCTAssertFalse(APIError.unauthorized.errorDescription?.isEmpty ?? true)
    }

    /// 测试：错误重试策略
    func testAPIError_RetryPolicy() {
        // 应该重试的错误
        XCTAssertTrue(APIError.timeout.shouldRetry)
        XCTAssertTrue(APIError.noConnection.shouldRetry)
        XCTAssertTrue(APIError.serverError.shouldRetry)
        XCTAssertTrue(APIError.serviceUnavailable.shouldRetry)

        // 不应该重试的错误
        XCTAssertFalse(APIError.unauthorized.shouldRetry)
        XCTAssertFalse(APIError.notFound.shouldRetry)
        XCTAssertFalse(APIError.badRequest.shouldRetry)
        XCTAssertFalse(APIError.forbidden.shouldRetry)
    }
}
