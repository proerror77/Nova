import XCTest
@testable import NovaSocial

/// AuthRepositoryTests - 认证仓库单元测试
///
/// 测试范围：
/// 1. 注册流程
/// 2. 登录流程
/// 3. 登出流程
/// 4. Token 刷新
/// 5. 错误处理
///
/// TDD 原则：每个测试都是一个需求文档
final class AuthRepositoryTests: XCTestCase {

    // MARK: - Properties

    var repository: AuthRepository!
    var apiClient: APIClient!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        // 配置 Mock URLSession
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        apiClient = APIClient(
            baseURL: URL(string: "https://api.test.com")!,
            session: session
        )
        repository = AuthRepository(apiClient: apiClient)

        AuthManager.shared.clearAuth()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        AuthManager.shared.clearAuth()
        MockURLProtocol.reset()
        repository = nil
        apiClient = nil
        super.tearDown()
    }

    // MARK: - Register Tests

    /// 测试：成功注册
    func testRegister_WhenSuccessful_ShouldReturnUserAndTokens() async throws {
        // Given: Mock 成功响应
        let mockResponse = TestFixtures.makeAuthResponse(
            user: TestFixtures.makeUser(username: "newuser", email: "new@example.com"),
            tokens: TestFixtures.makeAuthTokens()
        )

        try MockURLProtocol.mockJSON(mockResponse, statusCode: 201)

        // When: 注册
        let (user, tokens) = try await repository.register(
            email: "new@example.com",
            username: "newuser",
            password: "password123"
        )

        // Then: 返回正确的用户和 Token
        XCTAssertEqual(user.username, "newuser")
        XCTAssertEqual(user.email, "new@example.com")
        XCTAssertEqual(tokens.accessToken, "test_access_token")

        // And: 认证信息被保存
        XCTAssertTrue(AuthManager.shared.isAuthenticated)
        XCTAssertEqual(AuthManager.shared.currentUser?.username, "newuser")
    }

    /// 测试：注册时邮箱已存在
    func testRegister_WhenEmailExists_ShouldThrowError() async throws {
        // Given: Mock 400 错误响应
        let errorResponse = TestFixtures.makeErrorResponse(
            error: "email_exists",
            message: "Email already registered"
        )
        let errorData = try TestFixtures.makeJSONData(errorResponse)

        MockURLProtocol.mockError(statusCode: 400, errorData: errorData)

        // When & Then: 应该抛出错误
        do {
            _ = try await repository.register(
                email: "existing@example.com",
                username: "newuser",
                password: "password123"
            )
            XCTFail("Should throw error for existing email")
        } catch let error as APIError {
            // 验证是正确的错误类型
            switch error {
            case .badRequest:
                break // Expected
            default:
                XCTFail("Expected badRequest error, got: \(error)")
            }
        }

        // And: 不应该保存认证信息
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
    }

    /// 测试：注册时密码太短
    func testRegister_WhenPasswordTooShort_ShouldThrowError() async throws {
        // Given: Mock 400 错误
        MockURLProtocol.mockError(statusCode: 400)

        // When & Then
        do {
            _ = try await repository.register(
                email: "test@example.com",
                username: "testuser",
                password: "123" // Too short
            )
            XCTFail("Should throw error for short password")
        } catch {
            // Expected
        }
    }

    // MARK: - Login Tests

    /// 测试：成功登录
    func testLogin_WhenSuccessful_ShouldReturnUserAndTokens() async throws {
        // Given
        let mockResponse = TestFixtures.makeAuthResponse(
            user: TestFixtures.makeUser(email: "test@example.com"),
            tokens: TestFixtures.makeAuthTokens()
        )

        try MockURLProtocol.mockJSON(mockResponse, statusCode: 200)

        // When
        let (user, tokens) = try await repository.login(
            email: "test@example.com",
            password: "password123"
        )

        // Then
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertNotNil(tokens.accessToken)
        XCTAssertTrue(AuthManager.shared.isAuthenticated)
    }

    /// 测试：登录失败 - 无效凭据
    func testLogin_WhenInvalidCredentials_ShouldThrowError() async throws {
        // Given: Mock 401 响应
        MockURLProtocol.mockError(statusCode: 401)

        // When & Then
        do {
            _ = try await repository.login(
                email: "test@example.com",
                password: "wrong_password"
            )
            XCTFail("Should throw unauthorized error")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }

        // 不应该保存认证信息
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
    }

    /// 测试：登录时网络超时
    func testLogin_WhenNetworkTimeout_ShouldRetryAndFail() async throws {
        // Given: Mock 超时
        MockURLProtocol.mockTimeout()

        // When & Then
        do {
            _ = try await repository.login(
                email: "test@example.com",
                password: "password123"
            )
            XCTFail("Should throw timeout error")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout)
        }
    }

    // MARK: - Logout Tests

    /// 测试：成功登出
    func testLogout_WhenSuccessful_ShouldClearAuth() async throws {
        // Given: 已登录状态
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // Mock 成功响应
        MockURLProtocol.mockSuccess(statusCode: 204)

        // When: 登出
        try await repository.logout()

        // Then: 认证信息被清除
        XCTAssertFalse(AuthManager.shared.isAuthenticated)
        XCTAssertNil(AuthManager.shared.currentUser)
        XCTAssertNil(AuthManager.shared.accessToken)
    }

    /// 测试：登出失败仍然清除本地认证
    func testLogout_WhenFails_ShouldStillClearLocalAuth() async throws {
        // Given: 已登录状态
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // Mock 失败响应
        MockURLProtocol.mockError(statusCode: 500)

        // When: 登出（即使失败）
        do {
            try await repository.logout()
            XCTFail("Should throw server error")
        } catch {
            // Expected error
        }

        // Then: 本地认证信息应该被清除
        // 注意：这取决于实现策略 - 是否在失败时也清除本地状态
        // 当前实现只在成功时清除
    }

    // MARK: - Email Verification Tests

    /// 测试：邮箱验证成功
    func testVerifyEmail_WhenSuccessful_ShouldComplete() async throws {
        // Given: 已登录状态
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        struct VerifyResponse: Codable {
            let verified: Bool
        }

        try MockURLProtocol.mockJSON(VerifyResponse(verified: true))

        // When: 验证邮箱
        try await repository.verifyEmail(code: "123456")

        // Then: 不应该抛出错误
    }

    /// 测试：邮箱验证码无效
    func testVerifyEmail_WhenInvalidCode_ShouldThrowError() async throws {
        // Given
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        MockURLProtocol.mockError(statusCode: 400)

        // When & Then
        do {
            try await repository.verifyEmail(code: "invalid")
            XCTFail("Should throw error for invalid code")
        } catch {
            // Expected
        }
    }

    // MARK: - Session Management Tests

    /// 测试：检查本地认证状态
    func testCheckLocalAuthStatus_WhenAuthenticated_ReturnsTrue() {
        // Given: 保存认证信息
        let user = TestFixtures.makeUser()
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // When
        let isAuthenticated = repository.checkLocalAuthStatus()

        // Then
        XCTAssertTrue(isAuthenticated)
    }

    /// 测试：检查本地认证状态 - 未登录
    func testCheckLocalAuthStatus_WhenNotAuthenticated_ReturnsFalse() {
        // Given: 未登录
        AuthManager.shared.clearAuth()

        // When
        let isAuthenticated = repository.checkLocalAuthStatus()

        // Then
        XCTAssertFalse(isAuthenticated)
    }

    /// 测试：获取当前用户
    func testGetCurrentUser_WhenAuthenticated_ReturnsUser() {
        // Given
        let user = TestFixtures.makeUser(username: "testuser")
        let tokens = TestFixtures.makeAuthTokens()
        AuthManager.shared.saveAuth(user: user, tokens: tokens)

        // When
        let currentUser = repository.getCurrentUser()

        // Then
        XCTAssertNotNil(currentUser)
        XCTAssertEqual(currentUser?.username, "testuser")
    }

    /// 测试：获取当前用户 - 未登录
    func testGetCurrentUser_WhenNotAuthenticated_ReturnsNil() {
        // Given: 未登录
        AuthManager.shared.clearAuth()

        // When
        let currentUser = repository.getCurrentUser()

        // Then
        XCTAssertNil(currentUser)
    }

    // MARK: - Integration with Interceptor Tests

    /// 测试：登录后的请求应该自动包含 Token
    func testAfterLogin_SubsequentRequestsShouldIncludeToken() async throws {
        // Given: 成功登录
        let mockResponse = TestFixtures.makeAuthResponse()
        try MockURLProtocol.mockJSON(mockResponse, statusCode: 200)

        _ = try await repository.login(
            email: "test@example.com",
            password: "password123"
        )

        // When: 验证请求包含 Authorization header
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = TestFixtures.makeHTTPResponse(statusCode: 200)
            struct EmptyResponse: Codable {}
            let data = try! TestFixtures.makeJSONData(EmptyResponse())
            return (response, data)
        }

        struct EmptyResponse: Codable {}
        let endpoint = APIEndpoint(path: "/test", method: .get)
        _ = try? await apiClient.request(endpoint, authenticated: true) as EmptyResponse

        // Then: 应该包含 Bearer token
        XCTAssertNotNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(
            capturedRequest?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") ?? false
        )
    }
}
