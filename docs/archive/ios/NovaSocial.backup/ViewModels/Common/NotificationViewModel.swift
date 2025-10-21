import Foundation
import Combine

@MainActor
final class NotificationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var notifications: [Notification] = []
    @Published var unreadCount = 0
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Private Properties
    private let notificationRepository: NotificationRepository

    // MARK: - Initialization
    init(notificationRepository: NotificationRepository = NotificationRepository()) {
        self.notificationRepository = notificationRepository
    }

    // MARK: - Public Methods

    func loadNotifications() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await notificationRepository.getNotifications(limit: 50)
            notifications = response.notifications
            unreadCount = response.unreadCount
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isLoading = false
    }

    func refreshNotifications() async {
        guard !isRefreshing else { return }

        isRefreshing = true

        do {
            let response = try await notificationRepository.getNotifications(limit: 50)
            notifications = response.notifications
            unreadCount = response.unreadCount
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isRefreshing = false
    }

    func markAsRead(notification: Notification) {
        guard !notification.isRead else { return }

        // Optimistic update
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            var updatedNotification = notification
            // Create a new notification with isRead = true
            // Since Notification is Codable, we need to handle this properly
            // For now, we'll just update the local state
            unreadCount = max(0, unreadCount - 1)
        }

        Task {
            try? await notificationRepository.markAsRead(notificationId: notification.id)
        }
    }

    func markAllAsRead() {
        unreadCount = 0

        Task {
            try? await notificationRepository.markAllAsRead()
        }
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
