import Foundation

/// NotificationRepository - 通知业务逻辑层
/// 职责：处理通知获取、标记已读等操作
final class NotificationRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
    }

    // MARK: - Public API

    /// 获取通知列表
    func getNotifications(cursor: String? = nil, limit: Int = 20) async throws -> (notifications: [Notification], unreadCount: Int) {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let endpoint = APIEndpoint(
            path: "/notifications",
            method: .get,
            queryItems: queryItems
        )

        let response: NotificationResponse = try await interceptor.executeWithRetry(endpoint)
        return (response.notifications, response.unreadCount)
    }

    /// 标记单条通知为已读
    func markAsRead(id: UUID) async throws {
        let endpoint = APIEndpoint(
            path: "/notifications/\(id.uuidString)/read",
            method: .put
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)
    }

    /// 标记所有通知为已读
    func markAllAsRead() async throws {
        let endpoint = APIEndpoint(
            path: "/notifications/read-all",
            method: .put
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)
    }
}
