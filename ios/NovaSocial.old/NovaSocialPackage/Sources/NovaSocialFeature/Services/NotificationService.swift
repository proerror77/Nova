import Foundation

/// Response structure for notifications API
private struct NotificationResponse: Decodable {
    let notifications: [Notification]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case notifications
        case hasMore = "has_more"
    }
}

/// Service for managing notifications
final class NotificationService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager
    private let useMockData: Bool

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        cache: CacheManager = CacheManager(),
        useMockData: Bool = false
    ) {
        self.httpClient = httpClient
        self.cache = cache
        self.useMockData = useMockData
    }

    /// Fetches notifications for a given page
    func getNotifications(page: Int = 0, limit: Int = 20) async throws -> [Notification] {
        let cacheKey = "notifications_page_\(page)"

        // Check cache first
        if let cached: [Notification] = cache.get(for: cacheKey) {
            return cached
        }

        // Use mock data if explicitly set, or return mock data as fallback
        if useMockData {
            let mockNotifications = mockNotificationData()
            cache.set(mockNotifications, for: cacheKey)
            return mockNotifications
        }

        // Fetch from real API
        do {
            let response: NotificationResponse = try await httpClient.request(
                endpoint: .notifications(page: page, limit: limit)
            )
            cache.set(response.notifications, for: cacheKey)
            return response.notifications
        } catch {
            // Fallback to mock data if API fails
            let mockNotifications = mockNotificationData()
            cache.set(mockNotifications, for: cacheKey)
            return mockNotifications
        }
    }

    /// Returns mock notification data for testing and fallback
    private func mockNotificationData() -> [Notification] {
        [
            Notification(
                id: "notif_1",
                userId: "current_user",
                actionType: "like",
                targetId: "post_1",
                timestamp: "2025-10-19T10:00:00Z",
                actor: User(id: "user_1", username: "john_doe", displayName: "John Doe", avatarUrl: nil, bio: nil, followersCount: 42, followingCount: 100, postsCount: 15)
            ),
            Notification(
                id: "notif_2",
                userId: "current_user",
                actionType: "like",
                targetId: "post_2",
                timestamp: "2025-10-19T09:30:00Z",
                actor: User(id: "user_2", username: "jane_smith", displayName: "Jane Smith", avatarUrl: nil, bio: nil, followersCount: 156, followingCount: 89, postsCount: 32)
            ),
            Notification(
                id: "notif_3",
                userId: "current_user",
                actionType: "like",
                targetId: "post_3",
                timestamp: "2025-10-19T09:00:00Z",
                actor: User(id: "user_3", username: "mike_wilson", displayName: "Mike Wilson", avatarUrl: nil, bio: nil, followersCount: 203, followingCount: 150, postsCount: 47)
            ),
            Notification(
                id: "notif_4",
                userId: "current_user",
                actionType: "like",
                targetId: "post_4",
                timestamp: "2025-10-19T08:30:00Z",
                actor: User(id: "user_4", username: "sarah_jones", displayName: "Sarah Jones", avatarUrl: nil, bio: nil, followersCount: 89, followingCount: 56, postsCount: 21)
            ),
            Notification(
                id: "notif_5",
                userId: "current_user",
                actionType: "like",
                targetId: "post_5",
                timestamp: "2025-10-19T08:00:00Z",
                actor: User(id: "user_5", username: "alex_brown", displayName: "Alex Brown", avatarUrl: nil, bio: nil, followersCount: 312, followingCount: 201, postsCount: 64)
            ),
            Notification(
                id: "notif_6",
                userId: "current_user",
                actionType: "like",
                targetId: "post_6",
                timestamp: "2025-10-19T07:30:00Z",
                actor: User(id: "user_6", username: "emma_davis", displayName: "Emma Davis", avatarUrl: nil, bio: nil, followersCount: 145, followingCount: 98, postsCount: 38)
            )
        ]
    }
}
