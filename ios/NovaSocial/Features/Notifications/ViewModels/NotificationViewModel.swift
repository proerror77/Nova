import Foundation
import SwiftUI

// MARK: - Notification View Model

@MainActor
class NotificationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var notifications: [NotificationItem] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Temporary Model (TODO: Move to Shared/Models)

    struct NotificationItem: Identifiable {
        let id: String
        let type: NotificationType
        let message: String
        let timestamp: Date
        let isRead: Bool
        let relatedUserId: String?
        let relatedPostId: String?
    }

    enum NotificationType {
        case like
        case comment
        case follow
        case mention
        case share
    }

    // MARK: - Lifecycle

    func loadNotifications() async {
        isLoading = true
        errorMessage = nil

        // TODO: Implement notifications loading from backend

        isLoading = false
    }

    // MARK: - Actions

    func markAsRead(_ notificationId: String) async {
        // TODO: Implement mark as read
    }

    func markAllAsRead() async {
        // TODO: Implement mark all as read
    }
}
