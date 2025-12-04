import Foundation

/// AuthRepository - 认证业务逻辑层
/// 职责：处理登录、注册、登出等认证相关业务
final class AuthRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
    }

    // MARK: - Public API

    /// 用户注册
    func register(email: String, username: String, password: String) async throws -> (User, AuthTokens) {
        let request = RegisterRequest(
            email: email,
            password: password,
            username: username
        )

        let endpoint = APIEndpoint(
            path: "/auth/register",
            method: .post,
            body: request
        )

        let response: AuthResponse = try await interceptor.executeWithRetry(
            endpoint,
            authenticated: false
        )

        // 保存认证信息
        AuthManager.shared.saveAuth(user: response.user, tokens: response.tokens)

        return (response.user, response.tokens)
    }

    /// 用户登录
    func login(email: String, password: String) async throws -> (User, AuthTokens) {
        let request = LoginRequest(
            email: email,
            password: password
        )

        let endpoint = APIEndpoint(
            path: "/auth/login",
            method: .post,
            body: request
        )

        let response: AuthResponse = try await interceptor.executeWithRetry(
            endpoint,
            authenticated: false
        )

        // 保存认证信息
        AuthManager.shared.saveAuth(user: response.user, tokens: response.tokens)

        return (response.user, response.tokens)
    }

    /// 用户登出
    func logout() async throws {
        let endpoint = APIEndpoint(
            path: "/auth/logout",
            method: .post
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)

        // 清空本地认证信息
        AuthManager.shared.clearAuth()
    }

    /// 验证邮箱
    func verifyEmail(code: String) async throws {
        struct VerifyRequest: Codable {
            let code: String
        }

        let endpoint = APIEndpoint(
            path: "/auth/verify-email",
            method: .post,
            body: VerifyRequest(code: code)
        )

        struct VerifyResponse: Codable {
            let verified: Bool
        }

        let _: VerifyResponse = try await interceptor.executeWithRetry(endpoint)
    }

    /// 检查本地登录状态
    func checkLocalAuthStatus() -> Bool {
        return AuthManager.shared.restoreSession()
    }

    /// 获取当前用户
    func getCurrentUser() -> User? {
        return AuthManager.shared.currentUser
    }
}
