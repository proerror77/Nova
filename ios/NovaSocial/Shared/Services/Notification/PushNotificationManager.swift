import Foundation
import UserNotifications
import UIKit

// MARK: - Push Notification Manager

/// Manages push notification registration, permissions, and token handling
@MainActor
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var deviceToken: String?
    @Published var notificationSettings: UNNotificationSettings?

    // MARK: - Private Properties

    private let notificationService = NotificationService()
    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Request notification permissions from the user
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await notificationCenter.requestAuthorization(options: options)

            await MainActor.run {
                self.isAuthorized = granted
            }

            if granted {
                await registerForRemoteNotifications()
            }

            #if DEBUG
            print("[Push] Authorization \(granted ? "granted" : "denied")")
            #endif

            return granted
        } catch {
            #if DEBUG
            print("[Push] Authorization request failed: \(error)")
            #endif
            return false
        }
    }

    /// Check current notification settings
    func checkNotificationSettings() async {
        let settings = await notificationCenter.notificationSettings()

        await MainActor.run {
            self.notificationSettings = settings
            self.isAuthorized = settings.authorizationStatus == .authorized
        }

        #if DEBUG
        print("[Push] Notification status: \(settings.authorizationStatus.rawValue)")
        #endif
    }

    /// Register for remote notifications with APNs
    func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }

        #if DEBUG
        print("[Push] Registered for remote notifications")
        #endif
    }

    /// Handle successful device token registration
    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

        Task { @MainActor in
            self.deviceToken = tokenString

            #if DEBUG
            print("[Push] Device token: \(tokenString)")
            #endif

            // Register token with backend
            await registerTokenWithBackend(tokenString)
        }
    }

    /// Handle device token registration failure
    func handleRegistrationError(_ error: Error) {
        #if DEBUG
        print("[Push] Failed to register for remote notifications: \(error)")
        #endif
    }

    /// Handle received remote notification
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any], completion: @escaping (UIBackgroundFetchResult) -> Void) {
        #if DEBUG
        print("[Push] Received remote notification: \(userInfo)")
        #endif

        // Parse notification data
        if let aps = userInfo["aps"] as? [String: Any] {
            // Handle badge count
            if let badge = aps["badge"] as? Int {
                Task { @MainActor in
                    UIApplication.shared.applicationIconBadgeNumber = badge
                }
            }

            // Handle notification type and data
            if let notificationType = userInfo["type"] as? String,
               let notificationId = userInfo["notification_id"] as? String {
                handleNotificationAction(type: notificationType, notificationId: notificationId, userInfo: userInfo)
            }
        }

        completion(.newData)
    }

    /// Unregister device token (call on logout)
    func unregisterToken() async {
        guard let token = deviceToken else { return }

        do {
            try await notificationService.unregisterPushToken(token: token)

            await MainActor.run {
                self.deviceToken = nil
            }

            #if DEBUG
            print("[Push] Token unregistered successfully")
            #endif
        } catch {
            #if DEBUG
            print("[Push] Failed to unregister token: \(error)")
            #endif
        }
    }

    /// Clear badge count
    func clearBadge() {
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    // MARK: - Private Methods

    /// Register device token with backend
    private func registerTokenWithBackend(_ token: String) async {
        // Get device ID
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Get app version
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        do {
            try await notificationService.registerPushToken(
                token: token,
                platform: .apns,
                deviceId: deviceId,
                appVersion: appVersion
            )

            #if DEBUG
            print("[Push] Token registered with backend successfully")
            #endif
        } catch {
            #if DEBUG
            print("[Push] Failed to register token with backend: \(error)")
            #endif
        }
    }

    /// Handle notification action based on type
    private func handleNotificationAction(type: String, notificationId: String, userInfo: [AnyHashable: Any]) {
        // Post notification for app to handle navigation
        NotificationCenter.default.post(
            name: NSNotification.Name("PushNotificationReceived"),
            object: nil,
            userInfo: [
                "type": type,
                "notification_id": notificationId,
                "user_info": userInfo
            ]
        )

        #if DEBUG
        print("[Push] Notification action - type: \(type), id: \(notificationId)")
        #endif
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        #if DEBUG
        print("[Push] Will present notification in foreground: \(userInfo)")
        #endif

        // Show banner, sound, and badge even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap/interaction
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        #if DEBUG
        print("[Push] User interacted with notification: \(userInfo)")
        #endif

        // Handle notification tap - navigate to relevant screen
        if let notificationType = userInfo["type"] as? String,
           let notificationId = userInfo["notification_id"] as? String {
            Task { @MainActor in
                self.handleNotificationAction(type: notificationType, notificationId: notificationId, userInfo: userInfo)
            }
        }

        completionHandler()
    }
}
