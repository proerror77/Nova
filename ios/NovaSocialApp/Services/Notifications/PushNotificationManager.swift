import Foundation
import UserNotifications
import UIKit

final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()
    private let repository = PushTokenRepository()
    private let deviceTokenKey = "nova.apns.deviceToken"
    private let syncedTokenKey = "nova.apns.deviceToken.synced"
    private var observers: [NSObjectProtocol] = []
    private var syncTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func configure() {
        notificationCenter.delegate = self
        registerObservers()
        requestAuthorizationIfNeeded()
        synchronizeCachedTokenIfNeeded()
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard !tokenString.isEmpty else { return }

        UserDefaults.standard.set(tokenString, forKey: deviceTokenKey)
        synchronizeCachedTokenIfNeeded(force: true)
    }

    func handleRegistrationFailure(_ error: Error) {
        Logger.log("❌ Remote notification registration failed: \(error.localizedDescription)", level: .error)
    }

    func clearCachedToken() {
        UserDefaults.standard.removeObject(forKey: syncedTokenKey)
    }

    func synchronizeCachedTokenIfNeeded(force: Bool = false) {
        guard AuthManager.shared.isAuthenticated,
              let token = UserDefaults.standard.string(forKey: deviceTokenKey),
              !token.isEmpty else {
            return
        }

        let lastSynced = UserDefaults.standard.string(forKey: syncedTokenKey)
        if !force && lastSynced == token {
            return
        }

        syncTask?.cancel()
        syncTask = nil

        syncTask = Task {
            do {
                try await repository.registerDeviceToken(
                    token: token,
                    platform: "ios",
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    locale: Locale.current.identifier
                )
                UserDefaults.standard.set(token, forKey: syncedTokenKey)
                Logger.log("📬 APNs token registered", level: .info)
            } catch {
                Logger.log("❌ Failed to register APNs token: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func requestAuthorizationIfNeeded() {
        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error = error {
                        Logger.log("❌ Notification authorization failed: \(error.localizedDescription)", level: .error)
                        return
                    }
                    if granted {
                        DispatchQueue.main.async {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            default:
                break
            }
        }
    }

    private func registerObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

        let loginObserver = NotificationCenter.default.addObserver(
            forName: .authDidLogin,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                self?.synchronizeCachedTokenIfNeeded(force: true)
            }
        }

        let logoutObserver = NotificationCenter.default.addObserver(
            forName: .authDidLogout,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCachedToken()
        }

        observers.append(contentsOf: [loginObserver, logoutObserver])
    }

    deinit {
        syncTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
