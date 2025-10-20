import Foundation

/// RequestInterceptor - 请求拦截器
/// 职责：自动处理 Token 刷新、重试逻辑
///
/// Linus 改进:
/// 1. 使用 actor 替代 NSLock - 简单且正确
/// 2. 消除重复的重试逻辑
/// 3. 移除不必要的超时机制(网络层已有超时)
///
/// "双重检查锁定"是 Java 时代的垃圾,Swift 有 actor
actor RequestInterceptor {
    private let apiClient: APIClient
    private var activeRefreshTask: Task<Void, Error>?

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// 执行带自动重试的请求
    func executeWithRetry<T: Decodable>(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true,
        maxRetries: Int = 3
    ) async throws -> T {
        return try await executeRequest(authenticated: authenticated, maxRetries: maxRetries) {
            try await self.apiClient.request(endpoint, authenticated: authenticated)
        }
    }

    /// 执行无响应的请求（DELETE、logout 等）
    func executeNoResponseWithRetry(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true,
        maxRetries: Int = 3
    ) async throws {
        try await executeRequest(authenticated: authenticated, maxRetries: maxRetries) {
            try await self.apiClient.requestNoResponse(endpoint, authenticated: authenticated)
            return () // 返回空元组
        }
    }

    // MARK: - Core Logic (消除重复)

    /// 核心请求执行逻辑
    ///
    /// Linus: "两个方法做同样的事是垃圾代码,提取公共逻辑"
    private func executeRequest<T>(
        authenticated: Bool,
        maxRetries: Int,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: APIError?

        for attempt in 0..<maxRetries {
            do {
                // 检查是否需要刷新 Token
                if authenticated && AuthManager.shared.isTokenExpired {
                    try await refreshTokenIfNeeded()
                }

                // 发送请求
                return try await operation()

            } catch let error as APIError {
                lastError = error

                // 处理 401 - 刷新 Token 并重试
                if error.requiresReauthentication && attempt < maxRetries - 1 {
                    Logger.log("⚠️ Got 401, attempting token refresh", level: .warning)

                    do {
                        try await refreshTokenIfNeeded()
                        continue
                    } catch {
                        AuthManager.shared.clearAuth()
                        throw APIError.unauthorized
                    }
                }

                // 处理可重试错误
                if error.shouldRetry && attempt < maxRetries - 1 {
                    let delay = calculateBackoff(attempt: attempt)
                    Logger.log("⚠️ Retry attempt \(attempt + 1) after \(delay)s", level: .warning)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                throw error
            }
        }

        throw lastError ?? APIError.unknown("Request failed after \(maxRetries) attempts")
    }

    // MARK: - Token Refresh

    /// 刷新 Token (线程安全,自动去重)
    ///
    /// Linus: "Actor 保证了线程安全,Task 保证了去重,无需任何锁"
    private func refreshTokenIfNeeded() async throws {
        // 如果已有刷新任务,复用它
        if let existingTask = activeRefreshTask {
            Logger.log("⏳ Reusing existing refresh task", level: .debug)
            try await existingTask.value
            return
        }

        // 创建新的刷新任务
        let task = Task<Void, Error> {
            defer {
                // 清理任务引用
                Task { await self.clearRefreshTask() }
            }

            try await self.performTokenRefresh()
        }

        activeRefreshTask = task

        // 等待刷新完成
        try await task.value
    }

    /// 执行实际的 Token 刷新
    private func performTokenRefresh() async throws {
        guard let refreshToken = AuthManager.shared.refreshToken else {
            throw APIError.unauthorized
        }

        Logger.log("🔄 Refreshing access token...", level: .info)

        let endpoint = APIEndpoint(
            path: "/api/v1/auth/refresh",
            method: .post,
            body: ["refresh_token": refreshToken]
        )

        let response: RefreshTokenResponse = try await apiClient.request(endpoint, authenticated: false)
        AuthManager.shared.updateAccessToken(response.accessToken, expiresIn: response.expiresIn)

        Logger.log("✅ Access token refreshed", level: .info)
    }

    /// 清除刷新任务
    private func clearRefreshTask() {
        activeRefreshTask = nil
    }

    // MARK: - Retry Policy

    /// 计算指数退避延迟
    private func calculateBackoff(attempt: Int) -> TimeInterval {
        // 指数退避：2^attempt 秒，最多 8 秒
        let delay = min(pow(2.0, Double(attempt)), 8.0)

        // 添加随机抖动 (0-1 秒)，避免"惊群效应"
        let jitter = Double.random(in: 0...1)

        return delay + jitter
    }
}
