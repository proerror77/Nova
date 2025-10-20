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
        let request = RegisterRequest(email: email, password: password, username: username)

        let endpoint = APIEndpoint(
            path: "/api/v1/auth/register",
            method: .post,
            body: request
        )

        // 优先尝试解码后端返回的 { user, tokens } 结构
        if let response: AuthResponse = try? await interceptor.executeWithRetry(
            endpoint,
            authenticated: false
        ) {
            AuthManager.shared.saveAuth(user: response.user, tokens: response.tokens)
            return (response.user, response.tokens)
        }

        // 兼容后端仅返回注册确认信息的场景：注册成功后直接尝试登录获取 token
        struct RegisterOnlyResponse: Codable { let id: String; let email: String; let username: String; let message: String }
        _ = try await interceptor.executeWithRetry(
            endpoint,
            authenticated: false
        ) as RegisterOnlyResponse

        // 直接登录以获取 token（注意：生产环境可能要求邮箱先验证）
        return try await login(email: email, password: password)
    }

    /// 用户登录
    func login(email: String, password: String) async throws -> (User, AuthTokens) {
        let request = LoginRequest(
            email: email,
            password: password
        )

        let endpoint = APIEndpoint(
            path: "/api/v1/auth/login",
            method: .post,
            body: request
        )

        // 尝试解码 { user, tokens } 结构
        if let response: AuthResponse = try? await interceptor.executeWithRetry(
            endpoint,
            authenticated: false
        ) {
            AuthManager.shared.saveAuth(user: response.user, tokens: response.tokens)
            return (response.user, response.tokens)
        }

        // 兼容仅返回 token 的场景（后端不返回用户对象）
        struct TokenOnlyResponse: Codable {
            let access_token: String
            let refresh_token: String
            let token_type: String
            let expires_in: Int
        }

        let tokensOnly: TokenOnlyResponse = try await interceptor.executeWithRetry(
            endpoint,
            authenticated: false
        )

        // 从 access_token 的 JWT 解析用户基本信息
        let tokens = AuthTokens(
            accessToken: tokensOnly.access_token,
            refreshToken: tokensOnly.refresh_token,
            expiresIn: tokensOnly.expires_in,
            tokenType: tokensOnly.token_type
        )

        let userFromJWT = try decodeUserFromJWT(tokens.accessToken)
        AuthManager.shared.saveAuth(user: userFromJWT, tokens: tokens)
        return (userFromJWT, tokens)
    }

    /// 用户登出
    func logout() async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/auth/logout",
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
            path: "/api/v1/auth/verify-email",
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

// MARK: - JWT 解码辅助

private func decodeUserFromJWT(_ jwt: String) throws -> User {
    enum DecodeError: Error { case invalidFormat, invalidBase64, invalidJSON, invalidID }
    let parts = jwt.split(separator: ".")
    guard parts.count >= 2 else { throw DecodeError.invalidFormat }

    // Base64URL 解码 payload（第二部分）
    var payload = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    // 补齐 padding
    while payload.count % 4 != 0 { payload.append("=") }

    guard let data = Data(base64Encoded: payload) else { throw DecodeError.invalidBase64 }

    struct Claims: Codable { let sub: String; let email: String; let username: String }
    guard let claims = try? JSONDecoder().decode(Claims.self, from: data) else {
        throw DecodeError.invalidJSON
    }

    guard let id = UUID(uuidString: claims.sub) else { throw DecodeError.invalidID }

    // 组装最小可用用户对象（其余字段使用默认值）
    return User(
        id: id,
        username: claims.username,
        email: claims.email,
        displayName: nil,
        bio: nil,
        avatarUrl: nil,
        isVerified: true,
        createdAt: Date()
    )
}
