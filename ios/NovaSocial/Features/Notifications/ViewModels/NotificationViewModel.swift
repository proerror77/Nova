import Foundation
import SwiftUI

// MARK: - Notification ViewModel

@MainActor
@Observable
final class NotificationViewModel {
    // MARK: - Observable Properties

    var notifications: [NotificationItem] = [] {
        didSet {
            // Invalidate cached groups when notifications change
            invalidateGroupedCache()
        }
    }
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var hasMore = true
    var unreadCount = 0

    // MARK: - Cached Grouped Notifications

    private var _cachedTodayNotifications: [NotificationItem]?
    private var _cachedLastSevenDaysNotifications: [NotificationItem]?
    private var _cachedLastThirtyDaysNotifications: [NotificationItem]?
    private var _cachedOlderNotifications: [NotificationItem]?

    var todayNotifications: [NotificationItem] {
        if let cached = _cachedTodayNotifications { return cached }
        let filtered = notifications.filter { isToday($0.timestamp) }
        let result = groupNotifications(filtered)
        _cachedTodayNotifications = result
        return result
    }

    var lastSevenDaysNotifications: [NotificationItem] {
        if let cached = _cachedLastSevenDaysNotifications { return cached }
        let filtered = notifications.filter { isLastSevenDays($0.timestamp) && !isToday($0.timestamp) }
        let result = groupNotifications(filtered)
        _cachedLastSevenDaysNotifications = result
        return result
    }

    var lastThirtyDaysNotifications: [NotificationItem] {
        if let cached = _cachedLastThirtyDaysNotifications { return cached }
        let filtered = notifications.filter { isLastThirtyDays($0.timestamp) && !isLastSevenDays($0.timestamp) && !isToday($0.timestamp) }
        let result = groupNotifications(filtered)
        _cachedLastThirtyDaysNotifications = result
        return result
    }

    var olderNotifications: [NotificationItem] {
        if let cached = _cachedOlderNotifications { return cached }
        let filtered = notifications.filter { !isLastThirtyDays($0.timestamp) }
        let result = groupNotifications(filtered)
        _cachedOlderNotifications = result
        return result
    }

    /// Group notifications by user and type for better display
    /// Returns grouped notifications where multiple actions from same user are combined
    func groupNotifications(_ notifications: [NotificationItem]) -> [NotificationItem] {
        var grouped: [String: [NotificationItem]] = [:]
        
        // Group by user ID + notification type
        for notification in notifications {
            guard let userId = notification.relatedUserId else {
                // Keep notifications without user ID as-is
                continue
            }
            
            let key = "\(userId)_\(notification.type.rawValue)"
            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(notification)
        }
        
        var result: [NotificationItem] = []
        
        // Process grouped notifications
        for (_, group) in grouped {
            if group.count > 1 {
                // Multiple notifications from same user - keep only the most recent
                if let mostRecent = group.max(by: { $0.timestamp < $1.timestamp }) {
                    result.append(mostRecent)
                }
            } else if let single = group.first {
                result.append(single)
            }
        }
        
        // Add notifications without user ID
        result.append(contentsOf: notifications.filter { $0.relatedUserId == nil })
        
        // Sort by timestamp (most recent first)
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    private func invalidateGroupedCache() {
        _cachedTodayNotifications = nil
        _cachedLastSevenDaysNotifications = nil
        _cachedLastThirtyDaysNotifications = nil
        _cachedOlderNotifications = nil
    }

    // MARK: - Private Properties

    private let notificationService: NotificationService
    private let graphService: GraphService
    private var currentOffset = 0
    private let pageSize = 20
    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }

    // MARK: - Initialization

    init(
        notificationService: NotificationService = NotificationService(),
        graphService: GraphService = GraphService()
    ) {
        self.notificationService = notificationService
        self.graphService = graphService
    }

    // MARK: - Public Methods

    /// Load initial notifications
    func loadNotifications() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentOffset = 0

        do {
            let response = try await notificationService.getNotifications(limit: pageSize, offset: 0)
            self.notifications = response.notifications.map { $0.toNotificationItem() }
            self.hasMore = response.hasMore
            self.unreadCount = response.unreadCount
            self.currentOffset = response.notifications.count
            self.error = nil
        } catch {
            self.error = "Failed to load notifications: \(error.localizedDescription)"
            print("NotificationViewModel: Failed to load notifications - \(error)")
        }

        isLoading = false
    }

    /// Load more notifications (pagination)
    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }

        isLoadingMore = true

        do {
            let response = try await notificationService.getNotifications(limit: pageSize, offset: currentOffset)
            let newNotifications = response.notifications.map { $0.toNotificationItem() }

            // Deduplicate by ID
            let existingIds = Set(notifications.map { $0.id })
            let uniqueNew = newNotifications.filter { !existingIds.contains($0.id) }

            self.notifications.append(contentsOf: uniqueNew)
            self.hasMore = response.hasMore
            self.currentOffset += response.notifications.count
        } catch {
            print("NotificationViewModel: Failed to load more notifications - \(error)")
        }

        isLoadingMore = false
    }

    /// Refresh notifications (pull to refresh)
    func refresh() async {
        currentOffset = 0
        isLoading = true
        error = nil

        do {
            let response = try await notificationService.getNotifications(limit: pageSize, offset: 0)
            self.notifications = response.notifications.map { $0.toNotificationItem() }
            self.hasMore = response.hasMore
            self.unreadCount = response.unreadCount
            self.currentOffset = response.notifications.count
            self.error = nil
        } catch {
            self.error = "Failed to refresh notifications"
            print("NotificationViewModel: Failed to refresh - \(error)")
        }

        isLoading = false
    }

    /// Mark a notification as read
    func markAsRead(notificationId: String) async {
        // Optimistic local update first
        if let index = notifications.firstIndex(where: { $0.id == notificationId }),
           !notifications[index].isRead {
            // Create updated notification with isRead = true
            let old = notifications[index]
            var updatedNotification = NotificationItem(
                id: old.id,
                type: old.type,
                message: old.message,
                timestamp: old.timestamp,
                isRead: true,
                relatedUserId: old.relatedUserId,
                relatedPostId: old.relatedPostId,
                relatedCommentId: old.relatedCommentId
            )
            updatedNotification.userAvatarUrl = old.userAvatarUrl
            updatedNotification.userName = old.userName
            updatedNotification.postThumbnailUrl = old.postThumbnailUrl
            notifications[index] = updatedNotification

            // Decrement unread count
            if unreadCount > 0 {
                unreadCount -= 1
            }
        }

        // Send to server (fire and forget - don't block UI)
        do {
            try await notificationService.markAsRead(notificationId: notificationId)
        } catch {
            print("NotificationViewModel: Failed to mark as read on server - \(error)")
            // Note: We keep local state updated even if server call fails
            // The next refresh will sync the correct state
        }
    }

    /// Mark all notifications as read
    func markAllAsRead() async {
        do {
            try await notificationService.markAllAsRead()
            self.unreadCount = 0
            await refresh()
        } catch {
            print("NotificationViewModel: Failed to mark all as read - \(error)")
        }
    }

    /// Follow a user from notification
    func followUser(userId: String) async -> Bool {
        guard let currentUserId = currentUserId else {
            print("NotificationViewModel: No current user ID")
            return false
        }
        do {
            try await graphService.followUser(followerId: currentUserId, followeeId: userId)
            return true
        } catch {
            print("NotificationViewModel: Failed to follow user - \(error)")
            return false
        }
    }

    /// Unfollow a user
    func unfollowUser(userId: String) async -> Bool {
        guard let currentUserId = currentUserId else {
            print("NotificationViewModel: No current user ID")
            return false
        }
        do {
            try await graphService.unfollowUser(followerId: currentUserId, followeeId: userId)
            return true
        } catch {
            print("NotificationViewModel: Failed to unfollow user - \(error)")
            return false
        }
    }

    // MARK: - Private Helper Methods

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isLastSevenDays(_ date: Date) -> Bool {
        guard let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            return false
        }
        return date >= sevenDaysAgo
    }

    private func isLastThirtyDays(_ date: Date) -> Bool {
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return false
        }
        return date >= thirtyDaysAgo
    }
}

// MARK: - Notification Display Helpers

extension NotificationItem {
    /// Generate action text based on notification type
    var actionText: String {
        switch type {
        case .like:
            return "liked your post."
        case .comment:
            return "commented on your post."
        case .follow:
            return "started following you."
        case .mention:
            return "mentioned you in a post."
        case .share:
            return "shared your post."
        case .reply:
            return "replied to your comment."
        case .system:
            return message
        case .friendRequest:
            return "sent you a friend request."
        case .friendAccepted:
            return "accepted your friend request."
        }
    }

    /// Generate relative time string
    var relativeTimeString: String {
        let now = Date()
        let interval = now.timeIntervalSince(timestamp)

        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        let weeks = Int(interval / 604800)

        if minutes < 1 {
            return "now"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else if hours < 24 {
            return "\(hours)h"
        } else if days < 7 {
            return "\(days)d"
        } else {
            return "\(weeks)w"
        }
    }

    /// Determine button type for UI
    var buttonType: NotificationButtonType {
        switch type {
        case .follow:
            return .followBack
        case .like, .comment, .mention, .share, .reply:
            return .follow
        case .system:
            return .none
        case .friendRequest:
            return .followBack  // Show accept button
        case .friendAccepted:
            return .message  // Show message button
        }
    }
}

// MARK: - Button Type Enum (moved from View for reuse)

enum NotificationButtonType {
    case message
    case follow
    case followBack
    case none
}
