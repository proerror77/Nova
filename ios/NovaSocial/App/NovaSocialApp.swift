import SwiftUI

@main
struct NovaSocialApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var navigationState = DeepLinkNavigationState()
    @StateObject private var localizationManager = LocalizationManager.shared

    // MARK: - Accessibility Observers

    @State private var voiceOverToken: NotificationToken?
    @State private var dynamicTypeToken: NotificationToken?
    @State private var reduceMotionToken: NotificationToken?

    init() {
        // Setup accessibility observers
        setupAccessibilityObservers()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(deepLinkRouter)
                .environmentObject(navigationState)
                .environmentObject(localizationManager)
                .environment(\.locale, localizationManager.currentLanguage.locale)
                // Deep link handling - Custom URL Scheme
                .onOpenURL { url in
                    handleDeepLink(url: url)
                }
                // Deep link handling - Universal Links
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    handleDeepLink(url: url)
                }
                // Accessibility announcements on app launch
                .onAppear {
                    announceAppLaunch()
                }
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(url: URL) {
        Task { @MainActor in
            // Parse and navigate
            deepLinkRouter.handle(url: url)

            // Track analytics
            trackDeepLink(url: url)
        }
    }

    // MARK: - Accessibility Setup

    private func setupAccessibilityObservers() {
        // Observe VoiceOver status changes
        voiceOverToken = AccessibilityHelper.observeVoiceOverStatus { isEnabled in
            if isEnabled {
                print("VoiceOver enabled")
            }
        }

        // Observe Dynamic Type changes
        dynamicTypeToken = AccessibilityHelper.observeDynamicType { category in
            print("Dynamic Type changed to: \(category.rawValue)")
        }

        // Observe Reduce Motion preference
        reduceMotionToken = AccessibilityHelper.observeReduceMotion { isEnabled in
            print("Reduce Motion: \(isEnabled)")
        }
    }

    private func announceAppLaunch() {
        if AccessibilityHelper.isVoiceOverRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AccessibilityHelper.announce("NovaSocial app launched")
            }
        }
    }

    // MARK: - Analytics

    private func trackDeepLink(url: URL) {
        // TODO: Integrate with analytics service
        print("Deep link opened: \(url.absoluteString)")
    }
}

/// 全局应用状态
final class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?

    private let authRepository = AuthRepository()

    init() {
        checkAuthStatus()
    }

    func checkAuthStatus() {
        isAuthenticated = authRepository.checkLocalAuthStatus()
        currentUser = authRepository.getCurrentUser()
    }

    func signOut() {
        Task {
            try? await authRepository.logout()
            await MainActor.run {
                isAuthenticated = false
                currentUser = nil
            }
        }
    }
}
