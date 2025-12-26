import UIKit
import UserNotifications
import BackgroundTasks

// MARK: - App Delegate

/// AppDelegate handles system-level events including push notifications
class AppDelegate: NSObject, UIApplicationDelegate {

    // MARK: - Background Task Identifiers

    static let backgroundRefreshTaskIdentifier = "com.icered.app.refresh"

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = PushNotificationManager.shared

        // Register background tasks using modern BackgroundTasks framework
        registerBackgroundTasks()

        #if DEBUG
        print("[AppDelegate] Application did finish launching")
        print("[AppDelegate] Background refresh task registered")
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

    // MARK: - Background Tasks (Modern API)

    /// Register background tasks with the system
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundRefreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: refreshTask)
        }
    }

    /// Schedule the next background app refresh
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshTaskIdentifier)
        // Fetch no earlier than 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[AppDelegate] 📅 Background refresh scheduled")
            #endif
        } catch {
            #if DEBUG
            print("[AppDelegate] ❌ Failed to schedule background refresh: \(error)")
            #endif
        }
    }

    /// Handle the background app refresh task
    private func handleAppRefresh(task: BGAppRefreshTask) {
        #if DEBUG
        print("[AppDelegate] 🔄 Performing background refresh...")
        #endif

        // Schedule the next refresh
        scheduleAppRefresh()

        // Create a task to sync Matrix messages
        let syncTask = Task {
            do {
                try await MatrixBridgeService.shared.resumeSync()
                #if DEBUG
                print("[AppDelegate] ✅ Background refresh completed - new data")
                #endif
                task.setTaskCompleted(success: true)
            } catch {
                #if DEBUG
                print("[AppDelegate] ❌ Background refresh failed: \(error)")
                #endif
                task.setTaskCompleted(success: false)
            }
        }

        // Handle task expiration
        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
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
