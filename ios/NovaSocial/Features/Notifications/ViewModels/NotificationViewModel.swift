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

        // TODO: Implement CommunicationService.getNotifications()
        // Example:
        // do {
        //     let response = try await communicationService.getNotifications(
        //         unreadOnly: selectedFilter == .unread
        //     )
        //     notifications = response.notifications
        //     unreadCount = response.unreadCount
        // } catch {
        //     errorMessage = "Failed to load notifications: \(error.localizedDescription)"
        // }

        isLoading = false
    }

    // MARK: - Actions

    func markAsRead(_ notificationId: String) async {
        // TODO: Implement CommunicationService.markNotificationRead()
        // Example:
        // do {
        //     try await communicationService.markNotificationRead(id: notificationId)
        //     if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
        //         var updated = notifications[index]
        //         updated.isRead = true
        //         notifications[index] = updated
        //         unreadCount = max(0, unreadCount - 1)
        //     }
        // } catch {
        //     errorMessage = "Failed to mark as read: \(error.localizedDescription)"
        // }
    }

    func markAllAsRead() async {
        // TODO: Implement CommunicationService.markAllNotificationsRead()
        // Example:
        // do {
        //     try await communicationService.markAllNotificationsRead()
        //     notifications = notifications.map { var updated = $0; updated.isRead = true; return updated }
        //     unreadCount = 0
        // } catch {
        //     errorMessage = "Failed to mark all as read: \(error.localizedDescription)"
        // }
    }

    func selectFilter(_ filter: NotificationFilter) {
        selectedFilter = filter
    }
}
