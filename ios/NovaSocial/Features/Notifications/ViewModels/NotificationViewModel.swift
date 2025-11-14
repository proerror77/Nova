import Foundation
import SwiftUI

// MARK: - Notification View Model

@MainActor
class NotificationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var notifications: [NotificationItem] = []
    @Published var selectedFilter: NotificationFilter = .all
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Services

    private let communicationService = CommunicationService()

    // MARK: - Computed Properties

    var filteredNotifications: [NotificationItem] {
        switch selectedFilter {
        case .all:
            return notifications
        case .unread:
            return notifications.filter { !$0.isRead }
        case .mentions:
            return notifications.filter { $0.type == .mention }
        case .likes:
            return notifications.filter { $0.type == .like }
        case .comments:
            return notifications.filter { $0.type == .comment }
        }
    }

    // MARK: - Lifecycle

    func loadNotifications() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await communicationService.getNotifications(
                unreadOnly: selectedFilter == .unread,
                limit: 50,
                offset: 0
            )
            notifications = response.notifications
            unreadCount = response.unreadCount
        } catch {
            errorMessage = "Failed to load notifications: \(error.localizedDescription)"
            notifications = []
            unreadCount = 0
        }

        isLoading = false
    }

    // MARK: - Actions

    func markAsRead(_ notificationId: String) async {
        // Optimistic update: mark as read immediately in UI
        guard let index = notifications.firstIndex(where: { $0.id == notificationId }) else { return }

        let wasUnread = !notifications[index].isRead
        var updated = notifications[index]
        updated = NotificationItem(
            id: updated.id,
            type: updated.type,
            message: updated.message,
            timestamp: updated.timestamp,
            isRead: true,
            relatedUserId: updated.relatedUserId,
            relatedPostId: updated.relatedPostId,
            relatedCommentId: updated.relatedCommentId,
            userAvatarUrl: updated.userAvatarUrl,
            userName: updated.userName,
            postThumbnailUrl: updated.postThumbnailUrl
        )
        notifications[index] = updated

        if wasUnread {
            unreadCount = max(0, unreadCount - 1)
        }

        // Send API request
        do {
            try await communicationService.markNotificationRead(id: notificationId)
        } catch {
            // Revert on error
            notifications[index] = NotificationItem(
                id: updated.id,
                type: updated.type,
                message: updated.message,
                timestamp: updated.timestamp,
                isRead: false,
                relatedUserId: updated.relatedUserId,
                relatedPostId: updated.relatedPostId,
                relatedCommentId: updated.relatedCommentId,
                userAvatarUrl: updated.userAvatarUrl,
                userName: updated.userName,
                postThumbnailUrl: updated.postThumbnailUrl
            )
            if wasUnread {
                unreadCount += 1
            }
            errorMessage = "Failed to mark as read: \(error.localizedDescription)"
        }
    }

    func markAllAsRead() async {
        // Store original state for rollback
        let originalNotifications = notifications
        let originalUnreadCount = unreadCount

        // Optimistic update: mark all as read
        notifications = notifications.map { notification in
            NotificationItem(
                id: notification.id,
                type: notification.type,
                message: notification.message,
                timestamp: notification.timestamp,
                isRead: true,
                relatedUserId: notification.relatedUserId,
                relatedPostId: notification.relatedPostId,
                relatedCommentId: notification.relatedCommentId,
                userAvatarUrl: notification.userAvatarUrl,
                userName: notification.userName,
                postThumbnailUrl: notification.postThumbnailUrl
            )
        }
        unreadCount = 0

        // Send API request
        do {
            try await communicationService.markAllNotificationsRead()
        } catch {
            // Revert on error
            notifications = originalNotifications
            unreadCount = originalUnreadCount
            errorMessage = "Failed to mark all as read: \(error.localizedDescription)"
        }
    }

    func selectFilter(_ filter: NotificationFilter) {
        selectedFilter = filter
    }
}
