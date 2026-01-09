import SwiftUI
import Combine

// MARK: - Presentation Style

/// Defines how a route should be presented
enum PresentationStyle {
    /// Present as a sheet (modal that slides up from bottom)
    case sheet
    /// Present as a full screen cover (covers entire screen)
    case fullScreen
    /// Push onto navigation stack
    case push
}

/// Centralized navigation coordinator for the app
/// Manages navigation state, deep links, and tab coordination
@MainActor
@Observable
final class AppCoordinator: @unchecked Sendable {
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

    /// Flag indicating voice mode should be auto-opened (set by Action Button intent)
    var shouldOpenVoiceMode: Bool = false

    // MARK: - Modal Presentation State (Centralized)

    /// Currently presented sheet route (nil = no sheet)
    var presentedSheet: AppRoute?

    /// Currently presented full screen cover route (nil = no cover)
    var presentedFullScreen: AppRoute?

    // MARK: - Modal Presentation Methods

    /// Present a route as sheet or full screen cover
    func present(_ route: AppRoute, style: PresentationStyle) {
        switch style {
        case .sheet:
            presentedSheet = route
        case .fullScreen:
            presentedFullScreen = route
        case .push:
            navigate(to: route)
        }

        #if DEBUG
        print("[AppCoordinator] Presented \(route) as \(style)")
        #endif
    }

    /// Dismiss currently presented sheet
    func dismissSheet() {
        presentedSheet = nil
    }

    /// Dismiss currently presented full screen cover
    func dismissFullScreen() {
        presentedFullScreen = nil
    }

    /// Dismiss all modals (sheet and full screen)
    func dismissAllModals() {
        presentedSheet = nil
        presentedFullScreen = nil
    }

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

        // Also process pending voice mode request if applicable
        if shouldOpenVoiceMode {
            // Voice mode flag will be handled by AliceView
            #if DEBUG
            print("[AppCoordinator] Processing pending voice mode request")
            #endif
        }
    }

    /// Navigate directly to Alice voice mode (triggered by Action Button)
    func navigateToAliceVoiceMode() {
        // If user is not authenticated, store pending action
        guard isAuthenticated else {
            pendingDeepLink = .alice
            shouldOpenVoiceMode = true
            currentPage = .login

            #if DEBUG
            print("[AppCoordinator] User not authenticated, storing voice mode request")
            #endif
            return
        }

        // Switch to Alice tab
        if selectedTab != .alice {
            resetPath(for: selectedTab)
        }
        selectedTab = .alice
        currentPage = .alice

        // Set flag for AliceView to auto-open voice mode
        shouldOpenVoiceMode = true

        #if DEBUG
        print("[AppCoordinator] Navigating to Alice Voice Mode")
        #endif
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
        case .splash, .inviteCode, .login, .phoneLogin, .phoneRegistration, .phoneEnterCode,
             .gmailEnterCode, .gmailEnterCodeLogin, .forgotPassword, .emailSentConfirmation, .resetPassword, .createAccount:
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
        // Dismiss any presented modals
        presentedSheet = nil
        presentedFullScreen = nil
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
        case .welcome: return .splash  // Welcome uses same route as splash
        case .inviteCode: return .inviteCode
        case .login: return .login
        case .phoneLogin: return .phoneLogin
        case .phoneRegistration: return .phoneRegistration
        case .phoneEnterCode(let phoneNumber): return .phoneEnterCode(phoneNumber: phoneNumber)
        case .gmailEnterCode(let email): return .gmailEnterCode(email: email)
        case .gmailEnterCodeLogin(let email): return .gmailEnterCode(email: email)  // Use same route
        case .forgotPassword: return .forgotPassword
        case .emailSentConfirmation(let email): return .emailSentConfirmation(email: email)
        case .resetPassword(let token): return .resetPassword(token: token)
        case .createAccount: return .createAccount
        case .createAccountEmail: return .createAccount  // Use same route as createAccount
        case .createAccountPhoneNumber: return .createAccount  // Use same route as createAccount
        case .profileSetup: return .profileSetup
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
        case .chatBackup: return .chatBackup
        case .callRecordings: return .callRecordings
        }
    }

    // MARK: - Modal Presentation Bindings

    /// Binding for sheet presentation (use with .sheet(item:))
    var sheetBinding: Binding<AppRoute?> {
        Binding(
            get: { self.presentedSheet },
            set: { self.presentedSheet = $0 }
        )
    }

    /// Binding for full screen cover presentation (use with .fullScreenCover(item:))
    var fullScreenBinding: Binding<AppRoute?> {
        Binding(
            get: { self.presentedFullScreen },
            set: { self.presentedFullScreen = $0 }
        )
    }

    /// Check if a specific route is currently presented as sheet
    func isSheetPresented(_ route: AppRoute) -> Bool {
        presentedSheet == route
    }

    /// Check if a specific route is currently presented as full screen cover
    func isFullScreenPresented(_ route: AppRoute) -> Bool {
        presentedFullScreen == route
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
