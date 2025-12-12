import Foundation
import SwiftUI

// MARK: - Notification ViewModel

@MainActor
class NotificationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var notifications: [NotificationItem] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasMore = true
    @Published var unreadCount = 0

    // MARK: - Grouped Notifications

    var todayNotifications: [NotificationItem] {
        notifications.filter { isToday($0.timestamp) }
    }

    var lastSevenDaysNotifications: [NotificationItem] {
        notifications.filter { isLastSevenDays($0.timestamp) && !isToday($0.timestamp) }
    }

    var lastThirtyDaysNotifications: [NotificationItem] {
        notifications.filter { isLastThirtyDays($0.timestamp) && !isLastSevenDays($0.timestamp) && !isToday($0.timestamp) }
    }

    var olderNotifications: [NotificationItem] {
        notifications.filter { !isLastThirtyDays($0.timestamp) }
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
        do {
            try await notificationService.markAsRead(notificationId: notificationId)
            // Update local state
            if notifications.firstIndex(where: { $0.id == notificationId }) != nil {
                // NotificationItem is a struct with let isRead, so we refresh the list
                await refresh()
            }
        } catch {
            print("NotificationViewModel: Failed to mark as read - \(error)")
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
