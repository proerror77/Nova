import SwiftUI
import Combine

/// Centralized navigation coordinator for the app
/// Manages navigation state, deep links, and tab coordination
@MainActor
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    // MARK: - Navigation State

    /// Current page (legacy compatibility)
    var currentPage: AppPage = .splash

    /// Current main tab
    var selectedTab: MainTab = .home

    /// Navigation path for each tab
    var homePath: [AppRoute] = []
    var messagePath: [AppRoute] = []
    var alicePath: [AppRoute] = []
    var accountPath: [AppRoute] = []

    /// Pending deep link to process after authentication
    var pendingDeepLink: AppRoute?

    /// Flag to track if user is authenticated
    var isAuthenticated: Bool = false

    // MARK: - State Restoration Keys

    private let selectedTabKey = "AppCoordinator.selectedTab"
    private let pendingDeepLinkKey = "AppCoordinator.pendingDeepLink"

    private init() {
        // Note: State restoration is deferred to first access on main actor
    }

    // MARK: - Navigation Methods

    /// Navigate to a specific route
    func navigate(to route: AppRoute) {
        // If user is not authenticated and route requires auth, store as pending
        if !isAuthenticated && requiresAuthentication(route) {
            pendingDeepLink = route
            currentPage = .login
            return
        }

        // Update legacy currentPage for backward compatibility
        currentPage = route.toAppPage

        // Update tab if route belongs to a tab
        if let tab = route.mainTab {
            // If switching tabs, reset the navigation path of the new tab
            if selectedTab != tab {
                resetPath(for: tab)
            }
            selectedTab = tab

            // Push to the appropriate navigation path
            pushRoute(route, to: tab)
        }

        #if DEBUG
        print("[AppCoordinator] Navigated to: \(route)")
        #endif
    }

    /// Navigate to a tab (resets navigation path)
    func selectTab(_ tab: MainTab) {
        // Reset navigation path when switching tabs
        if selectedTab != tab {
            resetPath(for: selectedTab)
        }
        selectedTab = tab
        currentPage = tab.route.toAppPage

        #if DEBUG
        print("[AppCoordinator] Selected tab: \(tab)")
        #endif
    }

    /// Handle a deep link URL
    func handleDeepLink(_ url: URL) {
        guard let route = DeepLinkHandler.shared.parse(url: url) else {
            #if DEBUG
            print("[AppCoordinator] Failed to parse deep link: \(url)")
            #endif
            return
        }

        navigate(to: route)
    }

    /// Process pending deep link after authentication
    func processPendingDeepLink() {
        guard let pendingRoute = pendingDeepLink else { return }
        pendingDeepLink = nil
        navigate(to: pendingRoute)
    }

    /// Go back one step in navigation
    func goBack() {
        switch selectedTab {
        case .home:
            if !homePath.isEmpty {
                homePath.removeLast()
            }
        case .message:
            if !messagePath.isEmpty {
                messagePath.removeLast()
            }
        case .alice:
            if !alicePath.isEmpty {
                alicePath.removeLast()
            }
        case .account:
            if !accountPath.isEmpty {
                accountPath.removeLast()
            }
        }

        // Update currentPage based on remaining path
        updateCurrentPageFromPath()
    }

    /// Pop to root of current tab
    func popToRoot() {
        resetPath(for: selectedTab)
        currentPage = selectedTab.route.toAppPage
    }

    // MARK: - Path Management

    /// Get the navigation path for a tab
    func path(for tab: MainTab) -> [AppRoute] {
        switch tab {
        case .home: return homePath
        case .message: return messagePath
        case .alice: return alicePath
        case .account: return accountPath
        }
    }

    /// Push a route to a tab's path
    private func pushRoute(_ route: AppRoute, to tab: MainTab) {
        // Don't push if it's the root route for the tab
        if route == tab.route { return }

        switch tab {
        case .home:
            // Avoid duplicates
            if homePath.last != route {
                homePath.append(route)
            }
        case .message:
            if messagePath.last != route {
                messagePath.append(route)
            }
        case .alice:
            if alicePath.last != route {
                alicePath.append(route)
            }
        case .account:
            if accountPath.last != route {
                accountPath.append(route)
            }
        }
    }

    /// Reset navigation path for a tab
    private func resetPath(for tab: MainTab) {
        switch tab {
        case .home: homePath = []
        case .message: messagePath = []
        case .alice: alicePath = []
        case .account: accountPath = []
        }
    }

    /// Update currentPage based on the current path
    private func updateCurrentPageFromPath() {
        let path = self.path(for: selectedTab)
        if let lastRoute = path.last {
            currentPage = lastRoute.toAppPage
        } else {
            currentPage = selectedTab.route.toAppPage
        }
    }

    // MARK: - Authentication Helpers

    /// Check if a route requires authentication
    private func requiresAuthentication(_ route: AppRoute) -> Bool {
        switch route {
        case .splash, .welcome, .login, .phoneLogin, .phoneRegistration,
             .forgotPassword, .emailSentConfirmation, .resetPassword, .createAccount:
            return false
        default:
            return true
        }
    }

    /// Called when user logs in
    func onLogin() {
        isAuthenticated = true
        processPendingDeepLink()
    }

    /// Called when user logs out
    func onLogout() {
        isAuthenticated = false
        // Reset all navigation state
        homePath = []
        messagePath = []
        alicePath = []
        accountPath = []
        selectedTab = .home
        currentPage = .login
        pendingDeepLink = nil
    }

    // MARK: - State Persistence

    /// Save current state for restoration
    func saveState() {
        UserDefaults.standard.set(selectedTab.rawValue, forKey: selectedTabKey)

        if let pending = pendingDeepLink {
            if let data = try? JSONEncoder().encode(pending) {
                UserDefaults.standard.set(data, forKey: pendingDeepLinkKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: pendingDeepLinkKey)
        }
    }

    /// Restore state from persistence
    private func restoreState() {
        if let tabRaw = UserDefaults.standard.string(forKey: selectedTabKey),
           let tab = MainTab(rawValue: tabRaw) {
            selectedTab = tab
        }

        if let data = UserDefaults.standard.data(forKey: pendingDeepLinkKey),
           let route = try? JSONDecoder().decode(AppRoute.self, from: data) {
            pendingDeepLink = route
        }
    }
}

// MARK: - Binding Helpers

extension AppCoordinator {
    /// Get a binding for currentPage (for legacy views)
    var currentPageBinding: Binding<AppPage> {
        Binding(
            get: { self.currentPage },
            set: { newValue in
                // Convert AppPage to AppRoute and navigate
                let route = self.appPageToRoute(newValue)
                self.navigate(to: route)
            }
        )
    }

    /// Convert legacy AppPage to AppRoute
    private func appPageToRoute(_ page: AppPage) -> AppRoute {
        switch page {
        case .splash: return .splash
        case .welcome: return .welcome
        case .login: return .login
        case .phoneLogin: return .phoneLogin
        case .phoneRegistration: return .phoneRegistration
        case .forgotPassword: return .forgotPassword
        case .emailSentConfirmation(let email): return .emailSentConfirmation(email: email)
        case .resetPassword(let token): return .resetPassword(token: token)
        case .createAccount: return .createAccount
        case .home: return .home
        case .rankingList: return .rankingList
        case .search: return .search(query: nil)
        case .newPost: return .newPost
        case .notification: return .notification
        case .message: return .message
        case .account: return .account
        case .alice: return .alice
        case .setting: return .settings
        case .profileSetting: return .profileSetting
        case .aliasName: return .profileSetting
        case .devices: return .devices
        case .inviteFriends: return .inviteFriends
        case .myChannels: return .myChannels
        case .addFriends: return .addFriends
        case .friendRequests: return .friendRequests
        case .newChat: return .newChat
        case .write: return .write
        case .getVerified: return .getVerified
        case .groupChat: return .groupChat
        case .passkeys: return .passkeys
        }
    }
}

// MARK: - SwiftUI Environment

private struct AppCoordinatorKey: EnvironmentKey {
    static let defaultValue = AppCoordinator.shared
}

extension EnvironmentValues {
    var appCoordinator: AppCoordinator {
        get { self[AppCoordinatorKey.self] }
        set { self[AppCoordinatorKey.self] = newValue }
    }
}
