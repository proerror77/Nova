import UIKit
import UserNotifications

// MARK: - App Delegate

/// AppDelegate handles system-level events including push notifications
class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared

        // Enable background fetch for offline message sync
        // iOS will periodically wake the app to fetch new messages
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        #if DEBUG
        print("[AppDelegate] Application did finish launching")
        print("[AppDelegate] Background fetch enabled")
        #endif

        // Check if app was launched from a notification
        if let notificationInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            #if DEBUG
            print("[AppDelegate] Launched from notification: \(notificationInfo)")
            #endif
            // Handle the notification that launched the app
            handleLaunchNotification(notificationInfo)
        }

        return true
    }

    // MARK: - Background Fetch

    /// Called by iOS when it's time to perform a background fetch
    /// This is used to sync Matrix messages while the app is in the background
    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        #if DEBUG
        print("[AppDelegate] 🔄 Performing background fetch...")
        #endif

        Task {
            do {
                // Attempt to sync Matrix messages
                try await MatrixBridgeService.shared.resumeSync()
                #if DEBUG
                print("[AppDelegate] ✅ Background fetch completed - new data")
                #endif
                completionHandler(.newData)
            } catch {
                #if DEBUG
                print("[AppDelegate] ❌ Background fetch failed: \(error)")
                #endif
                completionHandler(.failed)
            }
        }
    }

    // MARK: - Remote Notification Registration

    /// Called when APNs successfully registers the device
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.handleDeviceToken(deviceToken)
    }

    /// Called when APNs registration fails
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.handleRegistrationError(error)
    }

    // MARK: - Remote Notification Handling

    /// Called when a remote notification arrives (silent or when app is in background)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        PushNotificationManager.shared.handleRemoteNotification(userInfo, completion: completionHandler)
    }

    // MARK: - Private Methods

    /// Handle notification that launched the app
    private func handleLaunchNotification(_ userInfo: [AnyHashable: Any]) {
        // Delay slightly to ensure app is fully initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let notificationType = userInfo["type"] as? String,
               let notificationId = userInfo["notification_id"] as? String {
                NotificationCenter.default.post(
                    name: NSNotification.Name("PushNotificationReceived"),
                    object: nil,
                    userInfo: [
                        "type": notificationType,
                        "notification_id": notificationId,
                        "user_info": userInfo,
                        "launched_from_notification": true
                    ]
                )
            }
        }
    }
}
